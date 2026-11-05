Ext.define('AdvSearchFilter.view.MainContainer', {
  extend: 'Ext.container.Container',
  alias: 'widget.tro_advanced_search_filter',
    statics: {
    getSelectedFilterValue: function (context, compId) {
      var comp = context.getComponent(compId);
      var selectedFilterValue = "";
      if (!comp) {
        xcp.Logger.warn("Could not find the component with id : " + compId);
      } else {
        selectedFilterValue = comp.getSelectedFilterValue();
      }
      return xcp.core.expr.BaseExpression.sanitizeObjectUri(selectedFilterValue, context);
    }
  },

  layout: 'fit',

  items: [
    { xtype: 'dctm-advsearchfilter', margin: 16 }
  ],

  initComponent: function () {
    var me = this;
    me.selectedFilterValue = '';
    me.callParent();

    var panel = me.down('dctm-advsearchfilter');
    if (panel) {
      panel.on('search', me.onSearchCriteria, me);
    }
  },

  onSearchCriteria: function (criteria) {
    this.selectedFilterValue = JSON.stringify(criteria, null, 2);
  },

  getSelectedFilterValue: function () {
    return this.selectedFilterValue;
  }
});
