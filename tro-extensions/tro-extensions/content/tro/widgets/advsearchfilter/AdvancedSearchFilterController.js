/**
 * Controller for the Advanced Search panel. Owns the Card 1 criteria chips,
 * drives the remote value-lookup combo / tag field, and builds/restores the
 * readable search-criteria JSON contract, persisting it to sessionStorage on
 * every user edit (ADD, chip removal, and phrase/wildcard typing).
 */
Ext.define('AdvSearchFilter.view.search.AdvancedSearchFilterController', {
  extend: 'Ext.app.ViewController',
  alias: 'controller.dctm-advsearchfilter',

  init: function () {
    var me = this;

    me.chips = [];
    me.usedKeys = {};
    me.nextChipId = 1;

    // Child component references are not reliably resolvable during init, so
    // wire everything up once the panel has been rendered. The attr/operator
    // combos get their stores via ViewModel bindings, so no setStore() is
    // needed here.
    me.getView().on('afterrender', me.onViewReady, me, { single: true });
  },

  onViewReady: function () {
    var me = this;

    var lookupStore = me.getStore('lookupValues');
    lookupStore.on('beforeload', me.onLookupBeforeLoad, me);
    lookupStore.on('load', me.onLookupLoad, me);

    // Fetch the attribute / operator / type config from the backend, then finish
    // initializing the panel (populate the attribute dropdown and restore any
    // previously persisted search).
    AdvSearchFilter.config.AttributeConfig.load(function (err) {
      if (err) {
        me.lookupReference('valueStatus').update(
          '<span class="search-error">' + Ext.htmlEncode(String(err.message || err)) + '</span>'
        );
        me.lookupReference('attrCombo').disable();
        return;
      }

      me.refreshAttrStore();

      // Pre-populate from sessionStorage if a previous search exists.
      var raw = null;
      try { raw = sessionStorage.getItem('advSearchFilterJson'); } catch (e) { raw = null; }

      if (raw) {
        var obj = null;
        try { obj = Ext.JSON.decode(raw); } catch (e2) { obj = null; }
        if (obj) {
          me.setSearchCriteria(obj);
          return;
        }
      }
    });
  },

  // --- Card 1: attribute / operator / value selection ---

  currentAttr: function () {
    return AdvSearchFilter.config.AttributeConfig.byKey(this.lookupReference('attrCombo').getValue());
  },

  onAttrChange: function (combo, key) {
    var me = this;
    var cfg = AdvSearchFilter.config.AttributeConfig.byKey(key);

    me.lookupReference('valueCombo').clearValue();
    me.lookupReference('valueTag').clearValue();
    me.lookupReference('startDateField').setValue(null);
    me.lookupReference('endDateField').setValue(null);
    me.lookupReference('valueStatus').update('');

    me.populateOperators(cfg);
    me.refreshValueControl();

    if (!cfg) {
      me.refreshAddState();
      return;
    }

    if (cfg.type === 'string') {
      me.getStore('lookupValues').load({ params: { attribute: key } });
    }

    me.refreshAddState();
  },

  populateOperators: function (cfg) {
    var me = this;
    var operatorCombo = me.lookupReference('operatorCombo');
    var data = (cfg && Ext.isArray(cfg.operators)) ? cfg.operators : [];

    me.getStore('operatorStore').loadData(data);

    if (data.length > 0) {
      operatorCombo.enable();
      operatorCombo.setValue(data[0].value);
    } else {
      operatorCombo.disable();
      operatorCombo.clearValue();
    }
  },

  onOperatorChange: function () {
    this.refreshValueControl();
    this.refreshAddState();
  },

  refreshValueControl: function () {
    var me = this;
    var cfg = me.currentAttr();
    var operator = me.lookupReference('operatorCombo').getValue();

    var showCombo = false, showTag = false, showDate = false;

    if (cfg) {
      if (cfg.type === 'date') {
        showDate = true;
      } else if (operator === 'in') {
        showTag = true;
      } else {
        showCombo = true;
      }
    }

    me.lookupReference('valueCombo').setVisible(showCombo);
    me.lookupReference('valueTag').setVisible(showTag);
    me.lookupReference('dateRangeCt').setVisible(showDate);
  },

  onValueChange: function () {
    this.refreshAddState();
  },

  onDateChange: function () {
    this.refreshAddState();
  },

  onLookupBeforeLoad: function () {
    var me = this;
    me.lookupReference('valueCombo').disable();
    me.lookupReference('valueTag').disable();
    me.lookupReference('valueCombo').setEmptyText('Loading values…');
    me.lookupReference('valueTag').setEmptyText('Loading values…');
    me.lookupReference('valueStatus').update('Loading values…');
  },

  onLookupLoad: function (store, records, successful, operation) {
    var me = this;
    var valueCombo = me.lookupReference('valueCombo');
    var valueTag = me.lookupReference('valueTag');

    // If the attribute was cleared while the request was in flight, ignore the
    // stale response and keep the value controls disabled.
    if (!me.lookupReference('attrCombo').getValue()) {
      valueCombo.setDisabled(true);
      valueTag.setDisabled(true);
      me.lookupReference('valueStatus').update('');
      return;
    }

    valueCombo.enable();
    valueTag.enable();

    if (!successful) {
      var err = (operation && operation.getError && operation.getError()) || 'Failed to load values';
      valueCombo.setEmptyText('Failed to load values');
      valueTag.setEmptyText('Failed to load values');
      me.lookupReference('valueStatus').update(
        '<span class="search-error">' + Ext.htmlEncode(String(err)) + '</span>'
      );
      return;
    }

    me.lookupReference('valueStatus').update('');

    if (records.length === 0) {
      valueCombo.setEmptyText('No values available');
      valueTag.setEmptyText('No values available');
    } else {
      valueCombo.setEmptyText('Select a value…');
      valueTag.setEmptyText('Select values…');
    }
  },

  onAdd: function () {
    var me = this;
    var cfg = me.currentAttr();
    var operator = me.lookupReference('operatorCombo').getValue();

    if (!cfg || !operator) return;

    var value, valueLabel;

    if (cfg.type === 'date') {
      var start = me.lookupReference('startDateField').getValue();
      var end = me.lookupReference('endDateField').getValue();
      if (!start || !end) return;

      var startStr = Ext.Date.format(start, 'd-M-Y');
      var endStr = Ext.Date.format(end, 'd-M-Y');
      value = [startStr, endStr];
      valueLabel = startStr + ' and ' + endStr;
    } else if (operator === 'in') {
      var tag = me.lookupReference('valueTag');
      value = tag.getValue();
      if (!Ext.isArray(value) || value.length === 0) return;
      valueLabel = me.joinSelectedLabels(tag, value);
    } else {
      var valueCombo = me.lookupReference('valueCombo');
      value = valueCombo.getValue();
      var rec = valueCombo.getSelectedRecord();
      if (value == null || value === '') return;
      valueLabel = rec ? rec.get('label') : value;
    }

    me.addChip(cfg, operator, value, valueLabel);
    me.resetAddRow();
    me.refreshAddState();
  },

  joinSelectedLabels: function (tag, values) {
    var store = tag.getStore();
    return Ext.Array.map(values, function (v) {
      var idx = store.findExact('value', v);
      if (idx >= 0) return store.getAt(idx).get('label');
      return v;
    }).join(', ');
  },

  addChip: function (cfg, operator, value, valueLabel) {
    var me = this;
    var id = me.nextChipId++;

    if (valueLabel == null || valueLabel === '') {
      valueLabel = me.formatValueLabel(operator, value);
    }

    var chip = {
      id: id,
      key: cfg.key,
      label: cfg.label,
      attribute: cfg.attribute,
      type: cfg.type,
      operator: operator,
      value: value,
      valueLabel: valueLabel
    };

    var operatorSymbol = operator === 'equals' ? '=' : (operator === 'in' ? 'IN' : 'Between');
    var chipHtml = Ext.htmlEncode(cfg.label + ' ' + operatorSymbol + ' ' + valueLabel) +
      ' <span class="adv-chip-remove" data-chip-id="' + id + '" title="Remove ' +
      Ext.htmlEncode(cfg.label) + '">&times;</span>';

    chip.cmp = Ext.widget('component', {
      cls: 'adv-chip',
      margin: '0 8 8 0',
      html: chipHtml,
      listeners: {
        click: {
          element: 'el',
          delegate: '.adv-chip-remove',
          fn: function (e) {
            var target = e.getTarget('.adv-chip-remove');
            if (!target) return;
            var chipId = target.getAttribute('data-chip-id');
            if (chipId) me.removeChip(Number(chipId));
          }
        }
      }
    });

    me.chips.push(chip);
    me.usedKeys[cfg.key] = true;

    me.lookupReference('chipsCt').add(chip.cmp);
    me.refreshAttrStore();
    me.refreshAddRow();
    me.syncSessionJson();
  },

  removeChip: function (id) {
    var me = this;

    for (var i = 0; i < me.chips.length; i++) {
      if (me.chips[i].id === id) {
        var chip = me.chips[i];
        chip.cmp.destroy();
        delete me.usedKeys[chip.key];
        Ext.Array.erase(me.chips, i, 1);
        break;
      }
    }

    me.refreshAttrStore();
    me.refreshAddRow();
    me.syncSessionJson();
  },

  formatValueLabel: function (operator, value) {
    if (operator === 'in' && Ext.isArray(value)) return value.join(', ');
    if (operator === 'between' && Ext.isArray(value)) return value[0] + ' and ' + value[1];
    return String(value);
  },

  refreshAttrStore: function () {
    var me = this;
    var data = [];

    Ext.Array.each(AdvSearchFilter.config.AttributeConfig.attributes, function (a) {
      if (!me.usedKeys[a.key]) {
        data.push({ key: a.key, label: a.label, attribute: a.attribute });
      }
    });

    me.getStore('attrStore').loadData(data);
  },

  refreshAddRow: function () {
    var me = this;
    var allUsed = me.usedKeysCount() >= AdvSearchFilter.config.AttributeConfig.attributes.length;

    if (allUsed) {
      me.lookupReference('attrCombo').disable();
      me.resetAddRow();
      me.lookupReference('addRowHint').update('All criteria added.');
    } else {
      me.lookupReference('attrCombo').enable();
      me.lookupReference('addRowHint').update('');
    }

    me.refreshAddState();
  },

  resetAddRow: function () {
    var me = this;

    me.lookupReference('attrCombo').clearValue();
    me.lookupReference('operatorCombo').clearValue();
    me.lookupReference('operatorCombo').disable();

    me.lookupReference('valueCombo').clearValue();
    me.lookupReference('valueCombo').setDisabled(true);
    me.lookupReference('valueCombo').setVisible(true);

    me.lookupReference('valueTag').clearValue();
    me.lookupReference('valueTag').setDisabled(true);
    me.lookupReference('valueTag').setVisible(false);

    me.lookupReference('startDateField').setValue(null);
    me.lookupReference('endDateField').setValue(null);
    me.lookupReference('dateRangeCt').setVisible(false);

    me.lookupReference('valueStatus').update('');
  },

  usedKeysCount: function () {
    var n = 0;
    for (var k in this.usedKeys) {
      if (Object.prototype.hasOwnProperty.call(this.usedKeys, k)) n++;
    }
    return n;
  },

  refreshAddState: function () {
    var me = this;
    var cfg = me.currentAttr();
    var operator = me.lookupReference('operatorCombo').getValue();
    var ready = false;

    if (cfg && operator) {
      if (cfg.type === 'date') {
        ready = !!me.lookupReference('startDateField').getValue() &&
                !!me.lookupReference('endDateField').getValue();
      } else if (operator === 'in') {
        var vals = me.lookupReference('valueTag').getValue();
        ready = Ext.isArray(vals) && vals.length > 0;
      } else {
        var v = me.lookupReference('valueCombo').getValue();
        ready = v != null && v !== '';
      }
    }

    me.lookupReference('addBtn').setDisabled(!ready);
  },

  // --- Card 2: exact phrase / wildcard ---

  onInputChange: function () {
    this.syncSessionJson();
  },

  // --- Contract / sessionStorage ---

  getSearchCriteria: function () {
    var me = this;
    var out = { searchType: 'advanced' };

    if (me.chips.length > 0) {
      out.matchAll = Ext.Array.map(me.chips, function (c) {
        return {
          field: c.label,
          attribute: c.attribute,
          operator: c.operator,
          value: c.value
        };
      });
    }

    var phrase = String(me.lookupReference('exactPhraseField').getValue() || '').trim();
    if (phrase) out.exactPhrase = phrase;

    out.createdAt = Ext.Date.format(new Date(), 'c');

    return out;
  },

  syncSessionJson: function () {
    var criteria = this.getSearchCriteria();
    var json = JSON.stringify(criteria, null, 2);
    try { sessionStorage.setItem('advSearchFilterJson', json); } catch (e) { /* ignore */ }

    // Keep the legacy "search" event alive for any xCP / container listener
    // now that the Search button has been removed.
    this.getView().fireEvent('search', criteria);
  },

  setSearchCriteria: function (obj) {
    var me = this;
    obj = obj || {};

    me.onClearAll();

    if (obj.exactPhrase) me.lookupReference('exactPhraseField').setValue(obj.exactPhrase);

    if (Ext.isArray(obj.matchAll)) {
      Ext.Array.each(obj.matchAll, function (item) {
        var cfg = AdvSearchFilter.config.AttributeConfig.byAttribute(item.attribute);
        if (!cfg) return;

        var operator = item.operator;
        var value = item.value;
        var valueLabel;

        if (operator === 'between') {
          if (!Ext.isArray(value) || value.length !== 2) return;
          valueLabel = value[0] + ' and ' + value[1];
        } else if (operator === 'in') {
          if (!Ext.isArray(value) || value.length === 0) return;
          valueLabel = value.join(', ');
        } else {
          operator = 'equals';
          if (value == null || value === '') return;
          valueLabel = String(value);
        }

        me.addChip(cfg, operator, value, valueLabel);
      });
    }

    me.syncSessionJson();
  },

  onClearAll: function () {
    var me = this;

    // Destroy chips and reset tracking state.
    Ext.Array.each(me.chips, function (chip) { chip.cmp.destroy(); });
    me.chips = [];
    me.usedKeys = {};

    me.lookupReference('exactPhraseField').setValue('');

    me.resetAddRow();

    try { sessionStorage.removeItem('advSearchFilterJson'); } catch (e) { /* ignore */ }

    me.refreshAttrStore();
    me.refreshAddRow();
  }
});
