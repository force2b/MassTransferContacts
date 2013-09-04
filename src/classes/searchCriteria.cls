/* -------------------------------------------------------------------------------------
* searchCriteria Class
* M.Smith 1 April 2009
* http://www.force2b.net
*
* Mass Transfer Search Criteria Wrapper Class
* - Used by the TransferContacts Class and Page 
* - Main purpose is to display multiple criteria rows on the search page
*   while allowing the main class to retrieve the values for each line
* - This class is essentially generic and should be able to be re-used for any page that
*   requires a criteria block, regardless of the object.
*
* Modifications:
* - M.Smith, 05/25/2011: Don't include TEXTAREA and Encrypted fields as a criteria field
*  ------------------------------------------------------------------------------------- */
public with sharing class searchCriteria{

    public string SearchField = '';
    public string SearchOperator = '';
    public string SearchValue = '';
    public string Logical = '';
    public string errMsg = '';

    // Default date format to MM/DD/YYYY, but modify this based on the users
    // Locale settings. The stringToDate() method uses this to determine how 
    // to parse dates entered as criteria. 
    private string InputDateFormat = 'MM/DD/YYYY' ;
    private string InputDateSep = '/';
    
    private boolean debugMode = false; 

// ----------------------------------------------------------------------------------------

    // Constructor class
    public searchCriteria() {
        string x = getInputDateFormat();
    }

    public string getSearchField()      { return this.SearchField; }
    public string getSearchOperator()   { return this.SearchOperator ; }
    public string getSearchValue()      { return this.SearchValue ; }
    public string getLogical()          { return this.Logical ; }
    public string geterrMsg()           { return this.errMsg; }
    public void setLogical(string val)          { this.Logical = val; }
    public void setSearchField(string val)      { this.SearchField = val; }
    public void setSearchOperator(string val)   { this.SearchOperator = val; }
    public void setSearchValue(string val)      { this.SearchValue =val; }
    public void seterrMsg(string val)           { this.errMsg = val; }

    // Figure out the date format based on the current users Locale settings
    // This is used in the stringToDate() method and to display the format type on the search page
    public string getInputDateFormat() {
        string dtTest = date.newInstance(2009, 12, 31).format();
        InputDateSep = dtTest.subString(2,3); 
        if (dtTest.subString(0,2) == '12') InputDateFormat = 'MM' + InputDateSep + 'DD' + InputDateSep + 'YYYY';
        if (dtTest.subString(0,2) == '31') InputDateFormat = 'DD' + InputDateSep + 'MM' + InputDateSep + 'YYYY';
        if (dtTest.subString(0,2) == '20') InputDateFormat = 'YYYY' + InputDateSep + 'MM' + InputDateSep + 'DD';
        return InputDateFormat;     
    }
    
    // Return a SelectOption list of operators that can be used on the page
    public List<SelectOption> getOperatorSelectList() {
        List<SelectOption> options = new List<SelectOption>();
        options.add(new selectOption('eq', 'Equals'));
        options.add(new selectOption('ne', 'Not Equal'));
        options.add(new selectOption('gt', 'Greater Than'));
        options.add(new selectOption('ge', 'Greater or Equal To'));
        options.add(new selectOption('lt', 'Less Than'));
        options.add(new selectOption('le', 'Less or Equal To'));
        options.add(new selectOption('starts', 'Starts With'));
        options.add(new selectOption('contains', 'Contains'));
        options.add(new selectOption('notcontain', 'Does Not Contain'));
        options.add(new selectOption('in', 'Includes'));
        options.add(new selectOption('notin', 'Excludes'));
        return options;
    }
    
    // --------------------------------------------------------------------------------
    // GetFieldsForObject(Map<> of Object Fields, LabelPrefix, FieldNamePrefix)
    //  - Returns a selectList[] of field names for whatever the passed MAP[] object is           
    // --------------------------------------------------------------------------------
    public List<SelectOption> GetFieldsForObject(Map<String, Schema.SObjectField> objFields, string lblPrefix, string fldPrefix) {

        // Build a list of field names to use to iterate the Map of field object pointers
        Set <string> flds = new Set <String>();
        flds = objFields.keySet();

        // Add the keyset of field names to a list so that it can be sorted
        List<String> fldList = new List<String>();
        for (string f : flds) {
            fldList.add(f);
        }
        fldList.sort();
            
        List<SelectOption> options = new List<SelectOption>();
        for (string f : fldList) {
            string fldName = objFields.get(f).getDescribe().getName();
            string fldLabel = objFields.get(f).getDescribe().getLabel();
            string fldType = ('' + objFields.get(f).getDescribe().getType()).replace('Schema.DisplayType.', '') ;
            // M.Smith, 05/25/2011: Ignore TEXTAREA and Encrypted fields as criteria fields
            if (fldType <> 'REFERENCE' && fldType <> 'TEXTAREA' && fldType <> 'ENCRYPTEDSTRING'
            && fldType <> 'ID' && fldName <> 'IsDeleted' && fldName <> 'SystemModstamp') 
                options.add(new selectOption(fldType + '/' + fldPrefix + fldName, lblPrefix + fldLabel ));
            if (fldName == 'OwnerID') {
                options.add(new selectOption('STRING/' + fldPrefix + 'Owner.Name', lblPrefix + 'Owner.Name'));
                options.add(new selectOption('STRING/' + fldPrefix + 'Owner.Alias', lblPrefix + 'Owner.Alias'));
                options.add(new selectOption('STRING/' + fldPrefix + 'Owner.Department', lblPrefix + 'Owner.Department'));
                options.add(new selectOption('STRING/' + fldPrefix + 'Owner.Division', lblPrefix + 'Owner.Division'));
            } else if (fldName == 'LastModifiedByID') {
                options.add(new selectOption('STRING/' + fldPrefix + 'LastModifiedBy.Name', lblPrefix + 'LastModifiedBy.Name'));
                options.add(new selectOption('STRING/' + fldPrefix + 'LastModifiedBy.Alias', lblPrefix + 'LastModifiedBy.Alias'));
            } else if (fldName == 'CreatedByID') {
                options.add(new selectOption('STRING/' + fldPrefix + 'CreatedBy.Name', lblPrefix + 'CreatedBy.Name'));
                options.add(new selectOption('STRING/' + fldPrefix + 'CreatedBy.Alias', lblPrefix + 'CreatedBy.Alias'));
            }
        }
        
        return options;     
    }
    
    
    // --------------------------------------------------------------------------------
    // For the current criteria line, create the WHERE clause component
    //      ex:   field = 'xyz'     
    // Called from main massTransfer class for each criteria line item
    // --------------------------------------------------------------------------------
    public string buildWhereClause(boolean showDebugMessages) 
    {
        string cWhereClause = '';
        this.debugMode = showDebugMessages;
        
        this.errMsg = '';
        if (this.SearchField == null || this.SearchField == '') {
            return '';
        }            

        // Get the field type, field name, and query friendly search value
        string fldType = this.SearchField.substring(0, this.SearchField.indexOf('/')) ;
        string fldName = this.SearchField.substring(this.SearchField.indexOf('/')+1) ;
        string fldValue = String.escapeSingleQuotes(this.SearchValue) ; // replace('\'', '\\\'').trim();
                
        if (showDebugMessages) ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.INFO, fldType + '/' + fldName + ' ' + this.SearchOperator + ' ' + fldValue )) ;
                
        // Start building the additional WHERE Clause
        cWhereClause = ' AND ' + fldName ;

        // itemValue="eq" itemLabel="Equals"
        // itemValue="ne" itemLabel="Not Equal"
        // itemValue="gt" itemLabel="Greater Than"
        // itemValue="ge" itemLabel="Greater or Equal To"
        // itemValue="lt" itemLabel="Less Than"
        // itemValue="le" itemLabel="Less or Equal To"
        // itemValue="starts" itemLabel="Starts With"
        // itemValue="contains" itemLabel="Contains"
        // itemValue="notcontain" itemLabel="Does Not Contain"
        // itemValue="in" itemLabel="Includes"
        // itemValue="notin" itemLabel="Excludes"
                
        // ERROR CHECKING LOGIC
        if (fldType == 'BOOLEAN' && !(fldValue.toUpperCase() == 'TRUE' || fldValue.toUpperCase() == 'FALSE')) {
            this.errMsg = 'Value can only be TRUE or FALSE';
        }  
        if ((fldType == 'DATE' || fldType == 'DATETIME' || fldType == 'CURRENCY' 
        || fldType == 'DOUBLE' || fldType == 'PHONE' || fldType == 'BOOLEAN'
        || fldType == 'INTEGER' || fldType == 'PERCENT') 
        && (this.SearchOperator == 'starts' || this.SearchOperator == 'contains' || this.SearchOperator == 'notcontain' || this.SearchOperator == 'in' || this.SearchOperator == 'notin')) {
            this.errMsg = 'Invalid Operator for this Field Type';
        }  

        // If this is a string/picklist type AND there is a comma in the search value
        // then assume that we'll use IN or NOT IN
        string cCloseCharacter = '';
        string cOperator = '';
        if (fldType == 'STRING' || fldType == 'EMAIL' || fldType == 'PICKLIST' || fldType == 'MULTIPICKLIST' || fldType == 'TEXTAEA') {
            if (!fldValue.contains(',')) {
                // No comma, so just use =, <>
                if (this.SearchOperator == 'eq') cOperator = '=';
                if (this.SearchOperator == 'ne') cOperator = '<>';
            } else {
                // comma present and
                if (this.SearchOperator == 'eq' || this.SearchOperator == 'in') cOperator = ' IN (';
                if (this.SearchOperator == 'ne' || this.SearchOperator == 'notin') cOperator = ' NOT IN (';
                cCloseCharacter = ')';
            }
        } else {
            if (this.SearchOperator == 'eq') cOperator = '=';
            if (this.SearchOperator == 'ne') cOperator = '<>';
        }
        
        if (this.SearchOperator == 'gt') cOperator = '>';
        if (this.SearchOperator == 'lt') cOperator = '<';
        if (this.SearchOperator == 'ge') cOperator = '>=';
        if (this.SearchOperator == 'le') cOperator = '<=';
        
        if (fldType == 'STRING' || fldType == 'EMAIL' || fldType == 'PICKLIST' || fldType == 'MULTIPICKLIST' || fldType == 'TEXTAEA') {
            if (this.SearchOperator == 'starts') { cOperator = ' LIKE \''; cCloseCharacter = '%\''; }
            if (this.SearchOperator == 'contains') { cOperator = ' LIKE \'%'; cCloseCharacter = '%\''; }
            if (this.SearchOperator == 'notcontain') {
                // NOT LIKE requires parenthesis around the whole condition, including the fieldname 
                cWhereClause = ' AND (NOT(' + fldName ; 
                cOperator = ' LIKE \'%'; 
                cCloseCharacter = '%\'))'; 
            }
            if (this.SearchOperator == 'in' && fldType == 'MULTIPICKLIST') { cOperator = ' INCLUDES ('; cCloseCharacter = ')'; }
            if (this.SearchOperator == 'notin' && fldType == 'MULTIPICKLIST') { cOperator = ' EXCLUDES ('; cCloseCharacter = ')'; }
            if (this.SearchOperator == 'in' && fldType <> 'MULTIPICKLIST') { cOperator = ' IN ('; cCloseCharacter = ')'; }
            if (this.SearchOperator == 'notin' && fldType <> 'MULTIPICKLIST') { cOperator = ' NOT IN ('; cCloseCharacter = ')'; }
        }
        cWhereClause += cOperator;
        
        if (cOperator == '') {
            // ERROR
            // ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.INFO, fldName + ': Invalid Operator for this field' )) ;
            this.errMsg = 'Invalid Operator for this field';
        }
                
        if (fldType == 'STRING' || fldType == 'EMAIL' || fldType == 'PICKLIST' || fldType == 'MULTIPICKLIST' || fldType == 'TEXTAEA') {
        
            if (cCloseCharacter.startsWith('%')) {
                // Using LIKE ('Starts With' or 'Contains')
                cWhereClause += fldValue ;
            } else if (!fldValue.contains(',')) {
                // Standard single = value
                cWhereClause += '\'' + fldValue + '\'';
            } else {
                // Multiple Values (IN or NOT IN)
                string[] multValues = fldValue.split(',');
                for (string v : multValues) {
                    cWhereClause += '\'' + v.trim() + '\',';
                }
                cWhereClause = cWhereClause.subString(0, cWhereClause.length()-1);
            }

        } else if (fldType == 'DATE' || fldType == 'DATETIME') {
            
            // For the various Date/Time constants (ex: LAST 60 DAYS) need an Underscore instead of space
            if (fldValue.toUpperCase().startsWith('NEXT') || fldValue.toUpperCase().startsWith('LAST')) {
                // If this is NEXT xxx DAYS/MONTHS/YEARS etc., then need to reorder the criteria to
                // NEXT_N_DAYS:yyy
                string fldVal2 = fldValue.subString(5).trim().toUpperCase();
                if (fldVal2.contains(' ')) {
                    List<string> fldSplit = fldVal2.split(' ');
                    string fldNum = fldSplit[0].trim();
                    // If the 2nd word is one of these then no numbers, just a straight value
                    if (!(fldNum == 'WEEK' || fldNum == 'MONTH' || fldNum == 'QUARTER' || fldNum == 'YEAR' || fldNum == 'FISCAL')) {
                        string fldPeriod = '';
                        for (integer y = 1; y < fldSplit.size(); y++) {
                            fldPeriod += fldSplit[y].trim() + ' ';
                        }
                        fldPeriod = fldPeriod.trim();
                        fldValue = fldValue.subString(0,4).trim().toUpperCase() + '_N_' + fldPeriod + ':' + fldNum;
                        // this.errMsg = 'fldNum:' + fldNum + ', fldPeriod:' + fldPeriod;
                    }
                } 
            } else if (fldValue.toUpperCase().startsWith('TODAY') || fldValue.toUpperCase().startsWith('YESTERDAY')
                || fldValue.toUpperCase().startsWith('TOMORROW') || fldValue.toUpperCase().startsWith('THIS')) {
                // No issues here
            } else {
                try {
                    date testDate = stringToDate(fldValue);
                    // Rebuild the date string as YYYY-MM-DD
                    string m = testDate.month().format();
                    string d = testDate.day().format();
                    if (integer.valueOf(m) < 10) m = '0' + m;
                    if (integer.valueOf(d) < 10) d = '0' + d;
                    fldValue = testDate.year() + '-' + m + '-' + d;
                    
                    // For DATETIME types, must add the hours AND we need to make it a compound condition
                    //     (field >= START AND field <= END)
                    // Example: field = 12/31/2008 will be translated to
                    //      field >= 2008-12-31T00:00:00Z AND field <= 2008-12-31T23:59:59Z 
                    if (fldType == 'DATETIME') {
                        // This creates a DateTime at midnight in the users current timezone 
                        datetime testDateTm = datetime.newInstance(testDate.year(), testDate.month(),testDate.day());
                        
                        // If the operator is equals/not equals then need a range for the entire day
                        // if the operator is greater or less, then we can just use the datetime
                        // but we'll need to adjust based on midnight or 23:59:59pm
                        if (cOperator == '=') {
                            cWhereClause = ' AND (' + fldName + ' >= ';                         
                            fldValue = testDateTm.format('yyyy-MM-dd') + 'T00:00:00Z';                          
                            cWhereClause += fldValue + ' AND ' + fldName + ' <= ' ;
                            fldValue = testDateTm.format('yyyy-MM-dd') + 'T23:59:59Z';
                            cCloseCharacter = ')';                          
                        } else if (cOperator == '<>') {
                            cWhereClause = ' AND (' + fldName + ' < ';                          
                            fldValue = testDateTm.format('yyyy-MM-dd') + 'T00:00:00Z';                          
                            cWhereClause += fldValue + ' OR ' + fldName + ' > ' ;
                            fldValue = testDateTm.format('yyyy-MM-dd') + 'T23:59:59Z';                          
                            cCloseCharacter = ')';                          
                        } else if (cOperator == '<') {
                            fldValue = testDateTm.format('yyyy-MM-dd') + 'T00:00:00Z';                          
                        } else if (cOperator == '<=') {
                            fldValue = testDateTm.format('yyyy-MM-dd') + 'T23:59:59Z';
                        } else if (cOperator == '>') {
                            fldValue = testDateTm.format('yyyy-MM-dd') + 'T23:59:59Z';
                        } else if (cOperator == '>=') {
                            fldValue = testDateTm.format('yyyy-MM-dd') + 'T00:00:00Z';                          
                        }
                    }
                } catch (exception ex) {
                    this.errMsg = 'Invalid Date Format (' + InputDateFormat + '): ' + ex.getMessage();
                }
            }    
            cWhereClause += fldValue.replace(' ', '_').toUpperCase();
        } else if (fldType == 'CURRENCY' || fldType == 'DOUBLE' || fldType == 'BOOLEAN'
        || fldType == 'INTEGER' || fldType == 'PERCENT') {
            cWhereClause += fldValue ;
        } else { 
            cWhereClause += '\'' + fldValue + '\''; 
        }
        cWhereClause += cCloseCharacter ;
        
        if (this.errMsg == '') { return cWhereClause; } else { return ''; }
        
    }
    
    // Convert a Date String to a Date type using the IntputDateFormat value
    // to determine how the date format is constructed
    private Date stringToDate(String s){
        
        // Due to regular expressions, split('.') does not work so replace all separators with a /
        // to force the process to work.
        s = s.replace('.', '/').replace('-', '/').replace('\\', '/');
        String[] stringDate = s.split('/');
        Integer m = 0;
        Integer d = 0;
        Integer y = 0;
        
        if (debugMode) {
            ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.INFO, 's=' + s )) ;
            ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.INFO, 'InputDateSep=' + InputDateSep )) ;
            ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.INFO, 'InputDateFormat=' + InputDateFormat )) ;
            ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.INFO, 'stringDate=' + stringDate.size() )) ;
        }
         
        if (InputDateFormat.subString(0,2) == 'MM') { 
            m = Integer.valueOf(stringDate[0]);
            d = Integer.valueOf(stringDate[1]);
            y = Integer.valueOf(stringDate[2]);
        }
        if (InputDateFormat.subString(0,2) == 'DD') { 
            d = Integer.valueOf(stringDate[0]);
            m = Integer.valueOf(stringDate[1]);
            y = Integer.valueOf(stringDate[2]);
        }
        if (InputDateFormat.subString(0,2) == 'YY') { 
            y = Integer.valueOf(stringDate[0]);
            m = Integer.valueOf(stringDate[1]);
            d = Integer.valueOf(stringDate[2]);
        }
        
        if (y < 100 && y > 80) y += 1900;
        if (y < 100) y += 2000;
        return date.newInstance(y,m,d); 
    }
}