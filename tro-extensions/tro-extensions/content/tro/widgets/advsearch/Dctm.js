Ext.ns('DocumentumSearch.lib');

DocumentumSearch.lib.Dctm = {
  getEntries: function (feed) {
    if (!feed) return [];
    if (Ext.isArray(feed.entries)) return feed.entries;
    return [];
  },

  getProperties: function (entry) {
    if (!entry) return {};
    if (entry.content && entry.content.properties) return entry.content.properties;
    if (entry.properties) return entry.properties;
    return {};
  }
};
