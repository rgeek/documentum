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
    }
  },

  data: {
    exactPhrase: '',
    wildcard: ''
  }
});
