
Ext.override(DocumentumSearchFilter.view.Viewport, {
	processConfig: function(config) {
		var store = Ext.create('Ext.data.TreeStore', {
			root: {
				text: 'Root',
				expanded: true,
				children: [
					{ text: 'Child 1', leaf: true },
					{
						text: 'Child 2', expanded: true, children: [
							{ text: 'Grand Child', leaf: true },

						]
					},
					{ text: 'Child 3', leaf: true }
				]
			},
			"proxy": {
				"type": "memory",
				"reader": {
					"type": "json",
				}
			},
		});

		Ext.applyIf(config, {
			"height": 200,
			"displayField": "name",
			"useArrows": "true",
			"store": store
		});
	},



});

Ext.define('DocumentumSearchFilter.view.Viewport.designer.AdvancedSearchFilter', {
	extend: 'xcp.designer.Component',
	constructor: function(cmp) {
		DocumentumSearchFilter.view.Viewport.designer.AdvancedSearchFilter.superclass.constructor.call(this, cmp);

		this.propertyConfig = {
			"tabs": [{
				"name": "general",
				"sections": [{
					"name": "basic",
					"label": "Basics",
					"properties": [{ "name": "fieldLabel" }, { "name": "debug" }]
				},
				{
					"name": "cabinetFilter",
					"label": "Cabinet Filter",
					"properties": [{ "name": "cabinetFilter" }]
				}]
			},
			{
				"name": "style",
				"sections": [{
					"name": "layout",
					"label": "Layout",
					"properties": [{ "name": "size", "editor": "genericWidth", "reCreateCmpOnChange": true }]
				}]
			},
			{
				"name": "behavior",
				"label": "Behavior",
				"sections": [{
					"name": "behavior",
					"properties": [
						{ "name": "hidden", "editor": "com.emc.xcp.uitemplate.ui.property.section.special.expr.BooleanExpressionPropertyEditor" },
						{ "name": "readOnly", "editor": "com.emc.xcp.uitemplate.ui.property.section.special.expr.BooleanExpressionPropertyEditor" }
					]
				}]
			}]
		};
		//this.cmp.setValue(this.addCanvasDisplayText(this.cmp.getValue()));

	},

	updateComponent: function(propertiesJSONObject) {
		console.log(propertiesJSONObject);
		console.log(this.cmp.getTitle());
		if (propertiesJSONObject.name === 'fieldLabel') {
			this.cmp.setFieldLabel(Ext.htmlEncode(propertiesJSONObject.value));
			this.cmp.setTitle(Ext.htmlEncode(propertiesJSONObject.value));
			this.cmp.updateTitle();
			this.cmp.update();
		}
		console.log(this.cmp.getTitle());
	},

});

xcp.designer.ComponentMgr.registerType("tro_adv_search_filter_view", DocumentumSearchFilter.view.Viewport.designer.AdvancedSearchFilter);

