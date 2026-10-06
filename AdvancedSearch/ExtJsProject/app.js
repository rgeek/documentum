Ext.application({
  name: 'DocumentumSearch',
  launch: function () {
    // Local dev/demo only: boot the same widget class that xCP instantiates.
    // The widget is registered as xtype 'dctm-advancedsearch' (see
    // app/view/search/SearchView.js). In xCP, reference that xtype directly in
    // your page definition — no Ext.application / renderTo is needed there.
    Ext.create('DocumentumSearch.view.MainContainer', {
      renderTo: 'search-app',
      height: '100%'
    });
  }
});
