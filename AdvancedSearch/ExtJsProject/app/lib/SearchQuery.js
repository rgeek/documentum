Ext.ns('DocumentumSearch.lib');

// Pure query builder: converts Advanced Search UI state into the JSON request
// body accepted by the Documentum REST search endpoint (POST .../search).
// Ported 1:1 from the React implementation.
DocumentumSearch.lib.SearchQuery = {
  DEFAULT_COLUMNS: [
    'r_object_id',
    'object_name',
    'r_object_type',
    'r_modify_date',
    'r_content_size',
    'summary'
  ],

  RELATIVE_OPERATOR: 'RELATIVE',

  TIME_UNITS: ['DAY', 'WEEK', 'MONTH', 'YEAR'],

  OPERATORS: {
    string: [
      'EQUAL', 'NOT_EQUAL', 'CONTAINS', 'DOES_NOT_CONTAIN',
      'BEGINS_WITH', 'ENDS_WITH', 'IN', 'NOT_IN', 'IS_NULL', 'IS_NOT_NULL'
    ],
    number: [
      'EQUAL', 'NOT_EQUAL', 'GREATER_THAN', 'GREATER_EQUAL', 'LESS_THAN',
      'LESS_EQUAL', 'BETWEEN', 'IN', 'NOT_IN', 'IS_NULL', 'IS_NOT_NULL'
    ],
    datetime: [
      'EQUAL', 'NOT_EQUAL', 'GREATER_THAN', 'GREATER_EQUAL', 'LESS_THAN',
      'LESS_EQUAL', 'BETWEEN', 'IS_NULL', 'IS_NOT_NULL', 'RELATIVE'
    ],
    boolean: ['EQUAL', 'IS_NULL', 'IS_NOT_NULL']
  },

  OPERATOR_LABELS: {
    EQUAL: 'equals',
    NOT_EQUAL: 'not equal',
    CONTAINS: 'contains',
    DOES_NOT_CONTAIN: 'does not contain',
    BEGINS_WITH: 'begins with',
    ENDS_WITH: 'ends with',
    IN: 'is one of',
    NOT_IN: 'is not one of',
    GREATER_THAN: 'greater than',
    GREATER_EQUAL: 'greater than or equal',
    LESS_THAN: 'less than',
    LESS_EQUAL: 'less than or equal',
    BETWEEN: 'between',
    IS_NULL: 'is empty',
    IS_NOT_NULL: 'is not empty',
    RELATIVE: 'within the last'
  },

  operatorsForType: function (type) {
    switch (type) {
      case 'boolean': return this.OPERATORS.boolean;
      case 'datetime': return this.OPERATORS.datetime;
      case 'integer':
      case 'float':
      case 'double': return this.OPERATORS.number;
      default: return this.OPERATORS.string;
    }
  },

  splitList: function (value) {
    if (Ext.isArray(value)) {
      return Ext.Array.map(value, function (v) { return String(v).trim(); })
        .filter(function (v) { return !!v; });
    }
    return String(value || '').split(',')
      .map(function (v) { return v.trim(); })
      .filter(function (v) { return !!v; });
  },

  buildExpression: function (condition, attr) {
    attr = attr || {};
    var name = condition.attribute;
    var operator = condition.operator;
    var value = condition.value != null ? condition.value : '';
    var value2 = condition.value2 != null ? condition.value2 : '';
    var timeUnit = condition.timeUnit || 'DAY';
    var repeating = !!attr.repeating;

    switch (operator) {
      case 'IN':
      case 'NOT_IN':
        return {
          'expression-type': 'property-list',
          name: name,
          operator: operator,
          values: this.splitList(value),
          repeating: repeating
        };

      case 'BETWEEN':
        return {
          'expression-type': 'property-range',
          name: name,
          operator: 'BETWEEN',
          from: value,
          to: value2,
          repeating: repeating
        };

      case 'RELATIVE':
        return {
          'expression-type': 'relative-date',
          name: name,
          operator: 'GREATER_THAN',
          value: -Math.abs(Number(value) || 0),
          'time-unit': timeUnit,
          repeating: repeating
        };

      case 'IS_NULL':
      case 'IS_NOT_NULL':
        return {
          'expression-type': 'property',
          name: name,
          operator: operator,
          'case-sensitive': false,
          'exact-match': false,
          repeating: repeating
        };

      default:
        return {
          'expression-type': 'property',
          name: name,
          operator: operator,
          value: String(value),
          'case-sensitive': false,
          'exact-match': false,
          repeating: repeating
        };
    }
  },

  buildSearchQuery: function (state) {
    state = state || {};
    var type = state.type;
    var columns = state.columns || this.DEFAULT_COLUMNS;
    var fulltext = state.fulltext || '';
    var conditions = state.conditions || [];
    var conjunction = state.conjunction || 'AND';
    var attributes = state.attributes || {};

    var expressions = [];

    if (fulltext && String(fulltext).trim()) {
      expressions.push({ 'expression-type': 'fulltext', value: String(fulltext).trim() });
    }

    for (var i = 0; i < conditions.length; i++) {
      var condition = conditions[i];
      expressions.push(this.buildExpression(condition, attributes[condition.attribute] || {}));
    }

    var body = {
      types: [type],
      columns: (columns && columns.length) ? columns : this.DEFAULT_COLUMNS,
      sorts: [{ property: 'r_modify_date', ascending: false }]
    };

    if (expressions.length) {
      body['expression-set'] = {
        'expression-type': 'expression-set',
        operator: conjunction === 'OR' ? 'OR' : 'AND',
        expressions: expressions
      };
    }

    return body;
  }
};
