/**
 * Remote store backing the "Value" combo in Card 1. It is loaded on demand
 * with { attribute: <key> } by the controller whenever the selected attribute
 * changes. The endpoint returns a bare array, which Ext's JSON reader accepts
 * directly as the record root (no rootProperty needed).
 */
Ext.define('AdvSearchFilter.store.LookupValues', {
  extend: 'Ext.data.Store',
  alias: 'store.lookupvalues',

  model: 'AdvSearchFilter.model.LookupValue',

  autoLoad: false,

  sorters: [
    { property: 'label', direction: 'ASC' }
  ],

  proxy: {
    type: 'ajax',
    url: window.location.protocol + '//' +  window.location.hostname + ':4000/api/lookup',
    timeout: 30000,
    reader: { type: 'json' }
  }
});
