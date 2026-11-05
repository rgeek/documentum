Ext.namespace('tro.functions');
tro.functions.returnToPreviousPage = function () {
    if (window.history.length > 1) {
        window.history.back();
    } else {
        alert('No previous page found.');
    }
    return "";
};