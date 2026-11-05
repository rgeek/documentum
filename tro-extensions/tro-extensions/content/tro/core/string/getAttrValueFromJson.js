tro.functions.getAttrValueFromJson = function (jsonSessionKey, key) {

    var jsonData = sessionStorage.getItem(jsonSessionKey);

    if (!jsonData) {
        console.log("Json Data not found");
        return '';
    }

    try {

        var data = JSON.parse(jsonData);

        // Check top-level values such as exactPhrase and wildcard
        if (data[key] !== undefined) {
            console.log("Json Data value found"+data[key]);
            return data[key];
        }

        // Check matchAll attributes
        if (data.matchAll) {

            for (var i = 0; i < data.matchAll.length; i++) {

                if (data.matchAll[i].attribute === key) {
                    console.log("Json Data value found"+data.matchAll[i].value);
                    return data.matchAll[i].value;
                }
            }
        }

    } catch (e) {

        console.error("Error parsing JSON:", e);
    }

    return '';
};