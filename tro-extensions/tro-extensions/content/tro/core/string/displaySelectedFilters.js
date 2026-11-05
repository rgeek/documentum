// displaySelectedFilters.js
Ext.namespace ('tro.functions');




tro.functions.displaySelectedFilters = function () {
	
var json = sessionStorage.getItem("advSearchFilterJson");

if (json) {
    try {
        var data = JSON.parse(json);
        var outputParts = [];
        var matchAll = data.matchAll || [];

        for (var i = 0; i < matchAll.length; i++) {
            var item = matchAll[i];

            outputParts.push(
                item.field + ' = "' + item.value + '"'
            );
        }

        if (data.exactPhrase) {
            outputParts.push(
                'Exact Phrase = "' + data.exactPhrase + '"'
            );
        }

        if (data.wildcard) {
            outputParts.push(
                'Wildcard = "' + data.wildcard + '"'
            );
        }

        var output = outputParts.join(", ");

        return output;

    } catch (error) {
        return "Invalid search filter JSON";
    }
}
};

