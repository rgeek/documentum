/**
 * ViewModel for the Advanced Search panel. Holds the remote lookup store used
 * by the Card 1 "Value" combo, plus the two free-text criteria values that are
 * bound to their fields.
 */
Ext.define('AdvSearchFilter.view.search.AdvancedSearchFilterModel', {
  extend: 'Ext.app.ViewModel',
  alias: 'viewmodel.dctm-advsearchfilter',

  stores: {
    lookupValues: {
      type: 'lookupvalues'
    },
    // Local stores backing the "Attribute" and "Operator" combos. They are
    // repopulated by the controller (refreshAttrStore / populateOperators) from
    // the backend config, and are bound to the combos below so the controller
    // never has to call setStore() on a child reference.
    attrStore: {
      fields: ['key', 'label', 'attribute'],
      data: []
    },
    operatorStore: {
      fields: ['value', 'label'],
      data: []
    }
  },

  data: {
    exactPhrase: '',
    wildcard: ''
  }
});
