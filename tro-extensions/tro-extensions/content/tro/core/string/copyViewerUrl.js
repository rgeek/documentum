
Ext.namespace('tro.functions');

tro.functions.copyViewerUrl = function () {

    var viewerUrl = window.location.href;

    if (navigator.clipboard) {
        navigator.clipboard.writeText(viewerUrl);
    } else {
        var temp = document.createElement("textarea");
        temp.value = viewerUrl;
        document.body.appendChild(temp);
        temp.select();
        document.execCommand("copy");
        document.body.removeChild(temp);
    }

    return viewerUrl;
};
