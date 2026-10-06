Ext.define('DocumentumSearch.view.search.SearchController', {
  extend: 'Ext.app.ViewController',
  alias: 'controller.dctm-advancedsearch',

  init: function () {
    var me = this;
    var SQ = DocumentumSearch.lib.SearchQuery;

    me.timeUnitStore = Ext.create('Ext.data.Store', {
      fields: ['value', 'label'],
      data: Ext.Array.map(SQ.TIME_UNITS, function (u) {
        return { value: u, label: u.toLowerCase() + 's' };
      })
    });

    me.boolStore = Ext.create('Ext.data.Store', {
      fields: ['value', 'label'],
      data: [
        { value: 'true', label: 'true' },
        { value: 'false', label: 'false' }
      ]
    });

    me.conditionRows = [];
    me.attributes = [];
    me.attrMap = {};
    me.nextConditionId = 1;
    me.lastQuery = null;
    me.loading = false;
    me.currentPage = 0;
    me.total = null;
    me.hasPrev = false;
    me.hasNext = false;

    me.loadTypes();
  },

  // --- object types ---

  loadTypes: function () {
    var me = this;
    var combo = me.lookupReference('typeCombo');

    combo.disable();
    combo.setEmptyText('Loading types…');

    DocumentumSearch.lib.Api.getTypes().then(function (types) {
      // The proxy now returns a flat [{ name, label }] list, where `label` is
      // the human-readable type label (dmi_dd_type_info.label_text).
      var list = Ext.isArray(types) ? types : [];
      var names = Ext.Array.map(list, function (t) { return t.name; })
        .filter(function (n) { return !!n; })
        .sort();

      me.types = names;
      combo.getStore().loadData(Ext.Array.map(list, function (t) {
        return { name: t.name, label: t.label || t.name };
      }));
      combo.setEmptyText('Select an object type…');
      combo.enable();
    }, function (err) {
      combo.setEmptyText('Failed to load types');
      combo.enable();
      me.lookupReference('typesError').update('<span class="search-error">' + Ext.htmlEncode(err.message) + '</span>');
    });
  },

  onTypeChange: function (combo, name) {
    var me = this;
    me.clearConditions();
    me.clearResults();
    me.hideValidation();
    me.lastQuery = null;
    me.lookupReference('jsonPre').hide();
    me.lookupReference('jsonToggle').setText('Show request JSON');
    me.lookupReference('typesError').update('');

    me.attributes = [];
    me.attrMap = {};

    if (!name) return;

    me.setAttributesHint('Loading attributes…');

    DocumentumSearch.lib.Api.getType(name).then(function (meta) {
      var props = (meta && meta.properties) || [];
      me.attributes = props
        .filter(function (p) { return !p.hidden && p.searchable !== false; })
        .map(function (p) {
          return { name: p.name, type: p.type, repeating: !!p.repeating, label: p.label || p.name };
        })
        .sort(function (a, b) { return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0); });

      me.attrMap = {};
      Ext.Array.each(me.attributes, function (a) {
        me.attrMap[a.name] = { type: a.type, repeating: a.repeating };
      });

      me.setAttributesHint('');
      me.refreshConditionsHint();
    }, function (err) {
      me.setAttributesHint('<span class="search-error">' + Ext.htmlEncode(err.message) + '</span>');
    });
  },

  setAttributesHint: function (html) {
    this.lookupReference('attributesHint').update(html || '');
  },

  // --- conditions ---

  addCondition: function () {
    var me = this;

    var row = { id: me.nextConditionId++ };
    row.attrName = '';
    row.operator = '';
    row.valueField = null;
    row.valueField2 = null;
    row.timeUnitField = null;
    row.isValueDate = false;
    row.isValue2Date = false;

    row.attrCombo = Ext.widget('combobox', {
      flex: 1,
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
      emptyText: 'Attribute…',
      listConfig: { emptyText: 'No matches' },
      margin: '0 4 0 0'
    });

    row.opCombo = Ext.widget('combobox', {
      flex: 1,
      queryMode: 'local',
      displayField: 'label',
      valueField: 'value',
      store: { fields: ['value', 'label'], data: [] },
      editable: false,
      emptyText: 'Operator…',
      disabled: true,
      margin: '0 4 0 0'
    });

    row.valueCt = Ext.widget('container', {
      flex: 2,
      layout: { type: 'hbox', align: 'stretch' },
      margin: '0 4 0 0'
    });

    var removeBtn = Ext.widget('button', {
      text: '×',
      tooltip: 'Remove condition',
      width: 28,
      handler: function () { me.removeCondition(row); }
    });

    row.cmp = Ext.widget('container', {
      layout: { type: 'hbox', align: 'stretch' },
      margin: '0 0 6 0',
      items: [row.attrCombo, row.opCombo, row.valueCt, removeBtn]
    });

    row.attrCombo.getStore().loadData(me.attributes);

    row.attrCombo.on('change', function (combo, newVal) { me.onAttrChange(row, newVal); });
    row.opCombo.on('change', function (combo, newVal) { me.onOpChange(row, newVal); });

    row.getData = function () {
      return {
        attribute: row.attrCombo.getValue() || '',
        operator: row.opCombo.getValue() || '',
        value: me.readField(row.valueField, row.isValueDate),
        value2: me.readField(row.valueField2, row.isValue2Date),
        timeUnit: row.timeUnitField ? row.timeUnitField.getValue() : 'DAY'
      };
    };

    me.conditionRows.push(row);
    me.lookupReference('conditionsCt').add(row.cmp);
    me.refreshConditionsHint();

    return row;
  },

  attrTypeFor: function (name) {
    var a = this.attrMap[name];
    return a ? a.type : 'string';
  },

  onAttrChange: function (row, name) {
    var me = this;
    var SQ = DocumentumSearch.lib.SearchQuery;
    var ops = SQ.operatorsForType(me.attrTypeFor(name));

    row.attrName = name || '';
    row.operator = ops[0];

    row.opCombo.getStore().loadData(Ext.Array.map(ops, function (op) {
      return { value: op, label: SQ.OPERATOR_LABELS[op] || op };
    }));
    row.opCombo.enable();
    row.opCombo.setValue(ops[0]);
    me.buildValueFields(row);
  },

  onOpChange: function (row, operator) {
    row.operator = operator;
    this.buildValueFields(row);
  },

  buildValueFields: function (row) {
    var me = this;
    var SQ = DocumentumSearch.lib.SearchQuery;
    var operator = row.operator;
    var type = me.attrTypeFor(row.attrName);
    var date = type === 'datetime';
    var valueCt = row.valueCt;

    valueCt.removeAll(true);

    row.valueField = null;
    row.valueField2 = null;
    row.timeUnitField = null;
    row.isValueDate = false;
    row.isValue2Date = false;

    if (operator === SQ.RELATIVE_OPERATOR) {
      row.valueField = valueCt.add({ xtype: 'numberfield', flex: 1, minValue: 1, emptyText: 'N', hideLabel: true, margin: '0 4 0 0' });
      row.timeUnitField = valueCt.add({ xtype: 'combobox', flex: 1, queryMode: 'local', store: me.timeUnitStore, displayField: 'label', valueField: 'value', value: 'DAY', editable: false, hideLabel: true });
      return;
    }

    if (operator === 'IS_NULL' || operator === 'IS_NOT_NULL') {
      return;
    }

    if (operator === 'BETWEEN') {
      if (date) {
        row.valueField = valueCt.add(me.dateFieldCfg('from'));
        valueCt.add({ xtype: 'component', html: 'and', margin: '4 4 0 4' });
        row.valueField2 = valueCt.add(me.dateFieldCfg('to'));
        row.isValueDate = true;
        row.isValue2Date = true;
      } else {
        row.valueField = valueCt.add({ xtype: 'textfield', flex: 1, emptyText: 'from', hideLabel: true, margin: '0 4 0 0' });
        valueCt.add({ xtype: 'component', html: 'and', margin: '4 4 0 4' });
        row.valueField2 = valueCt.add({ xtype: 'textfield', flex: 1, emptyText: 'to', hideLabel: true });
      }
      return;
    }

    if (type === 'boolean' && operator === 'EQUAL') {
      row.valueField = valueCt.add({ xtype: 'combobox', flex: 1, queryMode: 'local', store: me.boolStore, displayField: 'label', valueField: 'value', editable: false, emptyText: 'Select…', hideLabel: true });
      return;
    }

    if (date) {
      row.valueField = valueCt.add(me.dateFieldCfg('value'));
      row.isValueDate = true;
      return;
    }

    var placeholder = (operator === 'IN' || operator === 'NOT_IN') ? 'value1, value2, …' : 'value';
    row.valueField = valueCt.add({ xtype: 'textfield', flex: 1, emptyText: placeholder, hideLabel: true });
  },

  dateFieldCfg: function (emptyText) {
    return {
      xtype: 'datefield',
      flex: 1,
      format: 'Y-m-d',
      submitFormat: 'Y-m-d',
      emptyText: emptyText || 'YYYY-MM-DD',
      hideLabel: true,
      margin: '0 4 0 0'
    };
  },

  readField: function (field, isDate) {
    if (!field) return '';
    var v = field.getValue();
    if (v == null || v === '') return '';
    if (isDate && Ext.isDate(v)) return Ext.Date.format(v, 'Y-m-d');
    return String(v);
  },

  removeCondition: function (row) {
    var me = this;
    Ext.Array.remove(me.conditionRows, row);
    row.cmp.destroy();
    me.refreshConditionsHint();
  },

  clearConditions: function () {
    var me = this;
    Ext.Array.each(me.conditionRows, function (row) { row.cmp.destroy(); });
    me.conditionRows = [];
    me.refreshConditionsHint();
  },

  refreshConditionsHint: function () {
    var me = this;
    if (me.conditionRows.length === 0 && me.getSelectedType()) {
      me.lookupReference('conditionsHint').update('No conditions yet — add one below, or use the full-text keyword box.');
    } else {
      me.lookupReference('conditionsHint').update('');
    }
  },

  conditionsEnabled: function () {
    var cb = this.lookupReference('conditionsToggle');
    return !!(cb && cb.getValue());
  },

  onConditionsToggle: function (cb, checked) {
    var fs = this.lookupReference('conditionsFieldset');
    if (fs) fs.setVisible(!!checked);
  },

  // --- search ---

  getSelectedType: function () {
    return this.lookupReference('typeCombo').getValue() || '';
  },

  valueNeedsInput: function (op) {
    return op && op !== 'IS_NULL' && op !== 'IS_NOT_NULL';
  },

  validate: function () {
    var me = this;
    var type = me.getSelectedType();
    if (!type) return 'Select an object type.';

    var fulltext = String(me.lookupReference('fulltext').getValue() || '').trim();
    var useConditions = me.conditionsEnabled();

    if (!fulltext && !(useConditions && me.conditionRows.length > 0)) {
      return 'Enter a full-text keyword or add at least one condition.';
    }

    if (useConditions) {
      for (var i = 0; i < me.conditionRows.length; i++) {
        var data = me.conditionRows[i].getData();
        if (!data.attribute) return 'Every condition needs an attribute.';
        if (!data.operator) return 'Every condition needs an operator.';

        var attr = me.attrMap[data.attribute];
        if (data.operator === 'BETWEEN') {
          if (!data.value || !data.value2) return 'BETWEEN needs both a "from" and a "to" value.';
          var isDate = attr && attr.type === 'datetime';
          var ok;
          if (isDate || (attr && attr.type === 'string')) {
            ok = data.value <= data.value2;
          } else {
            ok = Number(data.value) <= Number(data.value2);
          }
          if (!ok) return '"from" must be before or equal to "to".';
        } else if (me.valueNeedsInput(data.operator) && !String(data.value).trim()) {
          return 'Condition on "' + data.attribute + '" needs a value.';
        }
      }
    }
    return null;
  },

  onSearch: function () {
    var me = this;
    var err = me.validate();
    if (err) {
      me.lookupReference('validationMsg').update('<span class="search-error">' + Ext.htmlEncode(err) + '</span>');
      me.lookupReference('validationMsg').show();
      return;
    }
    me.lookupReference('validationMsg').hide();
    me.runSearch(1);
  },

  runSearch: function (page) {
    var me = this;
    var SQ = DocumentumSearch.lib.SearchQuery;

    me.setLoading(true);

    var type = me.getSelectedType();
    var fulltext = me.lookupReference('fulltext').getValue();
    var conjunction = me.lookupReference('conjunction').getValue() || 'AND';
    var pageSize = me.lookupReference('pageSize').getValue();

    var conditions = [];
    if (me.conditionsEnabled()) {
      Ext.Array.each(me.conditionRows, function (row) {
        var data = row.getData();
        var attr = me.attrMap[data.attribute];
        if (attr && attr.type === 'datetime') {
          if (data.operator === 'BETWEEN') {
            data.value = me.toIsoDate(data.value);
            data.value2 = me.toIsoDate(data.value2);
          } else if (me.valueNeedsInput(data.operator)) {
            data.value = me.toIsoDate(data.value);
          }
        }
        conditions.push(data);
      });
    }

    var body = SQ.buildSearchQuery({
      type: type,
      fulltext: fulltext,
      conditions: conditions,
      conjunction: conjunction,
      attributes: me.attrMap
    });

    me.lastQuery = body;

    DocumentumSearch.lib.Api.search(body, {
      'items-per-page': pageSize,
      page: page,
      inline: 'true',
      'include-total': 'true'
    }).then(function (feed) {
      me.onResults(feed, page);
    }, function (err) {
      me.onError(err);
    });
  },

  toIsoDate: function (dateStr) {
    if (!dateStr) return '';
    var d = new Date(dateStr + 'T00:00:00');
    if (isNaN(d.getTime())) return dateStr;
    var offset = -d.getTimezoneOffset();
    var sign = offset >= 0 ? '+' : '-';
    var abs = Math.abs(offset);
    var hh = String(Math.floor(abs / 60)); if (hh.length < 2) hh = '0' + hh;
    var mm = String(abs % 60); if (mm.length < 2) mm = '0' + mm;
    return dateStr + 'T00:00:00.000' + sign + hh + ':' + mm;
  },

  onResults: function (feed, page) {
    var me = this;
    me.setLoading(false);

    var entries = DocumentumSearch.lib.Dctm.getEntries(feed);
    var links = (feed && feed.links) || [];
    var linkHasPrev = false;
    var linkHasNext = false;
    Ext.Array.each(links, function (l) {
      if (l.rel === 'previous' || l.rel === 'prev') linkHasPrev = true;
      if (l.rel === 'next') linkHasNext = true;
    });

    me.currentPage = (feed && feed.page) || page;
    me.total = feed && feed.total;

    var effectivePage = Number(me.currentPage) || 1;
    var pageSize = Number(me.lookupReference('pageSize').getValue()) || 10;

    // Trust link-based flags when present, otherwise derive from page/total
    // so the prev button doesn't stay stuck disabled after pressing Next.
    if (linkHasPrev) {
      me.hasPrev = true;
    } else {
      me.hasPrev = effectivePage > 1;
    }
    if (linkHasNext) {
      me.hasNext = true;
    } else if (typeof me.total === 'number' && me.total >= 0) {
      me.hasNext = (effectivePage * pageSize) < me.total;
    } else {
      me.hasNext = false;
    }

    me.lookupReference('prevBtn').setDisabled(!me.hasPrev);
    me.lookupReference('nextBtn').setDisabled(!me.hasNext);
    me.lookupReference('pageText').setText('Page ' + me.currentPage + ((typeof me.total === 'number' && me.total > 0) ? ' · ' + me.total + ' total' : ''));

    var records = [];
    Ext.Array.each(entries, function (entry) {
      var p = DocumentumSearch.lib.Dctm.getProperties(entry);
      var summary = p.summary;
      if (!summary && entry.content && entry.content.summary) summary = entry.content.summary;
      if (!summary && entry.summary) summary = entry.summary;
      records.push({
        r_object_id: p.r_object_id,
        object_name: p.object_name,
        r_object_type: p.r_object_type,
        r_modify_date: p.r_modify_date,
        r_content_size: p.r_content_size,
        summary: summary || '',
        terms: entry.terms || []
      });
    });

    me.lookupReference('resultsGrid').getStore().loadData(records);

    if (records.length === 0) {
      me.showMessage('No results found.');
    } else {
      me.showGrid();
    }
  },

  onError: function (err) {
    var me = this;
    me.setLoading(false);

    me.lookupReference('prevBtn').setDisabled(true);
    me.lookupReference('nextBtn').setDisabled(true);
    me.lookupReference('pageText').setText('');

    var code = err.detail && err.detail.code;
    var details = err.detail && err.detail.details;

    var html = '<div class="search-error" style="font-weight:bold;margin-bottom:6px;">' +
      (code ? '<code>' + Ext.htmlEncode(String(code)) + '</code> ' : '') +
      'Search failed</div>' +
      '<div>' + Ext.htmlEncode(err.message || 'Unknown error') + '</div>' +
      (details ? '<div style="margin-top:6px;color:#666;">' + Ext.htmlEncode(String(details)) + '</div>' : '');

    me.showMessage(html);
  },

  setLoading: function (loading) {
    var me = this;
    me.loading = loading;
    var btn = me.lookupReference('searchBtn');
    if (btn) btn.setText(loading ? 'Searching…' : 'Search');
    if (loading) me.showMessage('Searching…');
  },

  showMessage: function (html) {
    var me = this;
    me.lookupReference('messageCard').update(html);
    me.lookupReference('resultsPanel').setActiveItem(0);
  },

  showGrid: function () {
    this.lookupReference('resultsPanel').setActiveItem(1);
  },

  clearResults: function () {
    var me = this;
    me.lookupReference('resultsGrid').getStore().removeAll();
    me.lookupReference('prevBtn').setDisabled(true);
    me.lookupReference('nextBtn').setDisabled(true);
    me.lookupReference('pageText').setText('');
    me.currentPage = 0;
    me.total = null;
    me.hasPrev = false;
    me.hasNext = false;
    me.showMessage('Choose a type and add a condition or keyword, then run a search.');
  },

  hideValidation: function () {
    this.lookupReference('validationMsg').hide();
  },

  onPrev: function () {
    this.runSearch((this.currentPage || 1) - 1);
  },

  onNext: function () {
    this.runSearch((this.currentPage || 1) + 1);
  },

  onToggleJson: function () {
    var me = this;
    if (!me.lastQuery) return;
    var pre = me.lookupReference('jsonPre');
    var btn = me.lookupReference('jsonToggle');
    if (pre.isHidden()) {
      pre.setValue(JSON.stringify(me.lastQuery, null, 2));
      pre.show();
      btn.setText('Hide request JSON');
    } else {
      pre.hide();
      btn.setText('Show request JSON');
    }
  },

  onReset: function () {
    var me = this;
    me.lookupReference('typeCombo').clearValue();
    me.lookupReference('fulltext').setValue('');
    me.lookupReference('conjunction').setValue('AND');
    var toggle = me.lookupReference('conditionsToggle');
    if (toggle) toggle.setValue(false);
    var fs = me.lookupReference('conditionsFieldset');
    if (fs) fs.hide();
    me.lookupReference('typesError').update('');
    me.setAttributesHint('');
    me.clearConditions();
    me.attributes = [];
    me.attrMap = {};
    me.clearResults();
    me.hideValidation();
    me.lastQuery = null;
    me.lookupReference('jsonPre').hide();
    me.lookupReference('jsonToggle').setText('Show request JSON');
  }
});
