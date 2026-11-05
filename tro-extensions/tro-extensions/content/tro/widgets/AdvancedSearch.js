Ext.define('DocumentumSearch.view.MainContainer', {
  extend: 'Ext.container.Container',
  alias: 'widget.tro_advanced_search',

  layout: 'fit',

  items: [
    { xtype: 'dctm-advancedsearch', margin: 16 }
  ]
});
