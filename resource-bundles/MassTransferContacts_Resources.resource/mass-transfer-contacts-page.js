/* *****************************************************************
* Page Javascript: MassTransferContacts
* Created: M.Smith, 07/23/2016
* http://www.force2b.net
*
* Modifications:
*
********************************************************************* */
/* top-level name-space */
var force2b = force2b || {};

/*
* Function called by the j$(document).ready() function to initialize the page
*/
force2b.onPageLoad = function() {

	// Disable buttons and options until there is data
	j$(".mtc-find-button").attr("disabled", true);
	j$(".mtc-transfer-button").attr("disabled", true);
	j$(".mtc-transfer-option").attr("disabled", true);

	// SLDS uses different page message styling.
	// This method restyles apex:pageMessage div's to match SLDS styling
	force2b.overridePageMessages();

	// SLDS does not provide a mechanism to show inline help pop-ups on hover
	// so build my own mechanism to place properly and render on a hover
	j$( "#mtc-help-icon-transfer-tasks" ).hover(
		function() {
			var helpPopupsTop = j$("#mtc-help-icon-transfer-tasks").offset().top-200;
			j$("#mtc-transfer-tasks-help").css("margin-top", helpPopupsTop + "px").show();
		},
		function() { 	j$( "#mtc-transfer-tasks-help" ).hide(); }
	);

	j$( "#mtc-help-icon-send-email" ).hover(
		function() {
			var helpPopupsTop = j$("#mtc-help-icon-send-email").offset().top-200;
			j$("#mtc-send-email-help").css("margin-top", helpPopupsTop + "px").show();
		},
		function() { 	j$( "#mtc-send-email-help" ).hide(); }
	);
};

/*
* On change of the filter field ...
* Shows lookup of Users depending on the value selected.
*/
force2b.onChangeFilterType = function(fieldType) {
	var parentRow$ = j$(fieldType).closest("tr");

	if (j$(fieldType).val() === "_active_" || j$(fieldType).val() === "_inactive_" ||
				j$(fieldType).val() === "_community_") {

		parentRow$.find("#mtc-criteria-from-user-lookup").show();
		parentRow$.find("#mtc-criteria-plain-text").hide();
		parentRow$.find(".mtc-search-operator").val("eq").attr("disabled",true);
		parentRow$.find(".mtc-search-value").val('');

	} else if (parentRow$.find(".mtc-search-operator").attr("disabled") === "disabled") {

		parentRow$.find("#mtc-criteria-plain-text").show();
		parentRow$.find("#mtc-criteria-from-user-lookup").hide();
		parentRow$.find(".mtc-search-operator").attr("disabled",false);
		parentRow$.find(".mtc-search-value").val('');

	}
};

var is_currently_searching = false;

/*
* Type-ahead search for finding the "To" or "From" user
* Uses Javascript Remoting to query active Users and then renders an SLDS
* format list as combofield in the UI.
*/
force2b.userSearchTypeAhead = function(inputField$) {

	var searchKey = inputField$.val();
	var resultsDiv$ = j$("#" + inputField$.attr('aria-activedescendant'));
	var resultsList$ = j$("#" + inputField$.attr('id') + "-results");
	var onSelectFunction = inputField$.data('onselectfunction');
	var rowNumber = inputField$.data('rownumber');
	if (!rowNumber) {
		rowNumber = '';
	}

	var userTypeSearch = null;
	if (rowNumber != '') {
		var parentRow$ = j$("#mtc-criteria-row-" + rowNumber);
		userTypeSearch = parentRow$.find(".mtc-search-field").val()
	}

	// If the search field is empty, disable the buttons and return
	if (searchKey === "") {
		resultsDiv$.hide();
		if (rowNumber === '') {
			// Only disable buttons for the 'To User' lookup
			j$(".mtc-find-button").attr("disabled", true);
			j$(".mtc-transfer-option").attr("disabled", true);
		}
	}

	// Avoid searching while a search is going on
	if (is_currently_searching === true) {
		return;
	}

	// Disable buttons while searching
	resultsDiv$.show();
	j$(".mtc-transfer-button").attr("disabled", true);
	j$(".mtc-transfer-option").attr("disabled", true);

	Visualforce.remoting.timeout = 5000;	// 5 seconds
	is_currently_searching = true;
	f2b.MassTransferContactsController.searchUsers(searchKey, userTypeSearch,
		function(result, event) {
				if (event.status && result) {

					// Render the search results on the page
					var resultsListHtml = "";
					if (result.length > 0) {
						for(var i=0; i < result.length; i++) {
							var userRecord = result[i];
							resultsListHtml += "<li>" +
								"<a class=\"slds-lookup__item-action slds-media slds-media--center\" href=\"javascript:void(0);\" role=\"option\"" +
										"onClick=\"force2b." + onSelectFunction + "('" + userRecord.Id +"', '" +
											userRecord.Name + "', '" + rowNumber + "');\">" +
									"<div class=\"slds-media__body\">" +
										"<div class=\"slds-lookup__result-text\"><b>" + userRecord.Name +
										"</b></div>" +
										"<span class=\"slds-lookup__result-meta slds-text-body--small\">" +
											userRecord.Username + " (" + userRecord.UserType +")" +
										"</span>" +
									"</div>" +
								"</a></li>";
								// Don't use the icon for spacing reasons
								/*'<svg aria-hidden="true" class="slds-icon slds-icon-standard-account slds-icon--small">' +
								'<use xlink:href="{!$Resource.SalesforceLightningDesignSystem_v202}/assets/icons/standard-sprite/svg/symbols.svg#user"></use></svg>' +*/
						}
					} else {
						resultsListHtml += "<li class=\"slds-lookup__item\">No Records Found</li>";
					}
					resultsList$.html(resultsListHtml);
				}
				is_currently_searching = false;
			}, { escape: true }
	);
};

/*
* When a "To" user is selected, hide the combo-box and enable the buttons
*/
force2b.selectToUser = function(userId, userName) {
	j$("#mtc-user-selection-typeahead").hide();
	j$("#mtc-input-user-lookup").val(userName);
	j$(".mtc-find-button").attr("disabled", false)
	j$(".mtc-transfer-button").attr("disabled", true);
	j$(".mtc-to-user-id").val(userId);
};

force2b.selectFromUser = function(userId, userName, rowNumber) {
	var parentRow$ = j$("#mtc-criteria-row-" + rowNumber);

	parentRow$.find("#mtc-from-user-selection-typeahead").hide();
	parentRow$.find("#mtc-input-from-user-lookup").val(userName);
	parentRow$.find(".mtc-search-value").val(userId);
};

/*
* SLDS uses different page message styling.
* This method restyles apex:pageMessage div's to match SLDS styling
* https://vishnuvaishnav.wordpress.com/2016/02/21/convert-standard-page-messages-in-lightning-design-system/
*/
force2b.overridePageMessages = function() {
	var textureEffect = "";
	//Uncomment below line for texture effect on page messages
	//textureEffect = "slds-theme--alert-texture";

	j$(".warningM3").addClass("slds-notify slds-notify--toast slds-theme--warning customMessage "+textureEffect);
	j$(".confirmM3").addClass("slds-notify slds-notify--alert slds-theme--success  customMessage "+textureEffect);
	j$(".errorM3").addClass("slds-notify slds-notify--alert slds-theme--error customMessage "+textureEffect);
	j$(".infoM3").addClass("slds-notify slds-notify--toast customMessage "+textureEffect);

	j$(".errorM3").removeClass("errorM3");
	j$(".confirmM3").removeClass("confirmM3");
	j$(".infoM3").removeClass("infoM3");
	j$(".warningM3").removeClass("warningM3");
};

/*
* Toggle the [un]select all contacts in the list
*/
force2b.toggleSelectAll = function(mode) {
	j$(".mtc-row-select-checkbox").attr("checked", mode);
};

/*
* When the [Find] button is clicked
*/
force2b.startContactSearch = function() {
	j$(".mtc-find-button").attr("disabled", true).prop('value', ' Searching ');
	j$(".mtc-transfer-button").attr("disabled", true);
}

/*
* When the [Find Contacts] search has completed, show the search results
* and enable the buttons
*/
force2b.finishedWithSearch = function() {
	j$("#mtc-search-results-header").show();
	j$(".mtc-transfer-button").attr("disabled", false);
	j$(".mtc-transfer-option").attr("disabled", false);
	j$(".mtc-find-button").attr("disabled", false).prop('value', ' Find ');
	force2b.overridePageMessages();
};

/*
* When the [Transfer] button is clicked
*/
force2b.startContactTransfer = function() {
	j$(".mtc-find-button").attr("disabled", true);
	j$(".mtc-transfer-button").attr("disabled", true).prop('value', ' Transferring ');
}

/*
* When the [Transfer] has completed
*/
force2b.finishedWithTransfer = function() {
	j$(".mtc-transfer-button").attr("disabled", false).prop('value', ' Transfer Selected ');
	j$(".mtc-find-button").attr("disabled", false);
	force2b.overridePageMessages();
}
