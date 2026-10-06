Ext.ns('DocumentumSearch.lib');

// Thin wrapper around the existing Node/Express proxy. The Ext app is served
// from the same origin as the proxy, so relative /api/* URLs work directly.
DocumentumSearch.lib.Api = {
  baseUrl: '',

  request: function (method, path, params, jsonBody) {
    var me = this;
    return new Ext.Promise(function (resolve, reject) {
      Ext.Ajax.request({
        url: me.baseUrl + path,
        method: method,
        params: params,
        jsonData: jsonBody,
        timeout: 30000,
        success: function (response) {
          var data;
          try {
            data = Ext.decode(response.responseText);
          } catch (e) {
            data = response.responseText;
          }
          resolve(data);
        },
        failure: function (response) {
          var detail = null;
          try {
            detail = Ext.decode(response.responseText);
          } catch (e) { /* not JSON */ }

          var msg;
          if (response.status === 0) {
            msg = 'Cannot reach the proxy server. Is the backend running?';
          } else if (detail && (detail.error || detail.message)) {
            msg = (detail.error ? detail.error + ': ' : '') + (detail.message || '');
          } else {
            msg = 'Request failed with status ' + response.status;
          }

          reject({ message: msg, status: response.status, detail: detail });
        }
      });
    });
  },

  getTypes: function () {
    return this.request('GET', '/api/types');
  },

  getType: function (name) {
    return this.request('GET', '/api/types/' + encodeURIComponent(name));
  },

  search: function (body, params) {
    return this.request('POST', '/api/search', params, body);
  }
};
