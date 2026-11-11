/**
 * "Advanced Search" panel: a vertical form with three criteria cards, a
 * clear/search footer, and a read-only "Search request" JSON panel.
 *
 * Card 1 builds "match all" chips from configurable attributes; Card 2 takes an
 * exact phrase; Card 3 takes an optional wildcard pattern. The readable JSON
 * contract is produced by the controller's getSearchCriteria().
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

    // --- Card 2: Exact phrase ---
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
                { xtype: 'component', cls: 'adv-card-title', html: 'Exact phrase/Wildcards(Optional)' },
                { xtype: 'component', cls: 'adv-card-desc', html: 'Results must contain this exact phrase OR Match names using wildcard characters.' }
              ]
            }
          ]
        },
        {
          xtype: 'textfield',
          reference: 'exactPhraseField',
          margin: '12 0 0 0',
          emptyText: 'e.g. correspondence',
          listeners: { change: 'onInputChange' }
        }
      ]
    },

    // --- Card 3: Wildcards (optional) ---
    /*{
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
            { xtype: 'component', cls: 'adv-card-icon adv-icon-wildcard', html: '*' },
            {
              xtype: 'container',
              flex: 1,
              margin: '0 0 0 12',
              layout: { type: 'vbox', align: 'stretch' },
              items: [
                { xtype: 'component', cls: 'adv-card-title', html: 'Wildcards (optional)' },
                { xtype: 'component', cls: 'adv-card-desc', html: 'Match names using wildcard characters.' }
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
              xtype: 'textfield',
              reference: 'wildcardField',
              flex: 1,
              emptyText: 'claim*',
              listeners: { change: 'onInputChange' }
            },
            {
              xtype: 'component',
              cls: 'adv-info-icon',
              html: '&#9432;',
              margin: '0 0 0 8',
              tooltip: 'e.g. document*, d?ment'
            }
          ]
        },
        { xtype: 'component', reference: 'wildcardError', cls: 'adv-field-error', html: '', margin: '4 0 0 0', hidden: true }
      ]
    }*/,

    // --- Footer: Clear all (left) / Search (right) ---
    {
      xtype: 'container',
      margin: '4 0 12 0',
      layout: { type: 'hbox', align: 'middle' },
      items: [
        { xtype: 'button', reference: 'clearAllBtn', text: 'Clear all', cls: 'adv-clear-link', handler: 'onClearAll' },
        { xtype: 'component', flex: 1 },
        { xtype: 'button', reference: 'searchBtn', text: 'Done', scale: 'medium', disabled: true, handler: 'onSearch' }
      ]
    },

    // --- Search request JSON (collapsible) ---
    {
      xtype: 'fieldset',
      title: 'Search request',
      collapsible: true,
      collapsed: true,
      items: [
        {
          xtype: 'textareafield',
          reference: 'jsonOutput',
          anchor: '100%',
          readOnly: true,
          height: 220,
          emptyText: 'Run a search to build the request JSON.'
        }
      ]
    }
  ]
});
