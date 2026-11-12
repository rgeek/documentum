/**
 * "Advanced Search" panel: a vertical form with two criteria cards and a clear
 * footer. The generated JSON contract is produced by the controller's
 * getSearchCriteria() and persisted to sessionStorage as the user edits.
 *
 * Card 1 builds "match all" chips from configurable attributes. Each attribute
 * is backed by a type (string / date):
 *   - string attributes support Equal (single lookup value) or IN (multiple
 *     lookup values selected via a tag field).
 *   - date attributes support Between with two date inputs.
 *
 * Card 2 takes an exact phrase and an optional wildcard pattern.
 */
Ext.define('AdvSearchFilter.view.search.AdvancedSearchFilter', {
  extend: 'Ext.form.Panel',
  alias: 'widget.dctm-advsearchfilter',

  controller: 'dctm-advsearchfilter',
  viewModel: { type: 'dctm-advsearchfilter' },

  cls: 'adv-search-panel',
  scrollable: true,
  bodyPadding: 20,
  layout: { type: 'vbox', align: 'stretch' },

  items: [
    // --- Header ---
    { xtype: 'component', cls: 'adv-title', html: 'Advanced Search' },
    {
      xtype: 'component',
      cls: 'adv-subtitle',
      html: 'Find the right content using criteria, phrases and wildcards.',
      margin: '4 0 16 0'
    },

    // --- Card 1: All of these criteria (AND) ---
    {
      xtype: 'panel',
      cls: 'adv-card',
      bodyPadding: 16,
      margin: '0 0 12 0',
      layout: { type: 'vbox', align: 'stretch' },
      items: [
        {
          xtype: 'container',
          layout: { type: 'hbox', align: 'middle' },
          items: [
            { xtype: 'component', cls: 'adv-card-icon adv-icon-criteria', html: '&amp;' },
            {
              xtype: 'container',
              flex: 1,
              margin: '0 0 0 12',
              layout: { type: 'vbox', align: 'stretch' },
              items: [
                { xtype: 'component', cls: 'adv-card-title', html: 'All of these criteria' },
                { xtype: 'component', cls: 'adv-card-desc', html: 'Results must match all of these criteria (AND).' }
              ]
            }
          ]
        },
        {
          xtype: 'container',
          margin: '12 0 0 0',
          layout: { type: 'hbox', align: 'middle' },
          items: [
            {
              xtype: 'combobox',
              reference: 'attrCombo',
              flex: 1,
              bind: { store: '{attrStore}' },
              queryMode: 'local',
              triggerAction: 'all',
              queryCaching: false,
              displayField: 'label',
              valueField: 'key',
              editable: false,
              forceSelection: true,
              emptyText: 'Attribute…',
              listConfig: { emptyText: 'No attributes' },
              listeners: { change: 'onAttrChange' }
            },
            {
              xtype: 'combobox',
              reference: 'operatorCombo',
              flex: 1,
              margin: '0 0 0 8',
              bind: { store: '{operatorStore}' },
              queryMode: 'local',
              triggerAction: 'all',
              queryCaching: false,
              displayField: 'label',
              valueField: 'value',
              editable: false,
              forceSelection: true,
              disabled: true,
              emptyText: 'Operator…',
              listConfig: { emptyText: 'No operators' },
              listeners: { change: 'onOperatorChange' }
            },
            {
              xtype: 'combobox',
              reference: 'valueCombo',
              flex: 1,
              margin: '0 0 0 8',
              bind: { store: '{lookupValues}' },
              queryMode: 'local',
              triggerAction: 'all',
              queryCaching: false,
              displayField: 'label',
              valueField: 'value',
              forceSelection: true,
              typeAhead: true,
              minChars: 1,
              anyMatch: true,
              caseSensitive: false,
              queryDelay: 100,
              emptyText: 'Value…',
              disabled: true,
              listConfig: { emptyText: 'No values' },
              listeners: { change: 'onValueChange' }
            },
            {
              xtype: 'tagfield',
              reference: 'valueTag',
              flex: 1,
              margin: '0 0 0 8',
              bind: { store: '{lookupValues}' },
              queryMode: 'local',
              triggerAction: 'all',
              queryCaching: false,
              displayField: 'label',
              valueField: 'value',
              forceSelection: true,
              typeAhead: true,
              minChars: 1,
              anyMatch: true,
              caseSensitive: false,
              queryDelay: 100,
              emptyText: 'Select values…',
              disabled: true,
              hidden: true,
              listConfig: { emptyText: 'No values' },
              listeners: { change: 'onValueChange' }
            },
            {
              xtype: 'container',
              reference: 'dateRangeCt',
              flex: 1,
              margin: '0 0 0 8',
              hidden: true,
              layout: { type: 'hbox', align: 'middle' },
              items: [
                {
                  xtype: 'datefield',
                  reference: 'startDateField',
                  flex: 1,
                  format: 'd-M-Y',
                  submitFormat: 'd-M-Y',
                  emptyText: 'From date',
                  listeners: { change: 'onDateChange' }
                },
                {
                  xtype: 'component',
                  cls: 'adv-field-label',
                  html: 'and',
                  margin: '0 8'
                },
                {
                  xtype: 'datefield',
                  reference: 'endDateField',
                  flex: 1,
                  format: 'd-M-Y',
                  submitFormat: 'd-M-Y',
                  emptyText: 'To date',
                  listeners: { change: 'onDateChange' }
                }
              ]
            },
            {
              xtype: 'button',
              reference: 'addBtn',
              text: 'Add',
              margin: '0 0 0 8',
              disabled: true,
              handler: 'onAdd'
            }
          ]
        },
        { xtype: 'component', reference: 'valueStatus', cls: 'adv-value-status', html: '', margin: '4 0 0 0' },
        { xtype: 'container', reference: 'chipsCt', cls: 'adv-chips', margin: '8 0 0 0' },
        { xtype: 'component', reference: 'addRowHint', cls: 'adv-addrow-hint', html: '', margin: '4 0 0 0' }
      ]
    },

    // --- Card 2: Exact phrase / wildcard ---
    {
      xtype: 'panel',
      cls: 'adv-card',
      bodyPadding: 16,
      margin: '0 0 12 0',
      layout: { type: 'vbox', align: 'stretch' },
      items: [
        {
          xtype: 'container',
          layout: { type: 'hbox', align: 'middle' },
          items: [
            { xtype: 'component', cls: 'adv-card-icon adv-icon-phrase', html: '&ldquo;' },
            {
              xtype: 'container',
              flex: 1,
              margin: '0 0 0 12',
              layout: { type: 'vbox', align: 'stretch' },
              items: [
                { xtype: 'component', cls: 'adv-card-title', html: 'Exact phrase / wildcard' },
                { xtype: 'component', cls: 'adv-card-desc', html: 'Results must contain this phrase or match this pattern.' }
              ]
            }
          ]
        },
        {
          xtype: 'textfield',
          reference: 'exactPhraseField',
          margin: '12 0 0 0',
          emptyText: 'e.g. correspondence or claim*',
          listeners: { change: 'onInputChange' }
        }
      ]
    },

    // --- Footer: Clear all ---
    {
      xtype: 'container',
      margin: '4 0 12 0',
      layout: { type: 'hbox', align: 'middle' },
      items: [
        { xtype: 'button', reference: 'clearAllBtn', text: 'Clear all', cls: 'adv-clear-link', handler: 'onClearAll' }
      ]
    }
  ]
});
