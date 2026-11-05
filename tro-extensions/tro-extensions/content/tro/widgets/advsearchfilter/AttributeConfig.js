/**
 * Runtime source of truth for the configurable "All of these criteria"
 * attributes in the Advanced Search panel. The attribute list, data type, and
 * available operators are fetched from GET /api/search/attributes instead of
 * being hardcoded, so they can be changed server-side without a frontend build.
 *
 * Each entry:
 *   key       -> the lookup key sent to GET /api/lookup?attribute={key}
 *   label     -> the human-readable name shown in the dropdown and chips
 *   attribute -> the real Documentum property name written into the JSON
 *                contract ("attribute" field of each matchAll entry)
 *   type      -> 'string' (lookup-backed, Equal / IN) or 'date' (Between)
 *   operators -> [{ value, label }] operators available for this attribute
 */
Ext.define('AdvSearchFilter.config.AttributeConfig', {
  singleton: true,

  attributes: [],

  load: function (callback) {
    var me = this;

    Ext.Ajax.request({
      url: '/api/search/attributes',
      method: 'GET',
      timeout: 30000,
      success: function (response) {
        var obj = Ext.JSON.decode(response.responseText, true);
        var attrs = (obj && Ext.isArray(obj.attributes)) ? obj.attributes : [];
        me.attributes = attrs;
        callback(null, attrs);
      },
      failure: function () {
        me.attributes = [];
        callback(new Error('Failed to load search attributes'), null);
      }
    });
  },

  byKey: function (key) {
    var list = this.attributes;
    for (var i = 0; i < list.length; i++) {
      if (list[i].key === key) return list[i];
    }
    return null;
  },

  byAttribute: function (attribute) {
    var list = this.attributes;
    for (var i = 0; i < list.length; i++) {
      if (list[i].attribute === attribute) return list[i];
    }
    return null;
  }
});
