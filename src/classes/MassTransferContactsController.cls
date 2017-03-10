/**
* @author Michael Smith, Force2b, LLC
* @date 04/08/2009, 01/25/2010, 03/29/2010, 05/11/2011, 10/15/2011, 07/14/2016
*
* @group Controller
*
* @description Controller for the main MassTransferContacts pages
* - REBUILD FOR LIGHTNING DESIGN SYSTEM
*
* @unit-test: MassTransferContactsController_Test
*
* @modifications:
* - 09/27/2016: Exclude GroupEventType='Proposed Event' because they cannot be transferred
*
*/
public with sharing class MassTransferContactsController {

	public String toUserId { get; set; }

	// Option to send an eMail to the owner after transferring
	public Boolean optSendeMailToOwner 		{ get; set; }
	public Boolean optTxfrTasksNotesOwned { get; set; }

	// 1=Standard Debug Mode (display page messages with state)
	// 2=Troubleshooting Debug Mode (displays the SOQL, but doesn't run the query)
	private Integer debugMode = 0;

	// Because VF doesn't really support using isAccessible() on field set members
	// when the field is in a parent object, moving this into a map by Field Name
	// that can be referenced by the VF page
	public Map<String, Boolean> fieldVisibilityMap { get; set; }

	// Collection of search results for displaying
	// List<contact> searchResults = new List<contact>();
	public List<TransferContactSearchResult> searchResults { get; set; }

	// Collection of criteria line items using Wrapper class
	private List<SearchCriteria> criteriaLines;

	// Collection of fields for criteria picklist - build this once and reuse for each line
	private Map<String, List<SelectOption>> cacheFieldSelectValues = new Map<String, List<SelectOption>>();

	// Flag to identify when a transfer was just completed and running the query a second time for additional records
	private Boolean transferJustCompleted = false;

	// Returns true if there are Community/Portal Users in the Org
	public Boolean gethasCommunityUsers() {
		return [SELECT Count() FROM User WHERE IsActive = True AND ContactId != null] > 0;
	}

	// ------------------------------------------------
	// Constructor Method
	// ------------------------------------------------
	public MassTransferContactsController() {
		String dmode = apexPages.currentPage().getParameters().get('debug');
		if (dmode == null) {
			this.debugMode = 0;
		} else {
			this.debugMode = Integer.valueOf(dmode);
		}

		// Build a cached list of Contact/Account fields for the criteria picklist
		buildSearchFieldsList();

		// Init the criteria object to be used on the page via <Apex:DataTable>
		this.criteriaLines = new List<SearchCriteria>();
		for (integer j = 0; j < 5; j++) {
				SearchCriteria c = new SearchCriteria();
				if (j < 4) {
					c.logical = 'AND';
				}
				this.criteriaLines.add(c);
		}
	}

// ------------------------------------------------

	// Returns the date format (MM/DD/YYYY, DD/MM/YYYY, etc.) that criteria should be entered in
	// This is determined in the CriteriaWrapper class by loooking at the users Locale settings
	public string getInputDateFormat() {
		return criteriaLines[0].getInputDateFormat() ;
	}

// ------------------------------------------------

	// Return the list of Contact/Account fields for the criteria picklists
	public List<SelectOption> getContactFieldsPicklist() {
		return this.cacheFieldSelectValues.get('Contact');
	}
	public List<SelectOption> getAccountFieldsPicklist() {
		return this.cacheFieldSelectValues.get('Account');
	}
	public List<SelectOption> getUserFieldsPicklist() {
		return this.cacheFieldSelectValues.get('User');
	}

	// Create a SelectOption list Contact & Account fields for a select list
	// Uses a method in the Criteria Class to build the select lists for the two objects
	private void buildSearchFieldsList() {

		if (cacheFieldSelectValues.size() == 0) {
			cacheFieldSelectValues.put('User', new List<SelectOption>{
				new ApexPages.SelectOption('_active_', 'Owner: Active Standard Users'),
				new ApexPages.SelectOption('_inactive_', 'Owner: Inactive Users')
			});
			if (gethasCommunityUsers()) {
				cacheFieldSelectValues.get('User').add(
					new ApexPages.SelectOption('_community_', 'Owner: Community/Portal Users')
				);
			}

			// Create the Maps of Fields for the Contact and Account objects
			Map<String, Schema.SObjectField> accountFieldsMap = Schema.SObjectType.Account.fields.getMap();
			Map<String, Schema.SObjectField> contactFieldsMap = Schema.SObjectType.Contact.fields.getMap();

			// Return SelectOption lists for the Contact and Account objects
			searchCriteria critClass = new searchCriteria();

			List<SelectOption> sel1 = critClass.GetFieldsForObject(contactFieldsMap, '', '');
			List<SelectOption> sel2 = critClass.GetFieldsForObject(accountFieldsMap, 'Account.', 'Account.');

			cacheFieldSelectValues.put('Contact', critClass.GetFieldsForObject(contactFieldsMap, '', ''));
			cacheFieldSelectValues.put('Account', critClass.GetFieldsForObject(accountFieldsMap, 'Account.', 'Account.'));
		}
	}

	// ------------------------------------------------
	// Returns a List<> of Criteria Objects for use with <Apex:DataTable>
	// to allow multiple lines to be displayed and the values retrievable
	// ------------------------------------------------
	public List<SearchCriteria> getSearchCriteria() {
		return criteriaLines;
	}

	// -------------------------------------------------------------------------------------
	// SEARCH BUTTON:
	// Builds SOQL Statement based on selection criteria
	// Fills searchResults[] list
	// -------------------------------------------------------------------------------------
	public pageReference searchForContacts() {

		// If no To User is selected, then show error and return
		if (String.isEmpty(toUserID)) {
				ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.Error,
					'Warning', 'A "Transfer To User" Must be Selected'));
				return null;
		}

		String soql = 'SELECT Id,';

		// NOTE: The key on these are lowercase
		Map<String, Schema.SObjectField> accountFieldMap = Schema.SObjectType.Account.fields.getMap();
		Map<String, Schema.SObjectField> userFieldMap = Schema.SObjectType.Account.fields.getMap();
		Map<String, Schema.SObjectField> contactFieldsMap = Schema.SObjectType.Contact.fields.getMap();

		Schema.FieldSet listFields = SObjectType.Contact.FieldSets.MassTransferContacts_Results_List_Column;
		Schema.DescribeFieldResult fieldResult;
		this.fieldVisibilityMap = new Map<String, Boolean>();
		for (Schema.FieldSetMember f : listFields.getFields()) {
			if (this.debugMode == 2) {
				ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.INFO, 'Field: ' + f.getFieldPath(), ''));
			}
			if (f.getFieldPath().contains('.')) {
				String fldName = f.getFieldPath().split('\\.')[1].toLowerCase();
				String objName = f.getFieldPath().split('\\.')[0];
				if (this.debugMode == 2) {
					ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.INFO,
						' -- Object: ' + objName, ' -- Field: ' + fldName));
				}
				if (objName == 'Account') {
					fieldResult = accountFieldMap.get(fldName).getDescribe();
				} else if (objName == 'User') {
					fieldResult = userFieldMap.get(fldName).getDescribe();
				}
			} else {
				fieldResult = contactFieldsMap.get(f.getFieldPath().toLowerCase()).getDescribe();
			}
			this.fieldVisibilityMap.put(f.getFieldPath(), fieldResult.isAccessible());
			if (f.getFieldPath() != 'Id' && fieldResult.isAccessible()) {
				soql += f.getFieldPath() + ',';
			}
		}
		soql = soql.removeEnd(',') + ' FROM Contact WHERE ' +
		 ' OwnerId != \'' + String.escapeSingleQuotes(this.toUserId) + '\' ';

		// If PersonAccounts is enabled for the Org, be sure to exclude
		// all of these in the query
		if (contactFieldsMap.containsKey('ispersonaccount')) {
			soql += ' AND IsPersonAccount = False ';
		}

		// For each criteria line item, call the method to build the where clause component
		for (SearchCriteria cl : this.criteriaLines) {
			soql += cl.buildWhereClause(this.debugMode > 0);
		}
		if (soql.endsWith(' WHERE ')) {
			soql = soql.removeEnd(' WHERE ');
		}
		soql = soql.replace('WHERE  AND', 'WHERE ');

		// Sort the results and limit to the first 800 rows
		soql += ' ORDER BY Account.Name, Name LIMIT 800' ;

		// Debug: Display the SOQL Query string
		if (this.debugMode > 0) {
			ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.INFO,
				'SOQL', soql));
			if (this.debugMode == 2) {
				// in this case, only display the SOQL but don't run the query
				return null;
			}
		}

		// Run the database query and place results into the TransferContactSearchResult class
		try {
				searchResults = new List<TransferContactSearchResult>();
				List<Contact> results = Database.Query(soql);

				// If zero or more than 800 records returned, display a message
				if (results.size() > 800) {
					ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.INFO,
						'NOTE: Only the first 800 rows are displayed.', ''));
				}
				if (results.size() == 0 && !transferJustCompleted) {
					ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.ERROR,
						'NO RECORDS FOUND', ''));
				}

				// Build the searchResults[] list used by the Apex:DataTable tag on the page
				for (Contact c : results) {
					searchResults.add(new TransferContactSearchResult(c) ) ;
				}

		} catch (Exception ex) {
			// ERROR! Display message on screen
			ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.ERROR,
				'Error', 'Query Error: ' + ex.getMessage()));
		}

		this.transferJustCompleted = false;     // Reset the flag used to track when a transfer was completed versus a new query
		return null;
	}

	// ----------------------------------------------------------------------
	// Transfer Button:
	// - Query the selected contacts
	// - Change the OwnerId
	// - Call database.update()
	// - Check for errors
	// - Send an eMail if needed
	// - Rerun the query to display any remaining contacts
	// ----------------------------------------------------------------------
	public pageReference doTransfer() {

		if (String.isEmpty(toUserId)) {
			ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.ERROR,
				'ERROR: A "To User" must be specified', ''));
			return null;
		}

		// Build a list of Contact ID's to transfer ownership for
		List<Id> contactIdsToTransfer = New List<Id>();
		for (TransferContactSearchResult c : searchResults) {
			if (c.selected) {
				contactIdsToTransfer.add(c.contactID) ;
			}
		}
		if (this.debugMode > 0) {
			ApexPages.AddMessage(new ApexPages.Message(
				ApexPages.Severity.INFO, 'Selected Count: ' + contactIdsToTransfer.size(), ''));
		}

		// set a database savepoint that can be used to rollback the changes if it fails
		SavePoint sp = database.setSavepoint();

		List<Database.Saveresult> srs;
		Integer transferCount = 0;

		// MGS 10/22/2009: Add support for transferring Open Tasks, Notes, and Attachments to the new owner
		// EP 6/18/2010: moved the contact update to later so that we can compare original contact owner in Tasks/Notes transfer instead of
		//              using unreliably populated fromUserId variable
		List<SObject> txfrNotes = New List<SObject>();
		List<SObject> txfrAttachments = New List<SObject>();
		List<SObject> txfrTasks = New List<SObject>();
		List<SObject> txfrEvents = New List<SObject>();
		String whereAmI;
		try {
			if (optTxfrTasksNotesOwned && contactIdsToTransfer.size() > 0) {
				System.debug(LoggingLevel.Error, '++++ Transferring Tasks/Notes/Attachments');

				whereAmI = 'Gather Records to Transfer';
				// Query the Contacts and their related Notes, Attachments, and Tasks to be transferred
				// MGS, 06/22/2010: Limit the Sub-Queries to 1000 records because SalesForce
				//    seems to have an issue with more than that
				// MGS, 09/27/2016: 'Proposed Event' type Events cannot be transferred
				for (Contact c : [SELECT Id, OwnerId,
							(SELECT Id, OwnerId FROM Notes),
							(SELECT Id, OwnerId FROM Attachments),
							(SELECT Id, OwnerId FROM Tasks WHERE isClosed = False),
							(SELECT Id, OwnerId FROM Events WHERE GroupEventType != 'Proposed Event')
						FROM Contact WHERE Id IN :contactIdsToTransfer]) {

					txfrAttachments.addAll(changeChildRecordOwners(c.Attachments, c.OwnerId, toUserId));
					txfrTasks.addAll(changeChildRecordOwners(c.Tasks, c.OwnerId, toUserId));
					txfrEvents.addAll(changeChildRecordOwners(c.Events, c.OwnerId, toUserId));
					txfrNotes.addAll(changeChildRecordOwners(c.Notes, c.OwnerId, toUserId));
				} // for next contact

				// Transfer the owner on all child objects
				updateChildObject(txfrAttachments);
				updateChildObject(txfrTasks);
				updateChildObject(txfrEvents);
				updateChildObject(txfrNotes);
			}
		} catch (exception e) {
			// Rollback the database due to a failure transferring child records
			ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.FATAL,
				'Error Transferring at ' + whereAmI, e.getMessage() ));
			database.rollback(sp);
			return null;
		}

		// EP 6/18/2010: moved the contact update to later so that we can compare original contact owner in Tasks/Notes transfer instead of
		//				using unreliably populated fromUserId variable
		// Query the contacts being transferred
		List<Contact> contacts = new List<Contact>();
		for (Id cId : contactIdsToTransfer) {
			contacts.add(new Contact(
				Id = cId,
				OwnerId = toUserId
			));
		}
		if (this.debugMode > 0) {
			ApexPages.AddMessage(new ApexPages.Message(
				ApexPages.Severity.INFO, 'Query Size: ' + contacts.size(), ''));
		}

		// Process Errors and Count the Number of Records Transferred
		Set<Id> transferredIds = New Set<Id>(); // Remember which contacts were transferred
		try {
			srs = database.update(contacts);
			for (database.saveresult sr : srs) {
					if (!sr.isSuccess()) {
						ApexPages.AddMessage(new ApexPages.Message(
							ApexPages.Severity.FATAL, sr.getId(), sr.getErrors()[0].getMessage() ));
					} else {
						transferredIds.add(sr.getId());
					}
			}
			transferCount = transferredIds.size();

		} catch (DMLexception e) {

				// 10/30/2009: Catch errors here and try to give a nicer message to the user
				// Log the Errors and Rollback the changes
				for (integer i = 0; i < e.getNumDml(); i++) {
						ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.FATAL,
							 e.GetDmlId(i), e.getDmlMessage(i) ));
				}
				database.rollback(sp);
				return null;
		}

		// Display the Transfer Count
		ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.CONFIRM,
			transferCount + ' Records Successfully Transfered', '' ));

		// If the 'Send eMail to New Owner' option is checked:
		if (optSendeMailToOwner && transferCount > 0) {
			// Requery the contacts to figure out which were transferred and which were not.
			contacts = new List<Contact>();
			for (Contact c : [SELECT ID, OwnerId, Name, Account.Name, Title, Owner.Alias
						FROM Contact WHERE Id IN :contactIdsToTransfer]) {
				if (c.OwnerId == toUserID) {
					contacts.add(c);
				}
			}
			sendEMail(contacts);
		}

		// Set the flag that this just finished
		transferJustCompleted = true;

		// Re-run the [Search] button functionality.
		searchForContacts();

		return null;
	}

	// ----------------------------------------------------------------------
	// If the 'Send eMail to New Owner' option is checked
	// Send a simple email with Text/Html body listing the contacts just transferred
	// Called by doTransfer() passing in the contacts[] list.
	// ----------------------------------------------------------------------
	private boolean sendEMail(List<Contact> TransferedContacts) {
		String htmlBody = '<HTML><BODY><h3>';
		String textBody = '';

		htmlbody += 'The following Contacts were just transferred to you by ' + UserInfo.getName() + '</h3>';
		textBody += 'The following Contacts were just transferred to you ' + UserInfo.getName() + ':\r\r';

			// Build table/list of Contacts Transferred
		htmlBody += '<Table width="100%"><TR><TD width="25%"><B>Contact Name</B></TD><TD width="25%"><B>Account Name</B></TD>' +
			 '<TD width="25%"><B>Title</B></TD><TD><B>Old Owner</B></TD></TR>';
		textBody += 'CONTACT NAME\t\t\tACCOUNT NAME\t\t\tTITLE\t\t\tOLD OWNER\r';

		// Use this to get the base URL of the SalesForce instance
		String BaseURL = ApexPages.currentPage().getHeaders().get('Host');

		// Build the table/list of contacts
		// Make the Name field a link to the contact
		for (Contact c : TransferedContacts) {
			PageReference cView = new ApexPages.StandardController(c).view();
			htmlBody += '<TR><TD><a href="' + BaseURL + cView.getUrl() + '">' +
					c.Name + '</a></TD><TD>' + null2String(c.Account.Name) +
					'</TD><TD>' + null2String(c.Title) + '</TD><TD>' + c.Owner.Alias +
					'</TD></TR>';
			textBody += c.Name + '\t\t\t' + null2String(c.Account.Name) + '\t\t\t' +
				null2String(c.Title) + '\t\t\t' + c.Owner.Alias + '\r';
		}
		htmlBody += '</Table>';

		// Get the target user eMail address
		User user = [SELECT ID, eMail FROM User Where ID = :toUserID Limit 1];

		// Create the eMail object
		Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

		// Set the TO address
		String[] toAddresses = new String[] {user.Email};
		mail.setToAddresses(toAddresses);

		// Specify the name used as the display name.
		mail.setSenderDisplayName(UserInfo.getName());

		// Specify the subject line for your email address.
		mail.setSubject(TransferedContacts.size() + ' Contacts Transferred To You');

		// Set options
		mail.setBccSender(false);
		mail.setUseSignature(false);

		// Specify the text content of the email.
		mail.setPlainTextBody(textBody);
		mail.setHtmlBody(htmlBody);

		// Send the email
		Messaging.SendEmailResult [] sr = Messaging.sendEmail(
			new Messaging.SingleEmailMessage[] { mail });

		if (!sr[0].isSuccess()) {
			// Error sending the message; display the error on the page
			Messaging.SendEmailError r = sr[0].getErrors()[0];
			ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.ERROR,
				'Unable to send Email message to the new Owner', sr[0].getErrors()[0].getMessage() ));
			return false;
		} else {
			return true;
		}

	}

	// Simple function to convert NULL to ''
	private string null2String(string s) {
		if (s == null) {
			return '';
		} else {
			return s;
		}
	}

	/**
	 * Javascript Remoting Method to use for the "To Users" lookup via SLDS
	 */
	@RemoteAction
	public static List<User> searchUsers(String searchKey, String userType) {
		List<User> users = new List<User>();
		try {
			if (searchKey != null) {
				searchKey = '%' + String.escapeSingleQuotes(searchKey) + '%';
				String soql = 'SELECT Id, Name, UserName, UserType, UserRole.Name FROM User ' +
					' WHERE Name LIKE :searchKey ' +
					' AND UserType != \'Guest\' ' +
					' AND UserType != \'SelfService\' ' +
					' AND UserType != \'CsnOnly\' ';

				if (userType == '_active_') {
					// Filter on Active Standard Users only
					soql += ' AND IsActive = True ' +
						' AND UserType = \'Standard\'';

				} else if (userType == '_inactive_') {
					// Filter on Inactive Users of any kind (other than Guest, etc.)
					soql += ' AND IsActive = False ';

				} else if (userType == '_community_') {
					// Filter on Active Community of any kind (other than Guest, etc.)
					soql += ' AND IsActive = True ' +
						' AND UserType != \'Standard\'' +
						' AND ContactId != null';

				} else  {
					// Filter on Active Users of any kind that can become a 'To' User
					soql += ' AND IsActive = True ';

				}

				soql += ' ORDER BY LastName, FirstName LIMIT 15';
				users = database.query(soql);
			}
		} catch (exception e) { }
		return users;
	}

	/*
	* Utility method to change the owners of child records in an SObject
	* Doesn't commit the changes though
	*/
	private List<SObject> changeChildRecordOwners(List<SObject> records, Id contactOwnerId, Id newOwnerId) {

		List<SObject> updated = new List<SObject>();
		try {
			for (SObject s : records) {
				if (s.get('OwnerId') == contactOwnerId) {
					s.put('OwnerId', newOwnerId);
					updated.add(s);
				}
			}
		} catch (exception ex) { }
		return updated;
	}

	/*
	* Utility method to update child SObjects and validate success
	*/
	private Boolean updateChildObject(List<Sobject> records) {

		// Need to split this into blocks of 200 or less
		if (records == null || records.size() == 0) {
			return true;
		}

		List<Sobject> batchedRecords = New List<Sobject>();
		Integer recNo = 0;
		while (recNo < records.size()) {
			for (Sobject c : records) {
				batchedRecords.add(c);
				recNo++;
				if (batchedRecords.size() == 200) {
					break;
				}
			}
			for (database.saveresult sr : database.update(batchedRecords, false)) {
				if (!sr.isSuccess()) {
					ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.FATAL,
						sr.getId(), sr.getErrors()[0].getMessage() ));
				}
			}
			batchedRecords.clear();
		}
		return true;
	}

	/* -------------------------------------------------------------------------------------
	* TransferContactSearchResult: Mass Transfer Search Results Wrapper Class
	* - Used by the TransferContacts Class and Page
	* - Main purpose is to return a LIST of Contacts along with a custom checkbox that can
	*   be used to let the user select which rows to transfer and which to ignore.
	*  ------------------------------------------------------------------------------------- */
	public class TransferContactSearchResult {
		public Boolean selected { get; set; }
		public String contactId { get; set; }
		public transient Contact contact  { get; private set; }

		public TransferContactSearchResult() { }
		public TransferContactSearchResult(Contact c) {
			this.contact = c;
			this.contactID = c.id;
			this.selected = true;
		}
	}
}