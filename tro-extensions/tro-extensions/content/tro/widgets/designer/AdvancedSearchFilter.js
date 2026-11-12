// ---- Runtime override (keep in the runtime JS, loaded after Viewport is defined) ----
Ext.define('DocumentumSearchFilter.override.Viewport', {
    override: 'DocumentumSearchFilter.view.Viewport',

    processConfig: function (config) {
        var store = Ext.create('Ext.data.TreeStore', {
            root: {
                text: 'Root',
                expanded: true,
                children: [
                    { text: 'Child 1', leaf: true },
                    { text: 'Child 2', expanded: true, children: [
                        { text: 'Grand Child', leaf: true }
                    ]},
                    { text: 'Child 3', leaf: true }
                ]
            },
            proxy: { type: 'memory', reader: { type: 'json' } }
        });

        Ext.applyIf(config, {
            height: 200,
            displayField: 'text',   // your nodes use "text", not "name"
            useArrows: true,        // boolean, not the string "true"
            store: store
        });
    }
});

// ---- Designer class (designer JS) ----
Ext.define('DocumentumSearchFilter.designer.AdvancedSearchFilter', {
    extend: 'xcp.designer.Component',

    constructor: function (cmp) {
        this.callParent(arguments);

        this.propertyConfig = {
            tabs: [{
                name: 'general',
                sections: [
                    { name: 'basic', label: 'Basics',
                      properties: [{ name: 'fieldLabel' }, { name: 'debug' }] },
                    { name: 'cabinetFilter', label: 'Cabinet Filter',
                      properties: [{ name: 'cabinetFilter' }] }
                ]
            }, {
                name: 'style',
                sections: [{
                    name: 'layout', label: 'Layout',
                    properties: [{ name: 'size', editor: 'genericWidth', reCreateCmpOnChange: true }]
                }]
            }, {
                name: 'behavior', label: 'Behavior',
                sections: [{
                    name: 'behavior',
                    properties: [
                        { name: 'hidden',   editor: 'com.emc.xcp.uitemplate.ui.property.section.special.expr.BooleanExpressionPropertyEditor' },
                        { name: 'readOnly', editor: 'com.emc.xcp.uitemplate.ui.property.section.special.expr.BooleanExpressionPropertyEditor' }
                    ]
                }]
            }]
        };
    },

    updateComponent: function (prop) {
        if (prop.name === 'fieldLabel') {
            var label = Ext.htmlEncode(prop.value);
            if (this.cmp.setFieldLabel) { this.cmp.setFieldLabel(label); }   // fields only
            if (this.cmp.setTitle)      { this.cmp.setTitle(label); }        // panels/trees
        }
    }
});

xcp.designer.ComponentMgr.registerType(
    'tro_adv_search_filter_view',
    DocumentumSearchFilter.designer.AdvancedSearchFilter
);