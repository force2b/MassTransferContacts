@isTest
/* -------------------------------------------------------------------------------------
* TransferContacts_Test Class: Test the Classes used by the Mass Contact Transfer page
* M.Smith 8 April 2009
* http://www.force2b.net
*
* Modifications:
* - M.Smith, 01/25/2010: Using the new lookup fields for FROm/TO userids
* - M.Smith, 03/30/2010: Minor changes to allow this to run successfully even if only one user
* - E.Peterson, 06/18/2010: Reduced unit test dataset from 10 contacts to 5 
* - M.Smith, 05/11/2011: Changes to support modifications to main class & page. Bring up coverage %
*
* ------------------------------------------------------------------------------------- */
private class transferContacts_Test {

    static testMethod void myUnitTest() {

        try {
	        // Add 10 new contacts that we can search for and transfer
	        string UniqueKey = 'AbcDefGhi12345';
	        list<Contact> c = New List<Contact>();
	        List<Task> testTasks = New List<Task>();
	        List<Event> testEvents = New List<Event>();
	        List<Note> testNotes = New List<Note>();
	        List<Attachment> testAttachments = New List<Attachment>();
	        for (Integer i = 0; i < 5; i++) {
	            Contact cnew = new Contact(LastName = 'Test Contact ' + i, FirstName = UniqueKey);
	            insert cnew;
	            c.add(cnew);
	
		        // Create tasks and Notes on the Contact
		        for (integer n = 0; n < 5; n++) {
		            testTasks.add(New Task(Subject = 'TEST Task' + n, Status = 'Pending', WhoID = cnew.ID));
		            testEvents.add(New Event(Subject = 'TEST Event' + n, WhoID = cnew.ID, DurationInMinutes = 10, ActivityDateTime = Datetime.now()));
		            testNotes.add(New Note(Title = 'TEST Note' + n, ParentID = cnew.ID));
		            testAttachments.add(New Attachment(Body = Blob.valueOf('TEST Attachment ' + n), Name = 'TEST Attachment', ParentId = cnew.ID));
		        }
	        }
	        insert(testTasks);
	        insert(testEvents);
	        insert(testNotes);
	        insert(testAttachments);
	
	        // Get the current user and some other user
	        user anotheruser = null;
	        user currentuser = [Select ID, Alias From User WHERE IsActive = True
	            AND Id = :UserInfo.getUserID()  AND UserType = 'Standard' LIMIT 1];
	
	        // NOTE: There must be at least one other active user in the system!
	        // M.Smith, 01/25/2010: Only retrieve Standard users
	        // M.Smith, 03/30/2010: Might not be any other active users, so
	        try {
		        anotheruser = [Select ID, Alias From User WHERE IsActive = True
		            AND Id <> :UserInfo.getUserID() LIMIT 1];
	        } catch (exception ex) {
	        	anotheruser = [Select ID, Alias From User WHERE IsActive = True
	                AND Id = :UserInfo.getUserID()  AND UserType = 'Standard' LIMIT 1];
	        }
	
	        test.startTest();
	
	        system.assertEquals(5, [SELECT count() FROM Contact 
	        WHERE FirstName = :UniqueKey AND OwnerID = :currentuser.ID]);
	
	        // Create a PageReference to the VF page being tested
	        PageReference pg = Page.transferContacts;
	        pg.getParameters().put('debug','1');
	        test.setCurrentPage(pg);
	
	        // Create an instance of the searchCriteria to test all
	        // get/set methods and the BuildWhereClause() method
	        searchCriteria  critClass = new searchCriteria();
	
	        // Call the various Get/Set methods to test these
	        // nothing to check for, just want to run the code
	        system.debug(critClass.getInputDateFormat());
	        critClass.getSearchField();
	        critClass.getSearchOperator();
	        critClass.getSearchValue();
	        critClass.getLogical();
	        critClass.getSearchValue();
	        critClass.seterrMsg('');
	        critClass.setLogical('AND');
	
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
	        for (string f : fields) {
	            critClass.setSearchField(f);
	            for (SelectOption o : operators) {
	                critClass.setSearchOperator (o.getValue());
	                for (string v : values) {
	                    critClass.setSearchValue (v);
	                    System.debug(f + ' ' + o.getValue() + ' ' + v + ' :' + critClass.buildWhereClause(true) + ' - ' + critClass.geterrMsg());
	                }
	            }
	        }
	
	        // Create an instance of the page controller to test its methods
	        transferContacts cntrlr = new transferContacts();
	
	        // Call the various Get/Set methods to test these
	        // nothing to check for, just want to run the code
	        cntrlr.getInputDateFormat();
	        // M.Smith, 01/25/2010: Using the new lookup fields for FROm/TO userids
	        cntrlr.gettoUserLookup();
	        cntrlr.getfromUserLookup();
	        cntrlr.optShowUserType = 'Portal';
	        cntrlr.getFromUsersOther();
	        cntrlr.optShowUserType = 'Inactive';
	        cntrlr.getFromUsersOther();
	        cntrlr.optShowUserType = 'Standard';
	        cntrlr.updateFromUserList();
	        cntrlr.proxyAcctLookupTO.OwnerId = anotheruser.ID;
	        cntrlr.proxyAcctLookupFROM.OwnerId = UserInfo.getUserID();
	        cntrlr.getsearchFields();
	        cntrlr.getsearchCriteria();
	        cntrlr.getSearchResults();
	        // cntrlr.getShowBlockIfResults();
	
	        // Create a search criteria that must succeed
	        // Get the error message values for each to confirm no errors on any criteria line
	        cntrlr.criteriaLine[0].setSearchField('STRING/FirstName');
	        cntrlr.criteriaLine[0].setSearchOperator('eq');
	        cntrlr.criteriaLine[0].setSearchValue(UniqueKey);
	        System.Debug(cntrlr.criteriaLine[0].buildWhereClause(true));
	        System.assertEquals('', cntrlr.criteriaLine[0].geterrMsg());
	
	        cntrlr.criteriaLine[1].setSearchField('DATETIME/CreatedDate');
	        cntrlr.criteriaLine[1].setSearchOperator ('eq');
	        cntrlr.criteriaLine[1].setSearchValue ('TODAY');
	        System.Debug(cntrlr.criteriaLine[1].buildWhereClause(true));
	        System.assertEquals('', cntrlr.criteriaLine[1].geterrMsg());
	
	        cntrlr.criteriaLine[2].setSearchField('STRING/LastName');
	        cntrlr.criteriaLine[2].setSearchOperator ('starts');
	        cntrlr.criteriaLine[2].setSearchValue ('Test Contact');
	        System.Debug(cntrlr.criteriaLine[2].buildWhereClause(true));
	        System.assertEquals('', cntrlr.criteriaLine[2].geterrMsg());
	
	        cntrlr.criteriaLine[3].setSearchField('STRING/Owner.Alias');
	        cntrlr.criteriaLine[3].setSearchOperator ('eq');
	        cntrlr.criteriaLine[3].setSearchValue (currentuser.Alias);
	        System.Debug(cntrlr.criteriaLine[3].buildWhereClause(true));
	        System.assertEquals('', cntrlr.criteriaLine[3].geterrMsg());
	
	        // Run the Search against this criteria
	        PageReference cntrlrResult = cntrlr.doSearch();
	
	        // Confirm that the results match the number of contacts added above
	        System.assertEquals(null, cntrlrResult);
	        if (UserInfo.getUserID() != anotheruser.ID) // this is possible if there only one active user in system
	            System.assertEquals(c.size(), cntrlr.searchResults.size());
	
	        // Enum the searchResult to test some of the code in this class
	        // Nothing to test for here
	        for (transferContacts.TransferContactSearchResults sr : cntrlr.searchResults) {
	            sr.selected = true;
	        }
	
	        // Test the send mail functionality.
	        cntrlr.optSendeMailToOwner = true;
	        cntrlr.optTxfrTasksNotesOwned = true;
	
	        // Click the transfer button
	        cntrlrResult = cntrlr.doTransfer();
	
	        // Confirm that all 5 contacts were transferred with no errors
	        if (UserInfo.getUserID() != anotheruser.ID) {
	            System.assertEquals(cntrlrResult, null);
	            System.assertEquals(cntrlr.searchResults.size(), 0);
	        }
	        
	        system.assertEquals(5, [SELECT count() FROM Contact 
	        WHERE FirstName = :UniqueKey AND OwnerID = :anotheruser.ID]);
	
	        // Should fail
	        cntrlr.fromUserID = null;
	        cntrlr.proxyAcctLookupTO.OwnerId = null;
	        cntrlr.doSearch();
	        cntrlr.doTransfer();
	
	        Test.stopTest();
        } catch (exception ex) {
        	
        }
    }
}