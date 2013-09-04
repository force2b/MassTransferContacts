/* ******************************************************************************************
* Class: TransferContacts -- Controller for the TransferContacts page
* Created: M.Smith, 04/08/2009, 01/25/2010, 03/29/2010, 05/11/2011, 10/15/2011
* http://www.force2b.net 
*
* Mass Contact Transfer Controller Class
* - Used by the TransferContacts Page
* - Works with the TransferContactsSearchResults and searchCriteria Classes
*
* Modifications:
* - M.Smith, 10/22/2009: Add support for transferring Open Tasks, Notes, and Attachments
* - M.Smith, 01/25/2010: Convert the TO USER field to a lookup value
* - M.Smith, 03/29/2010: Apparently, the FROM USER Lookup field does not support In-Active Users
*       - Resolve this by adding a link for "Show Inactive Users" to the page
*       - If clicked, it hides the "Active User Lookup" and replaces it with a picklist of
*         inactive users; and relabels the link to "Show Active Users"
* - E.Peterson, 06/18/2010: 
*   - Changed the order of transfer so that Contacts were transferred last. 
*     This allowed me to compare the child record (Task/Note/Attachment) OwnerID to the 
*     Contact OwnerID, since it seemed like fromUserID variable wasn't always populated.
*   - Included child records in the total records transferred count
*   - Added support for transferring Events
*   - Added testing support for Events
*   - Added testing support for Attachments
* - M.Smith, 05/11/2011:
*   - Rewrite some functionality to be more effecient
*   - Use a transient contact property in the transferContactResults subclass
*   - Check for 'IsPersonAccount' field and exclude those from query if field exists
*   - Change API version to 20 
* - M.Smith, 05/25/2011: Don't include TEXTAREA and Encrypted fields in the SOQL
* - M.Smith, 10/15/2011
*       - In the Contact Search Results stop using URLFOR() because some PE users are getting errors
*       - Update the 'From' user logic to work with Inactive AND Portal user types as well as Active users 
******************************************************************************************* */
public With Sharing class transferContacts {

    // From and To UserID's - PICKLIST VERSIONS
    public string fromUserID { get; set; }      // still using this for a picklist of inactive values
    private string toUserID { get; set; }       // internal use only since using a lookup on the page

    // From and To UserID's - LOOKUP VERSIONS
    // M.Smith, 01/25/2010: Enable lookup of the TO USER instead of a pick list.
    public Contact proxyAcctLookupTO = new Contact();
    public Contact proxyAcctLookupFROM = new Contact();
    public Contact gettoUserLookup()   { return proxyAcctLookupTO; }
    public Contact getfromUserLookup() { return proxyAcctLookupFROM; }

    // Option to send an eMail to the owner after transferring
    public boolean optSendeMailToOwner { get; set; }

    // 10/22/2009: Option to transfer Tasks, Notes, and Attachments
    public boolean optTxfrTasksNotesOwned { get; set; }

    // 02/17/2010: Option to show/hide inactive users picklist
    public string optShowUserType { get; set; }

    // If this is set to TRUE (by an InputHidden tag on the page) then show SOQL and other debug messages
    public boolean DebugMode = false;

    // Collection of search results for displaying
    // List<contact> searchResults = new List<contact>();
    public List<transferContactSearchResults> searchResults = new List<transferContactSearchResults>();

    // Collection of criteria line items using Wrapper class
    public List<searchCriteria> criteriaLine = New List<searchCriteria>();

    // Collection of fields for criteria picklist - build this once and reuse for each line
    public List<SelectOption> cacheFieldSelectValues = new List<SelectOption>();

    // Flag to identify when a transfer was just completed and running the query a second time for additional records
    private Boolean transferJustCompleted = false;

    // Capture a Map and Set of Contact Fields so we only do the Describe ONCE per instance
    private Map<String, Schema.SObjectField> contactFieldMap = null;

    // ------------------------------------------------
    // Constructor Method
    // ------------------------------------------------
    public transferContacts() {

        DebugMode = (apexPages.currentPage().getParameters().get('debug') != null
        && apexPages.currentPage().getParameters().get('debug') == '1') ;
        
        // Build a cached list of Contact/Account fields for the criteria picklist
        BuildSearchFieldsList();

        // Init the criteria object to be used on the page via <Apex:DataTable>
        for (integer j = 0; j < 5; j++) {
            searchCriteria critLine = new searchCriteria();
            critLine.SearchField = '';
            critLine.SearchOperator = '';
            critLine.SearchValue = '';
            if (j < 4) critLine.Logical = 'AND';
            criteriaLine.add(critLine);
        }

        // Define the private vars of the Map and Set of Contact Fields
        // so we only do the describe one time
        contactFieldMap = Schema.SObjectType.Contact.fields.getMap();
        
        this.optShowUserType = 'Standard';
    }

// ------------------------------------------------

    // Returns the date format (MM/DD/YYYY, DD/MM/YYYY, etc.) that criteria should be entered in
    // This is determined in the CriteriaWrapper class by loooking at the users Locale settings
    public string getInputDateFormat() { return criteriaLine[0].getInputDateFormat() ; }

// ------------------------------------------------
    public pageReference updateFromUserList() {
    	this.fromUserID = null;
    	return null;
    }

    // Create a SelectOption list of all usernames in the User table (active and inactive)
    public List<SelectOption> getFromUsersOther() {
        integer queryLimit = (Test.isRunningTest()) ? 10 : 999;
        List<SelectOption> options = new List<SelectOption>();
        if (this.optShowUserType == 'Portal') {
            options.add(new selectOption('', '--- Select a Portal User ---'));
            for (User u : [Select ID, Name FROM User WHERE IsActive = True AND 
            (UserType = 'PowerPartner' OR UserType = 'PowerCustomerSuccess' OR UserType = 'CustomerSuccess') 
            Order by Name LIMIT :queryLimit]) {
                options.add(new selectOption(u.ID, u.Name));
            }
        } else {
	        options.add(new selectOption('', '--- Select an Inactive User ---'));
	        for (User u : [Select ID, Name FROM User WHERE IsActive = False 
	        Order by Name LIMIT :queryLimit]) {
	            options.add(new selectOption(u.ID, u.Name));
	        }
        }
        return options;
    }

    // Return the list of Contact/Account fields for the criteria picklists
    public List<SelectOption> getsearchFields() {
        return this.cacheFieldSelectValues;
    }

    // Create a SelectOption list Contact & Account fields for a select list
    // Uses a method in the Criteria Class to build the select lists for the two objects
    private void BuildSearchFieldsList() {

        if (cacheFieldSelectValues.size() == 0) {

            // Create the Schema Lists for the Contact and Account objects
            Schema.DescribeSObjectResult contactDescribe = Contact.sObjectType.getDescribe();
            Schema.DescribeSObjectResult accountDescribe = Account.sObjectType.getDescribe();

            // Create the Maps of Fields for the Contact and Account objects
            Map<String, Schema.SObjectField> contactFields = Schema.SObjectType.Contact.fields.getMap();
            Map<String, Schema.SObjectField> accountFields = Schema.SObjectType.Account.fields.getMap();

            searchCriteria critClass = new searchCriteria();

            // Return SelectOption lists for the Contact and Account objects
            List<SelectOption> sel1 = critClass.GetFieldsForObject(contactFields, '', '');
            List<SelectOption> sel2 = critClass.GetFieldsForObject(accountFields, 'Account.', 'Account.');

            // Combine the two returned SelectOption[] lists into a single list
            List<SelectOption> options = new List<SelectOption>();
            options.add(new selectOption('', '- select field -'));
            for (Selectoption selOpt : sel1) {
                options.add(selOpt);
            }
            for (Selectoption selOpt : sel2) {
                options.add(selOpt);
            }

            // Set the cached value so we only do this once per instance
            cacheFieldSelectValues = options;

        }
    }

    // ------------------------------------------------
    // Returns a List<> of Criteria Objects for use with <Apex:DataTable>
    // to allow multiple lines to be displayed and the values retrievable
    // ------------------------------------------------
    public list<searchCriteria> getsearchCriteria() {
        return criteriaLine;
    }

	// -------------------------------------------------------------------------------------
	// SEARCH BUTTON:
	// Builds SOQL Statement based on selection criteria
	// Fills searchResults[] list
	// -------------------------------------------------------------------------------------
    public pageReference doSearch() {

        // Retrieve the To & From user ID's from the lookup field
        this.toUserID = proxyAcctLookupTO.OwnerId;

        // if not showing InActive users, then get the FROM user from the LOOKUP
        // otherwise, just use the value from the picklist of Inactive users
        if (this.optShowUserType == 'Standard') this.fromUserID = proxyAcctLookupFROM.OwnerId;

        // If no TOUser selected, then show error and return
        if (toUserID == null) {
            ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.FATAL, 'A "Transfer To User" Must be Selected'));
            return null;
        }

        // Build a list of ALL Contact Fields for the Query.
        // This allows the user to modify the VisualForce page to show any
        // columns they want in the display without having to modify the Class
        // in a development environment.
        Set <String> contactFlds = contactFieldMap.keySet();
        boolean isPersonAccounts = false;
        string contactFieldsList = '';
        for (string f : contactFlds) {
            string fldType = ('' + contactFieldMap.get(f).getDescribe().getType()).replace('Schema.DisplayType.', '') ;
            // M.Smith, 05/25/2011: Ignore TEXTAREA and Encrypted fields in the SOQL
            if (fldType <> 'REFERENCE' && fldType <> 'TEXTAREA' && fldType <> 'ENCRYPTEDSTRING'
            && f <> 'IsDeleted' && f <> 'SystemModstamp') {
                if (contactFieldsList <> '') contactFieldsList += ', ';
                contactFieldsList += f;
                if (f.toUpperCase() == 'ISPERSONACCOUNT') isPersonAccounts = true;
            }
        }

        // Build the base SOQL String, querying the standard Contact fields WHERE the current OwnerID = the selected value
        string cSOQL = 'SELECT ' + contactFieldsList + ', Account.Name, Account.Site, Account.Owner.Name, '  +
            'Account.Industry, Account.Type, Account.Owner.Alias, ' +
            'Owner.Name, Owner.Alias, CreatedBy.Name, CreatedBy.Alias, LastModifiedBy.Name, LastModifiedBy.Alias ' +
            'FROM Contact WHERE OwnerID <> \'' + String.escapeSingleQuotes(toUserID) + '\' ';

        // If a From User was selected, add this to the critiera
        if (fromUserID <> null) cSOQL += ' AND OwnerID = \'' + String.escapeSingleQuotes(fromUserID) + '\' ';

        // If PersonAccounts is enabled for the Org, be sure to exclude all of these in the query
        if (isPersonAccounts) cSOQL += ' AND IsPersonAccount = False ';
        
        // For each criteria line item, call the method to build the where clause component
        for (searchCriteria cl : criteriaLine) {
                cSOQL += cl.buildWhereClause(DebugMode);
        }

        // Sort the results and limit to the first 250 rows
        cSOQL += ' ORDER BY Account.Name, Name LIMIT 250' ;

        // Debug: Display the SOQL Query string
        if (DebugMode) ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.INFO, cSOQL));

        // Run the database query and place results into the TransferContactSearchResults class
        try {
            searchResults.clear();
            List<Contact> results = Database.Query(cSOQL);

            // If zero or more than 250 records returned, display a message
            if (results.size() > 250) ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.INFO, 'NOTE: Only the first 250 rows are displayed.'));
            if (results.size() == 0 && !transferJustCompleted) ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.INFO, 'NO RECORDS FOUND.'));

            // Build the searchResults[] list used by the Apex:DataTable tag on the page
            for (Contact c : results) {
                searchResults.add( new transferContactSearchResults(c) ) ;
            }

        } catch (Exception ex) {
                // ERROR! Display message on screen
            ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'Query Error: ' + ex.getMessage()));
        }

        transferJustCompleted = false;     // Reset the flag used to track when a transfer was completed versus a new query
        return null;

    }

    // Return searchResults to the DATAGRID
    public list<transferContactSearchResults> getSearchResults() {
        if (fromUserID != '') {
            return this.searchResults;
        } else {
            return null ;
        }
    }

    /* // Used with the Style attribute on the OutputPanel tag show the search results if there are any
    public string getShowBlockIfResults() {
        if (this.searchResults.size() > 0) {
            return 'display: block;' ;
        } else {
            return 'display: none;' ;
        }
    } */

    // ----------------------------------------------------------------------
    // Transfer Button:
    // - Query the selected contacts
    // - Change the OwnerID
    // - Call database.update()
    // - Check for errors
    // - Send an eMail if needed
    // - Rerun the query to display any remaining contacts
    // ----------------------------------------------------------------------
    public pageReference doTransfer() {

        if (toUserID == '' || toUserID == null) {
        	ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'ERROR: A "To User" must be specified'));
        	return null;
        }

        // Build a list of Contact ID's to transfer ownership for
        List<string> IDs = New List<string>();
        for (transferContactSearchResults c : searchResults) {
            if (c.selected) IDs.add(c.contactID) ;
        }
        if (DebugMode) ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.INFO, 'Selected Count: ' + IDs.size()));
        
        // set a database savepoint that can be used to rollback the changes if it fails
        SavePoint sp = database.setSavepoint();
        
        List<database.saveresult> srs = null;
        Integer transferCount = 0;
        
        // MGS 10/22/2009: Add support for transferring Open Tasks, Notes, and Attachments to the new owner
        // EP 6/18/2010: moved the contact update to later so that we can compare original contact owner in Tasks/Notes transfer instead of 
        //              using unreliably populated fromUserId variable 
        List<Note> txfrNotes = New List<Note>();
        List<Attachment> txfrAttachments = New List<Attachment>();
        List<Task> txfrTasks = New List<Task>();
        List<Event> txfrEvents = New List<Event>();
        string whereAmI;
        try {
	        if (optTxfrTasksNotesOwned && IDs.size() > 0) {
	        	System.debug(LoggingLevel.Error, '++++ Transferring Tasks/Notes/Attachments');

	            whereAmI = 'Gather Records to Transfer';
	            // Query the Contacts and their related Notes, Attachments, and Tasks to be transferred
	            // MGS, 06/22/2010: Limit the Sub-Queries to 1000 records because SalesForce
	            //    seems to have an issue with more than that
	            for (Contact c : [SELECT ID, Name, OwnerID,
	            (Select ID, OwnerID, Title From Notes),
	            (Select ID, OwnerID, Name From Attachments ),
	            (Select ID, OwnerID, IsClosed From Tasks ),
	            (Select ID, OwnerID From Events )
	            FROM Contact WHERE ID IN :IDs]) {
	                /* System.Debug(LoggingLevel.Error, '++++ Contact Related Items for ' + c.Name);
                    if (c.Notes <> null)        System.Debug(LoggingLevel.Error, '+    Notes.size=' + c.Notes.size());
                    if (c.Attachments <> null)  System.Debug(LoggingLevel.Error, '+    Attachments.size=' + c.Attachments.size());
                    if (c.Tasks <> null)        System.Debug(LoggingLevel.Error, '+    Tasks.size=' + c.Tasks.size());
                    if (c.Events <> null)       System.Debug(LoggingLevel.Error, '+    Events.size=' + c.Events.size()); */

                    // 10/29/0211: Add try/catch blocks to prevent the dreaded
                    // 'Aggregrate query has too many rows' error.
                    try {
		                //if (c.Notes <> null) 
		                   for (Note n : c.Notes) { 
		                   	   if (n.OwnerID == c.OwnerID) txfrNotes.add(n); 
	                   	   }
                    } catch (exception ex) { }
                   	   
                    try {
		                //if (c.Attachments <> null) 
		                   for (Attachment at : c.Attachments) { 
		                   	   if (at.OwnerID == c.OwnerID) txfrAttachments.add(at);  
	                   	   }
                    } catch (exception ex) { }
                       
                    try {
		                //if (c.Tasks <> null)
		                	for (Task t : c.Tasks) {
								if (t.OwnerID == c.OwnerID && !t.isClosed) txfrTasks.add(t); 
							}
                    } catch (exception ex) { }
                       
                    try {
						//if (c.Events <> null)
							for (Event e : c.Events) {
								if (e.OwnerID == c.OwnerID) txfrEvents.add(e);
							}
                    } catch (exception ex) { }
                       
	            }

		        for (Task c : txfrTasks)                { c.OwnerId = toUserId; /* System.Debug(LoggingLevel.Error, '++++ Task: ' + c.ID);*/ }
		        for (Event c : txfrEvents)				{ c.OwnerId = toUserId; /* System.Debug(LoggingLevel.Error, '++++ Event: ' + c.ID);*/ } 
		        for (Attachment c : txfrAttachments)    { c.OwnerId = toUserId; /* System.Debug(LoggingLevel.Error, '++++ Attachment: ' + c.ID);*/ }
		        for (Note c : txfrNotes)                { c.OwnerId = toUserId; /* System.Debug(LoggingLevel.Error, '++++ Note: ' + c.ID);*/ }

    	        boolean IsError = false;

	            // ---- TASKS -----
	            // Need to split this into blocks of 200 or less
	            if (!IsError && txfrTasks.size() > 0) {
	                whereAmI = 'Transfer Tasks';
	                List<Task> txfrTasks2 = New List<Task>();
	                integer n = 0;
	                integer recNo = 0;
	                for (Task c : txfrTasks) {
	                    txfrTasks2.add(c);
	                    n++;
	                    recNo++;
	                    if (n == 190 || recNo == txfrTasks.size()) {
	                        srs = database.update(txfrTasks2);
					        for (database.saveresult sr : srs) {
					            if (!sr.isSuccess()) {
					                ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.FATAL, sr.getId() + '/' + sr.getErrors()[0].getMessage() ));
					            } else {
					            	transferCount++;
					            }
					        }
	                        txfrTasks2.clear();
	                        n = 0;
	                    }
	                }
	            }
	            
	            // ---- EVENTS -----
	            // Need to split this into blocks of 200 or less
	            if (!IsError && txfrEvents.size() > 0) {
	                whereAmI = 'Transfer Events';
	                List<Event> txfrEvents2 = New List<Event>();
	                integer n = 0;
	                integer recNo = 0;
	                for (Event c : txfrEvents) {
	                    txfrEvents2.add(c);
	                    n++;
	                    recNo++;
	                    if (n == 190 || recNo == txfrEvents.size()) {
	                        srs = database.update(txfrEvents2);
					        for (database.saveresult sr : srs) {
					            if (!sr.isSuccess()) {
					                ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.FATAL, sr.getId() + '/' + sr.getErrors()[0].getMessage() ));
					            } else {
					            	transferCount++;
					            }
					        }
	                        txfrEvents2.clear();
	                        n = 0;
	                    }
	                }
	            }


	            // ---- NOTES -----
	            if (!IsError && txfrNotes.size() > 0) {
	                whereAmI = 'Transfer Notes';
	                // System.Debug(LoggingLevel.Error, '++++ ' + whereAmI + ': ' + txfrNotes.size() + ' records');
	                srs = database.update(txfrNotes);
			        for (database.saveresult sr : srs) {
			            if (!sr.isSuccess()) {
			                ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.FATAL, sr.getId() + '/' + sr.getErrors()[0].getMessage() ));
			            } else {
			            	transferCount++;
			            }
			        }
	            }

	            // ---- ATTACHMENTS -----
	            if (!IsError && txfrAttachments.size() > 0) {
	                whereAmI = 'Transfer Attachments';
	                // System.Debug(LoggingLevel.Error, '++++ ' + whereAmI + ': ' + txfrAttachments.size() + ' records');
	                srs = database.update(txfrAttachments);
			        for (database.saveresult sr : srs) {
			            if (!sr.isSuccess()) {
			                ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.FATAL, sr.getId() + '/' + sr.getErrors()[0].getMessage() ));
			            } else {
			            	transferCount++;
			            }
			        }
	            }

                // MGS, 06/22/2010: Are there are remaining items to transfer that went beyond
                //     our query limits
                List<String> batchContactIDs = new List<String>();
                for (Contact c : [SELECT ID, Name, OwnerID,
                (Select ID, OwnerID, Title From Notes limit 1),
                (Select ID, OwnerID, Name From Attachments limit 1),
                (Select ID, OwnerID, IsClosed From Tasks limit 1),
                (Select ID, OwnerID From Events limit 1)
                FROM Contact WHERE ID IN :IDs]) {
                    if (c.Notes <> null && c.Notes.size() > 0) batchContactIDs.add(c.id);
                    else if (c.Tasks <> null && c.Tasks.size() > 0) batchContactIDs.add(c.id);
                    else if (c.Attachments <> null && c.Attachments.size() > 0) batchContactIDs.add(c.id);
                    else if (c.Events <> null && c.Events.size() > 0) batchContactIDs.add(c.id);
                }
                if (batchContactIDs.size() > 0) {
                	// System.debug(LoggingLevel.Error, 
                	//    '++++ There are remaining Tasks/Notes/Attachments to transfer for: ' + batchContactIDs);
                	
                	// Schedule the batch job!
	                //id batchinstanceid = database.executeBatch(
	                //    new batch_transferContacts(toUserId, batchContactIDs), 200);
                }

	        }
	        else {
	        	// System.debug(LoggingLevel.Error, '++++ Not transferring Tasks/Notes/Attachments');
	        }
        } catch (exception e) {
            // Rollback the database
            ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.FATAL, 'Error Transferring ' + whereAmI + ':' + e.getMessage() ));
            database.rollback(sp);
            return null;
        }
        
        // EP 6/18/2010: moved the contact update to later so that we can compare original contact owner in Tasks/Notes transfer instead of 
        //				using unreliably populated fromUserId variable  
        // Query the contacts being transferred
        List<Contact> contacts = [SELECT ID, OwnerID, Name, Account.Name, Title, Owner.Alias FROM Contact WHERE ID IN :IDs];
        for (Contact c : contacts) {
            c.ownerID = toUserID;
        }
        if (DebugMode) ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.INFO, 'Query Size: ' + contacts.size()));

        // Process Errors and Count the Number of Records Transferred
        List<string> txfrdIDs = New List<string>(); // Remember which contacts were transferred
        try {
	        srs = database.update(contacts);
	        system.debug(LoggingLevel.Error, '*** srs=' + srs);
	        for (database.saveresult sr : srs) {
	            if (!sr.isSuccess()) {
	                ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.FATAL, sr.getId() + '/' + sr.getErrors()[0].getMessage() ));
	            } else {
	            	transferCount++;
	            	txfrdIDs.add(sr.getId());
	            }
	        }
        } catch (DMLexception e) {

            // 10/30/2009: Catch errors here and try to give a nicer message to the user
            // Log the Errors and Rollback the changes
            for (integer i = 0; i < e.getNumDml(); i++) {
                ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.FATAL,
                   e.GetDmlId(i) + ': ' + e.getDmlMessage(i) ));
                for (string f : e.getDmlFieldNames(i)){
                    system.debug(LoggingLevel.Error, '++++ Transfer Error: ' + e.GetDmlId(i) + '/' + f + ': ' + e.getDmlMessage(i));
                }
            }
            database.rollback(sp);
            return null;
        }

        // If there were any errors, then re-build the list of contacts transferred to use for sending the eMail
        if (transferCount <> contacts.size() && transferCount > 0) {
	        // Requery the contacts to figure out which were transferred and which were not.
	        List<Contact> contacts2 = [SELECT ID, OwnerID, Name, Account.Name, Title, Owner.Alias FROM Contact WHERE ID IN :IDs];
	        contacts = new List<Contact>();
	        for (Contact c : contacts2) {
	            if (c.OwnerID == toUserID) contacts.add(c);
	        }
        }

        // Display the Transfer Count
        ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.CONFIRM, transferCount + ' Records Successfully Transfered' ));

        // If the 'Send eMail to New Owner' option is checked:
        if (DebugMode) ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.INFO, 'optSendeMailToOwner=' + optSendeMailToOwner));
        if (optSendeMailToOwner && transferCount > 0) 	sendEMail(contacts);

        // Set the flag that this just finished
        transferJustCompleted = true;

        // Re-run the [Search] button functionality.
        doSearch();

        return null;
    }

    // ----------------------------------------------------------------------
    // If the 'Send eMail to New Owner' option is checked
    // Send a simple email with Text/Html body listing the contacts just transferred
    // Called by doTransfer() passing in the contacts[] list.
    // ----------------------------------------------------------------------
    private boolean sendEMail(List<Contact> TransferedContacts) {
    	string htmlBody = '<HTML><BODY><h3>';
    	string textBody = '';

    	htmlbody += 'The following Contacts were just transferred to you by ' + UserInfo.getName() + '</h3>';
    	textBody += 'The following Contacts were just transferred to you ' + UserInfo.getName() + ':\r\r';
 
        // Build table/list of Contacts Transferred
    	htmlBody += '<Table width="100%"><TR><TD width="25%"><B>Contact Name</B></TD><TD width="25%"><B>Account Name</B></TD>' +
    	   '<TD width="25%"><B>Title</B></TD><TD><B>Old Owner</B></TD></TR>';
        textBody += 'CONTACT NAME\t\t\tACCOUNT NAME\t\t\tTITLE\t\t\tOLD OWNER\r';

        // Use this to get the base URL of the SalesForce instance
        string BaseURL = ApexPages.currentPage().getHeaders().get('Host');

        // Build the table/list of contacts
        // Make the Name field a link to the contact
        for (Contact c : TransferedContacts) {
            pageReference cView = new ApexPages.StandardController(c).view();
            htmlBody += '<TR><TD><a href="' + BaseURL + cView.getUrl() + '">' + c.Name + '</a></TD><TD>'
                + null2String(c.Account.Name) + '</TD><TD>' + null2String(c.Title) + '</TD><TD>' + c.Owner.Alias + '</TD></TR>';
            textBody += c.Name + '\t\t\t' + null2String(c.Account.Name) + '\t\t\t' + null2String(c.Title) + '\t\t\t' + c.Owner.Alias + '\r';
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
		Messaging.SendEmailResult [] sr = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });

		if (!sr[0].isSuccess()) {
			// Error sending the message; display the error on the page
			Messaging.SendEmailError r = sr[0].getErrors()[0];
			ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'Error Sending Message: ' + sr[0].getErrors()[0].getMessage() ));
			return false;
		} else { return true; }

    }

    // Simple function to convert NULL to ''
    private string null2String(string s) { if (s == null) return ''; else return s; }

	/* -------------------------------------------------------------------------------------
	* TransferContactSearchResults: Mass Transfer Search Results Wrapper Class
	* - Used by the TransferContacts Class and Page
	* - Main purpose is to return a LIST of Contacts along with a custom checkbox that can
	*   be used to let the user select which rows to transfer and which to ignore.
	*  ------------------------------------------------------------------------------------- */
	public class transferContactSearchResults{
 
	    public boolean selected {get; set; }
        public string contactID;
	    public transient Contact contact  {get; private set;}

	    public transferContactSearchResults() { }
	    public transferContactSearchResults(Contact c) { 
	    	contact = c;
	    	contactID = c.id; 
	    	selected = true; 
    	}

	}
}