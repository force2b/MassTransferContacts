/**
* @author Michael Smith, Force2b, LLC
* @date 07/23/2016
*
* @group Unit Tests
*
* @description
*
* @modifications:
*/
@isTest
private class MassTransferContactsController_Test {

	@testSetup
	static void create_test_data() {
		Integer uid = 100;
		//try {
			Account a = new Account(Name = 'UNITTEST');
			insert(a);

			// Add 10 new contacts that we can search for and transfer
			List<Contact> contacts = new List<Contact>();
			for (Integer i = 0; i < 5; i++) {
				contacts.add(new Contact(
					LastName = 'UNITTEST ' + String.valueOf(uid++),
					FirstName = 'UNITTEST',
					Email = 'UNITTEST-' + String.valueOf(uid++) + '@UNITTEST.NET',
					AccountId = a.Id
				));
			}
			insert contacts;

			List<Task> testTasks = New List<Task>();
			List<Event> testEvents = New List<Event>();
			List<Note> testNotes = New List<Note>();
			List<Attachment> testAttachments = New List<Attachment>();
			for (Contact c : contacts) {
				testTasks.add(new Task(
					Subject = 'UNITTEST-' + uid,
					Status = 'Pending',
					WhoId = c.Id)
				);
				testEvents.add(new Event(
					Subject = 'UNITTEST-' + uid,
					WhoId = c.Id,
					DurationInMinutes = 10,
					ActivityDateTime = Datetime.now())
				);
				testNotes.add(new Note(
					Title = 'UNITTEST-' + uid,
					ParentId = c.Id)
				);
				testAttachments.add(new Attachment(
					Body = Blob.valueOf('UNITTEST-' + uid),
					Name = 'TEST Attachment',
					ParentId = c.Id)
				);
			}
			insert(testTasks);
			insert(testEvents);
			insert(testNotes);
			insert(testAttachments);
		//} catch (Exception ex) {}
	}

	@isTest
	static void test_transferController() {
		//try {

			// Get the current user and some other user
			User currentUser = [Select ID, FirstName, Lastname, Alias From User WHERE IsActive = True
				AND Id = :UserInfo.getUserID()  AND UserType = 'Standard' LIMIT 1];
			User anotherUser = [Select ID, FirstName, Lastname, Alias From User WHERE IsActive = True
					AND Id != :currentUser.Id LIMIT 1];

			Test.StartTest();

			// Test the static remoteVF methods
			MassTransferContactsController.searchUsers('XZY', '_active_');
			System.assertNotEquals(0, MassTransferContactsController.searchUsers(currentUser.LastName, null).size(),
				'There should be at least one User returned');

			// Create a PageReference to the VF page being tested
			PageReference pg = Page.MassTransferContacts;
			pg.getParameters().put('debug','1');
			Test.setCurrentPage(pg);

			// Create an instance of the searchCriteria to test all
			// get/set methods and the BuildWhereClause() method
			SearchCriteria critClass = new SearchCriteria();

			// Test all possible combinations of Fields and Operators
			List<SelectOption> operators = critClass.getOperatorSelectList();
			Set <String> fields = new Set<String>{'STRING/Field1', 'DATE/Field2', 'DATETIME/Field3',
				'PICKLIST/Field4', 'MULTIPICKLIST/Field5', 'EMAIL/Field6', 'PHONE/Field7',
				'DOUBLE/Field8', 'CURRENCY/Field9', 'BOOLEAN/Field10', 'TEXTAREA/Field11'};
			Set <String> values = new Set<String>{'abcde', 'abcd, efgh, ijkl', 'true', '100',
				'12/31/2007', '12-21-2008', 'TODAY', 'NEXT 3 WEEKS'};

			// Three nested loops - Fields, Operators, Values
			// nothing to check for, just want to run the code
			// Can look through the Test results for Debug entries if neded
			for (String f : fields) {
				critClass.searchField = f;
				for (SelectOption o : operators) {
					critClass.searchOperator = o.getValue();
					for (String v : values) {
						critClass.searchValue = v;
						System.debug(f + ' ' + o.getValue() + ' ' + v + ' :' +
							critClass.buildWhereClause(true) + ' - ' + critClass.errMsg);
					}
				}
			}

			// Create an instance of the page controller to test its methods
			MassTransferContactsController ctrlr = new MassTransferContactsController();

			// Call the various Get/Set methods to test these
			// nothing to check for, just want to run the code
			ctrlr.getInputDateFormat();

			ctrlr.gethasCommunityUsers();
			ctrlr.getUserFieldsPicklist();
			ctrlr.getContactFieldsPicklist();
			ctrlr.getAccountFieldsPicklist();

			ctrlr.searchForContacts();
			System.assertEquals(null, ctrlr.searchResults,
				'This should have failed because there was no To user');

			ctrlr.toUserId = anotherUser.Id;

			// Create a search criteria that must succeed
			// Get the error message values for each to confirm no errors on any criteria line
			List<SearchCriteria> critLines = ctrlr.getSearchCriteria();
			critLines[0].searchField = 'STRING/FirstName';
			critLines[0].searchOperator = 'eq';
			critLines[0].searchValue = 'UNITTEST';
			System.Debug(critLines[0].buildWhereClause(true));
			System.assert(String.isEmpty(critLines[0].errMsg));

			critLines[1].searchField = 'DATETIME/CreatedDate';
			critLines[1].searchOperator = 'eq';
			critLines[1].searchValue = 'TODAY';
			System.Debug(critLines[1].buildWhereClause(true));
			System.assert(String.isEmpty(critLines[1].errMsg));

			critLines[2].searchField = 'STRING/LastName';
			critLines[2].searchOperator = 'starts';
			critLines[2].searchValue = 'UNIT';
			System.Debug(critLines[2].buildWhereClause(true));
			System.assert(String.isEmpty(critLines[2].errMsg));

			critLines[3].searchField = '_active_';
			critLines[3].searchOperator = 'eq';
			critLines[3].searchValue = currentUser.Id;
			System.Debug(critLines[3].buildWhereClause(true));
			System.assert(String.isEmpty(critLines[3].errMsg));

			// Run the Search against this criteria
			ctrlr.searchForContacts();

			// Confirm that the results match the number of contacts added above
			if (UserInfo.getUserID() != anotherUser.ID) {
				// this is possible if there only one active user in system
				System.assertEquals(5, ctrlr.searchResults.size());
			}

			// Enum the searchResult to test some of the code in this class
			// Nothing to test for here
			for (MassTransferContactsController.TransferContactSearchResult sr : ctrlr.searchResults) {
				sr.selected = true;
			}

			// Test the send mail functionality.
			ctrlr.optSendeMailToOwner = true;
			ctrlr.optTxfrTasksNotesOwned = true;

			// Click the transfer button
			ctrlr.doTransfer();

			// Confirm that all 5 contacts were transferred with no errors
			if (UserInfo.getUserID() != anotheruser.ID) {
				System.assertEquals(ctrlr.searchResults.size(), 0);
			}

			System.assertEquals(5, [SELECT count() FROM Contact
				WHERE FirstName = 'UNITTEST' AND OwnerId = :anotherUser.Id],
				'Contacts were not transferred');

			// Should fail
			//ctrlr.fromUserID = null;
			//ctrlr.proxyAcctLookupTO.OwnerId = null;
			ctrlr.searchForContacts();
			ctrlr.doTransfer();

			Test.stopTest();
		/*} catch (Exception ex) {

		}*/
	}

}
