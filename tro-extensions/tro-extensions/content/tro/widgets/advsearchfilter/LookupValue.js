/**
 * A single lookup value returned by GET /api/lookup (a bare JSON array of
 * { value, label } objects — see app/store/LookupValues.js).
 */
Ext.define('AdvSearchFilter.model.LookupValue', {
  extend: 'Ext.data.Model',

  fields: [
    { name: 'value', type: 'string' },
    { name: 'label', type: 'string' }
  ]
});
