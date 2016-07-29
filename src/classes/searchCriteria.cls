/**
* @author Michael Smith, Force2b, LLC
* @date 04/01/2009
*
* @group Utility Class
*
* @description Mass Transfer Search Criteria Wrapper Class
* - Used by the TransferContacts Class and Page
* - Main purpose is to display multiple criteria rows on the search page
*   while allowing the main class to retrieve the values for each line
* - This class is essentially generic and should be able to be re-used for any page that
*   requires a criteria block, regardless of the object.
*
* @unit-test: MassTransferContactsController_Test
*
* @modifications:
* - M.Smith, 05/25/2011: Don't include TEXTAREA and Encrypted fields as a
*		criteria field
* - M.Smith, 10/15/2015: Fix an error with 'Collection Size Exceeds 1000'.
*		Technically there is no limit on Lists in Apex, but Visualforce still
*		enforces a 1000 item list on <apex:selectList>. To help with this, when Person
*		Accounts are enabled ignore all PersonAccount related fields (API name ends
*		with __pc) when there are more than 300 custom fields in the object
* - M.Smith, 07/20/2016: Minor updates to support the new SLDS design
*
*/
public class SearchCriteria{

	public String searchField 	{ get; set; }
	public String searchOperator{ get; set; }
	public String searchValue 	{ get; set; }
	public String logical 			{ get; set; }
	public String errMsg 				{ get; set; }
	public Integer rowNum 			{ get; private set; }

	public static Integer rowNumStatic = 0;

	// Default date format to MM/DD/YYYY, but modify this based on the users
	// Locale settings. The stringToDate() method uses this to determine how
	// to parse dates entered as criteria.
	private String inputDateFormat = 'MM/DD/YYYY' ;
	private String inputDateSep = '/';

	private Boolean  debugMode = false;

// ----------------------------------------------------------------------------------------

	// Constructor class
	public SearchCriteria() {
		getInputDateFormat();
		rowNum = rowNumStatic++;
	}

	// Figure out the date format based on the current users Locale settings
	// This is used in the stringToDate() method and to display the format type on the search page
	public String getInputDateFormat() {
		String dtTest = date.newInstance(2009, 12, 31).format();
		inputDateSep = dtTest.subString(2,3);
		if (dtTest.subString(0,2) == '12') {
			inputDateFormat = 'MM' + inputDateSep + 'DD' + inputDateSep + 'YYYY';
		}
		if (dtTest.subString(0,2) == '31') {
			inputDateFormat = 'DD' + inputDateSep + 'MM' + inputDateSep + 'YYYY';
		}
		if (dtTest.subString(0,2) == '20') {
			inputDateFormat = 'YYYY' + inputDateSep + 'MM' + inputDateSep + 'DD';
		}
		return inputDateFormat;
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
	// GetFieldsForObject(Map!= of Object Fields, LabelPrefix, FieldNamePrefix)
	//  - Returns a selectList[] of field names for whatever the passed MAP[] object is
	// --------------------------------------------------------------------------------
	public List<SelectOption> getFieldsForObject(Map<String, Schema.SObjectField> objFields, String lblPrefix, String fldPrefix) {

		// Build a list of field names to use to iterate the Map of field object pointers
		Set <String> flds = new Set <String>();
		flds = objFields.keySet();

		// Add the keyset of field names to a list so that it can be sorted
		List<String> fldList = new List<String>();
		for (String f : flds) {
			fldList.add(f);
		}
		fldList.sort();

		Boolean  personAccountsEnabled = objFields.containsKey('ispersonaccount');
		Boolean  ignorePersonAcctFields = (personAccountsEnabled && fldList.size() > 300);

		List<SelectOption> options = new List<SelectOption>();
		for (String f : fldList) {
			String fldName = objFields.get(f).getDescribe().getName();
			if (ignorePersonAcctFields && fldName.endsWith('__pc')) {
				continue;
			}
			String fldLabel = objFields.get(f).getDescribe().getLabel();
			String fldType = ('' + objFields.get(f).getDescribe().getType()).replace('Schema.DisplayType.', '') ;
			// M.Smith, 05/25/2011: Ignore TEXTAREA and Encrypted fields as criteria fields
			if (fldType != 'REFERENCE' && fldType != 'TEXTAREA'
					&& fldType != 'ENCRYPTEDSTRING' && fldType != 'ID'
					&& fldName != 'IsDeleted' && fldName != 'SystemModstamp')  {
				options.add(new selectOption(fldType + '/' + fldPrefix + fldName, lblPrefix + fldLabel ));
			}
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
	public String buildWhereClause(Boolean showDebugMessages) {
		String cWhereClause = '';
		this.debugMode = showDebugMessages;

		this.errMsg = '';
		if (String.isEmpty(this.SearchField)) {
			return '';
		}

		String field = String.escapeSingleQuotes(this.searchField);
		if (field.startsWith('_') && field.endsWith('_')) {
			field = 'STRING/OwnerId';
		}

		// Get the field type, field name, and query friendly search value
		String fldType = field.split('/')[0];
		String fldName = field.split('/')[1];
		String fldValue = (!String.isEmpty(this.searchValue) ? String.escapeSingleQuotes(this.searchValue) : '');

		if (showDebugMessages) {
			ApexPages.AddMessage(new ApexPages.Message(ApexPages.Severity.INFO,
				fldType + '/' + fldName + ' ' + this.searchOperator + ' ' + fldValue )) ;
		}

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
				&& (this.SearchOperator == 'starts' || this.SearchOperator == 'contains' ||
					this.SearchOperator == 'notcontain' || this.SearchOperator == 'in' ||
					this.SearchOperator == 'notin')) {
			this.errMsg = 'Invalid Operator for this Field Type';
		}

		// If this is a string/picklist type AND there is a comma in the search value
		// then assume that we'll use IN or NOT IN
		String cCloseCharacter = '';
		String cOperator = '';
		if (fldType == 'STRING' || fldType == 'EMAIL' || fldType == 'PICKLIST' ||
				fldType == 'MULTIPICKLIST' || fldType == 'TEXTAEA') {
			if (!fldValue.contains(',')) {
				// No comma, so just use =, !=
				if (this.SearchOperator == 'eq') {
					cOperator = '=';
				}
				if (this.SearchOperator == 'ne') {
					cOperator = '!=';
				}
			} else {
				// comma present and
				if (this.SearchOperator == 'eq' || this.SearchOperator == 'in') {
					cOperator = ' IN (';
				}
				if (this.SearchOperator == 'ne' || this.SearchOperator == 'notin') {
					cOperator = ' NOT IN (';
				}
				cCloseCharacter = ')';
			}
		} else {
			if (this.SearchOperator == 'eq') {
				cOperator = '=';
			}
			if (this.SearchOperator == 'ne') {
				cOperator = '!=';
			}
		}

		if (this.SearchOperator == 'gt') cOperator = '>';
		if (this.SearchOperator == 'lt') cOperator = '<';
		if (this.SearchOperator == 'ge') cOperator = '>=';
		if (this.SearchOperator == 'le') cOperator = '<=';

		if (fldType == 'STRING' || fldType == 'EMAIL' || fldType == 'PICKLIST' ||
				fldType == 'MULTIPICKLIST' || fldType == 'TEXTAEA') {
			if (this.SearchOperator == 'starts') {
				cOperator = ' LIKE \'';
				cCloseCharacter = '%\'';
			}
			if (this.SearchOperator == 'contains') {
				cOperator = ' LIKE \'%';
				cCloseCharacter = '%\'';
			}
			if (this.SearchOperator == 'notcontain') {
				// NOT LIKE requires parenthesis around the whole condition, including the fieldname
				cWhereClause = ' AND (NOT(' + fldName ;
				cOperator = ' LIKE \'%';
				cCloseCharacter = '%\'))';
			}
			if (this.SearchOperator == 'in' && fldType == 'MULTIPICKLIST') {
				cOperator = ' INCLUDES (';
				cCloseCharacter = ')';
			}
			if (this.SearchOperator == 'notin' && fldType == 'MULTIPICKLIST') {
				cOperator = ' EXCLUDES (';
				cCloseCharacter = ')';
			}
			if (this.SearchOperator == 'in' && fldType != 'MULTIPICKLIST') {
				cOperator = ' IN (';
				cCloseCharacter = ')';
			}
			if (this.SearchOperator == 'notin' && fldType != 'MULTIPICKLIST') {
				cOperator = ' NOT IN (';
				cCloseCharacter = ')';
			}
		}
		cWhereClause += cOperator;

		if (String.isEmpty(cOperator)) {
			this.errMsg = 'Invalid Operator for this field';
		}

		if (fldType == 'STRING' || fldType == 'EMAIL' || fldType == 'PICKLIST' ||
				fldType == 'MULTIPICKLIST' || fldType == 'TEXTAEA') {

			if (cCloseCharacter.startsWith('%')) {
				// Using LIKE ('Starts With' or 'Contains')
				cWhereClause += fldValue ;
			} else if (!fldValue.contains(',')) {
				// Standard single = value
				cWhereClause += '\'' + fldValue + '\'';
			} else {
				// Multiple Values (IN or NOT IN)
				String[] multValues = fldValue.split(',');
				for (String v : multValues) {
					cWhereClause += '\'' + v.trim() + '\',';
				}
				cWhereClause = cWhereClause.subString(0, cWhereClause.length()-1);
			}

		} else if (fldType == 'DATE' || fldType == 'DATETIME') {

			// For the various Date/Time constants (ex: LAST 60 DAYS) need an Underscore instead of space
			if (fldValue.toUpperCase().startsWith('NEXT') || fldValue.toUpperCase().startsWith('LAST')) {
				// If this is NEXT xxx DAYS/MONTHS/YEARS etc., then need to reorder the criteria to
				// NEXT_N_DAYS:yyy
				String fldVal2 = fldValue.subString(5).trim().toUpperCase();
				if (fldVal2.contains(' ')) {
					List<String> fldSplit = fldVal2.split(' ');
					String fldNum = fldSplit[0].trim();
					// If the 2nd word is one of these then no numbers, just a straight value
					if (!(fldNum == 'WEEK' || fldNum == 'MONTH' || fldNum == 'QUARTER' || fldNum == 'YEAR' || fldNum == 'FISCAL')) {
						String fldPeriod = '';
						for (integer y = 1; y < fldSplit.size(); y++) {
							fldPeriod += fldSplit[y].trim() + ' ';
						}
						fldPeriod = fldPeriod.trim();
						fldValue = fldValue.subString(0,4).trim().toUpperCase() + '_N_' + fldPeriod + ':' + fldNum;
						// this.errMsg = 'fldNum:' + fldNum + ', fldPeriod:' + fldPeriod;
					}
				}
			} else if (fldValue.toUpperCase().startsWith('TODAY') ||
					fldValue.toUpperCase().startsWith('YESTERDAY') ||
					fldValue.toUpperCase().startsWith('TOMORROW') ||
					fldValue.toUpperCase().startsWith('THIS')) {
				// No issues here
			} else {
				try {
					Date testDate = stringToDate(fldValue);
					// Rebuild the date String as YYYY-MM-DD
					String m = testDate.month().format();
					String d = testDate.day().format();
					if (integer.valueOf(m) < 10) {
						m = '0' + m;
					}
					if (integer.valueOf(d) < 10) {
						d = '0' + d;
					}
					fldValue = testDate.year() + '-' + m + '-' + d;

					// For DATETIME types, must add the hours AND we need to make it a compound condition
					//     (field >= START AND field <= END)
					// Example: field = 12/31/2008 will be translated to
					//      field >= 2008-12-31T00:00:00Z AND field <= 2008-12-31T23:59:59Z
					if (fldType == 'DATETIME') {
						// This creates a DateTime at midnight in the users current timezone
						Datetime testDateTm = Datetime.newInstance(testDate.year(), testDate.month(),testDate.day());

						// If the operator is equals/not equals then need a range for the entire day
						// if the operator is greater or less, then we can just use the datetime
						// but we'll need to adjust based on midnight or 23:59:59pm
						if (cOperator == '=') {
							cWhereClause = ' AND (' + fldName + ' >= ';
							fldValue = testDateTm.format('yyyy-MM-dd') + 'T00:00:00Z';
							cWhereClause += fldValue + ' AND ' + fldName + ' <= ' ;
							fldValue = testDateTm.format('yyyy-MM-dd') + 'T23:59:59Z';
							cCloseCharacter = ')';
						} else if (cOperator == '!=') {
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
				} catch (Exception ex) {
					this.errMsg = 'Invalid Date Format (' + InputDateFormat + '): ' + ex.getMessage();
				}
			}
			cWhereClause += fldValue.replace(' ', '_').toUpperCase();
		} else if (fldType == 'CURRENCY' || fldType == 'DOUBLE' || fldType == 'BOOLEAN' ||
				fldType == 'INTEGER' || fldType == 'PERCENT') {
			cWhereClause += fldValue ;
		} else {
			cWhereClause += '\'' + fldValue + '\'';
		}
		cWhereClause += cCloseCharacter ;

		if (!String.isEmpty(this.errMsg)) {
			return '';
		}
		return cWhereClause;
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
			ApexPages.AddMessage(new ApexPages.Message(
				ApexPages.Severity.INFO, 's=' + s, '' )) ;
			ApexPages.AddMessage(new ApexPages.Message(
				ApexPages.Severity.INFO, 'InputDateSep=' + inputDateSep, '' )) ;
			ApexPages.AddMessage(new ApexPages.Message(
				ApexPages.Severity.INFO, 'InputDateFormat=' + inputDateFormat, '' )) ;
			ApexPages.AddMessage(new ApexPages.Message(
				ApexPages.Severity.INFO, 'stringDate=' + stringDate.size(), '' )) ;
		}

		if (inputDateFormat.subString(0,2) == 'MM') {
			m = Integer.valueOf(stringDate[0]);
			d = Integer.valueOf(stringDate[1]);
			y = Integer.valueOf(stringDate[2]);
		} else if (inputDateFormat.subString(0,2) == 'DD') {
			d = Integer.valueOf(stringDate[0]);
			m = Integer.valueOf(stringDate[1]);
			y = Integer.valueOf(stringDate[2]);
		} else if (inputDateFormat.subString(0,2) == 'YY') {
			y = Integer.valueOf(stringDate[0]);
			m = Integer.valueOf(stringDate[1]);
			d = Integer.valueOf(stringDate[2]);
		}

		if (y < 100 && y > 80) {
			y += 1900;
		}
		if (y < 100) {
			y += 2000;
		}
		return Date.newInstance(y,m,d);
	}
}
