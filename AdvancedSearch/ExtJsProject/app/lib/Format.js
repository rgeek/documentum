Ext.ns('DocumentumSearch.lib');

DocumentumSearch.lib.Format = {
  formatBytes: function (bytes) {
    if (bytes == null || isNaN(bytes)) return '—';
    var n = Number(bytes);
    if (n === 0) return '0 B';
    var units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = Math.floor(Math.log(n) / Math.log(1024));
    var value = n / Math.pow(1024, i);
    return value.toFixed(value >= 100 || i === 0 ? 0 : 1) + ' ' + units[i];
  },

  formatDate: function (value) {
    if (!value) return '—';
    var d = new Date(value);
    if (isNaN(d.getTime())) return String(value);
    return d.toLocaleString();
  },

  // Highlight each matched search term in a snippet with a yellow background.
  // `terms` is the entry.terms array returned by the Documentum search feed.
  highlight: function (text, terms) {
    var escaped = Ext.htmlEncode(String(text == null ? '' : text));
    if (terms && typeof terms === 'string') terms = terms.split(/\s+/);
    if (!Ext.isArray(terms) || !terms.length) return escaped;

    Ext.Array.each(terms, function (term) {
      term = String(term == null ? '' : term).trim();
      if (!term) return;

      var escapedTerm = Ext.String.escapeRegex(Ext.htmlEncode(term));
      var wholeWord = /^\w/.test(term) && /\w$/.test(term);
      var pattern = (wholeWord ? '\\b' : '') + escapedTerm + (wholeWord ? '\\b' : '');

      escaped = escaped.replace(new RegExp(pattern, 'gi'), function (match) {
        return '<span style="background:#ffff00;">' + match + '</span>';
      });
    });

    return escaped;
  }
};
