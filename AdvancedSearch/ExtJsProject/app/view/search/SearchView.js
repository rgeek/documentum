Ext.define('DocumentumSearch.view.search.SearchView', {
  extend: 'Ext.panel.Panel',
  alias: 'widget.dctm-advancedsearch',
  controller: 'dctm-advancedsearch',

  layout: { type: 'vbox', align: 'stretch' },

  items: [
    {
      xtype: 'form',
      title: 'Advanced Search',
      scrollable: true,
      maxHeight: 560,
      bodyPadding: 12,
      layout: { type: 'vbox', align: 'stretch' },
      defaults: { labelAlign: 'top', labelSeparator: '' },
      items: [
        {
          xtype: 'container',
          layout: { type: 'hbox', align: 'stretch' },
          items: [
            {
              xtype: 'container',
              flex: 1,
              layout: { type: 'vbox', align: 'stretch' },
              defaults: { labelAlign: 'top', labelSeparator: '' },
              items: [
                {
                  xtype: 'combobox',
                  reference: 'typeCombo',
                  fieldLabel: 'Object type',
                  queryMode: 'local',
                  triggerAction: 'all',
                  queryCaching: false,
                  displayField: 'label',
                  valueField: 'name',
                  store: { fields: ['name', 'label'], data: [], filters: [] },
                  editable: true,
                  forceSelection: true,
                  typeAhead: false,
                  minChars: 1,
                  queryDelay: 30,
                  anyMatch: true,
                  caseSensitive: false,
                  emptyText: 'Loading types…',
                  listConfig: { emptyText: 'No matches' },
                  listeners: { change: 'onTypeChange' }
                },
                {
                  xtype: 'component',
                  reference: 'typesError',
                  html: ''
                },
                {
                  xtype: 'textfield',
                  reference: 'fulltext',
                  fieldLabel: 'Full-text keyword (optional)',
                  emptyText: 'Search within document content…'
                }
              ]
            },
            {
              xtype: 'container',
              flex: 1,
              margin: '0 0 0 16',
              layout: { type: 'vbox', align: 'stretch' },
              items: [
                {
                  xtype: 'checkboxfield',
                  reference: 'conditionsToggle',
                  boxLabel: 'Add conditions',
                  listeners: { change: 'onConditionsToggle' }
                },
                {
                  xtype: 'fieldset',
                  reference: 'conditionsFieldset',
                  title: 'Conditions',
                  hidden: true,
                  margin: '8 0 0 0',
                  padding: '8 8 4 8',
                  layout: { type: 'vbox', align: 'stretch' },
                  items: [
                    {
                      xtype: 'container',
                      layout: { type: 'hbox', align: 'middle' },
                      items: [
                        { xtype: 'component', html: 'Combine with', margin: '0 8 0 0' },
                        {
                          xtype: 'segmentedbutton',
                          reference: 'conjunction',
                          items: [
                            { text: 'AND', value: 'AND', pressed: true },
                            { text: 'OR', value: 'OR' }
                          ]
                        }
                      ]
                    },
                    {
                      xtype: 'component',
                      reference: 'attributesHint',
                      html: '',
                      margin: '6 0 0 0'
                    },
                    {
                      xtype: 'container',
                      reference: 'conditionsCt',
                      layout: { type: 'vbox', align: 'stretch' },
                      margin: '6 0 0 0'
                    },
                    {
                      xtype: 'component',
                      reference: 'conditionsHint',
                      html: '',
                      margin: '4 0 0 0'
                    },
                    {
                      xtype: 'button',
                      text: '+ Add condition',
                      width: 140,
                      margin: '6 0 0 0',
                      handler: 'addCondition'
                    }
                  ]
                }
              ]
            }
          ]
        },
        {
          xtype: 'container',
          layout: { type: 'hbox', align: 'bottom' },
          margin: '12 0 0 0',
          items: [
            {
              xtype: 'combobox',
              reference: 'pageSize',
              fieldLabel: 'Results per page',
              labelAlign: 'top',
              labelSeparator: '',
              width: 160,
              queryMode: 'local',
              displayField: 'label',
              valueField: 'value',
              value: 10,
              editable: false,
              store: {
                fields: ['value', 'label'],
                data: [
                  { value: 5, label: '5' },
                  { value: 10, label: '10' },
                  { value: 25, label: '25' },
                  { value: 50, label: '50' }
                ]
              }
            },
            { xtype: 'component', flex: 1 },
            {
              xtype: 'button',
              reference: 'searchBtn',
              text: 'Search',
              margin: '0 6 0 0',
              handler: 'onSearch'
            },
            {
              xtype: 'button',
              reference: 'resetBtn',
              text: 'Reset',
              handler: 'onReset'
            }
          ]
        },
        {
          xtype: 'component',
          reference: 'validationMsg',
          html: '',
          margin: '10 0 0 0',
          cls: 'search-error',
          hidden: true
        },
        {
          xtype: 'container',
          margin: '10 0 0 0',
          layout: { type: 'vbox', align: 'stretch' },
          items: [
            {
              xtype: 'button',
              reference: 'jsonToggle',
              text: 'Show request JSON',
              width: 160,
              handler: 'onToggleJson'
            },
            {
              xtype: 'textareafield',
              reference: 'jsonPre',
              hidden: true,
              readOnly: true,
              height: 200,
              fieldLabel: 'Request JSON',
              labelAlign: 'top',
              labelSeparator: ''
            }
          ]
        }
      ]
    },
    {
      xtype: 'panel',
      flex: 1,
      minHeight: 400,
      reference: 'resultsPanel',
      title: 'Results',
      layout: 'card',
      tbar: [
        { xtype: 'button', reference: 'prevBtn', text: '← Previous', disabled: true, handler: 'onPrev' },
        { xtype: 'tbtext', reference: 'pageText', text: '' },
        { xtype: 'button', reference: 'nextBtn', text: 'Next →', disabled: true, handler: 'onNext' },
        '->',
        { xtype: 'tbtext', reference: 'statusText', text: '' }
      ],
      items: [
        {
          xtype: 'container',
          reference: 'messageCard',
          scrollable: true,
          padding: 16,
          html: 'Choose a type and add a condition or keyword, then run a search.'
        },
        {
          xtype: 'gridpanel',
          reference: 'resultsGrid',
          store: {
            fields: ['r_object_id', 'object_name', 'r_object_type', 'r_modify_date', 'r_content_size', 'summary', 'terms']
          },
          features: [{
            ftype: 'rowbody',
            getAdditionalData: function (data, idx, record) {
              var summary = record.get('summary');
              if (!summary) return null;
              return {
                rowBody: '<div style="padding: 6px 10px; color: #555; font-size: 12px;">' +
                  DocumentumSearch.lib.Format.highlight(summary, record.get('terms')) + '</div>'
              };
            }
          }],
          columns: [
            { text: 'Object ID', dataIndex: 'r_object_id', width: 150 },
            { text: 'Name', dataIndex: 'object_name', flex: 1, minWidth: 160 },
            { text: 'Type', dataIndex: 'r_object_type', width: 150 },
            {
              text: 'Modified',
              dataIndex: 'r_modify_date',
              width: 170,
              renderer: function (v) { return DocumentumSearch.lib.Format.formatDate(v); }
            },
            {
              text: 'Size',
              dataIndex: 'r_content_size',
              width: 90,
              align: 'right',
              renderer: function (v) { return DocumentumSearch.lib.Format.formatBytes(v); }
            }
          ]
        }
      ]
    }
  ]
});
