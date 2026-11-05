var token = "Basic " + btoa("dmadmin:dmadmin123");

Ext.define("rwd.widgets.CustomTreeView", {
	extend: 'Ext.tree.Panel',
	alias: 'widget.rwd_custom_tree_view',

	//renderTo: document.body,



	config: {
		debug: true, // set to 'true' when you want debug messages to show up in the JavaScript console

	},

	title: 'Custom Tree View',

	store: Ext.create("Ext.data.TreeStore", {
		folderSort: true,
		rootVisible: false,
		proxy: {
			type: "rest",
			autoLoad: true,
			noCache: false,
			username: "dmadmin",
			password: "dmadmin123",
			url: "https://3.140.76.175:8444/dctm-rest/repositories/ecm_dev_repo/cabinets",
			withCredentials: false,
			appendId: false,
			method: "GET",
			headers: {
				'Authorization': token

			},
			reader: {
				type: "json",
				rootProperty: "entries",
			},
		},
	}),
	useArrows: true,
	rootVisible: false,

	xcpeventconfig: [
		{
			event: "change",
			data: function(field, newValue, oldValue, options) {
				return newValue;
			}
		}],

	statics: {
		getSelectedNodeId: function(context, compId) {
			var comp = context.getComponent(compId);
			var selectedNodeId = "";
			if (!comp) {
				xcp.Logger.warn("Could not find the component with id : " + compId);
			} else {
				selectedNodeId = comp.getSelectedNodeId();
			}
			//console.log("Selected Sanitized Node:"+xcp.core.expr.BaseExpression.sanitizeObjectUri(selectedNodeId, context))
			//xcp.Logger.error("Selected Sanitized Node:"+xcp.core.expr.BaseExpression.sanitizeObjectUri(selectedNodeId, context));
			return xcp.core.expr.BaseExpression.sanitizeObjectUri(selectedNodeId, context);
		},


	},

	initComponent: function() {
		this.log('initComponent enter', arguments);
		rwd.widgets.CustomTreeView.superclass.initComponent.call(this);
		this.log('initComponent exit');
	},

	constructor: function(config) {
		this.processConfig(config);
		this.callParent(arguments);
		this.log('constructor enter', arguments);
		this.newObjectID = null;
		this.previousObjectId = null;
		this.selectedNodeId = null;

		try {
			xcp.widget.form.Form.encodeFieldLabel(config); // this fails when running outside xCP
		} catch (err) {
			this.log("we're not in Kansas anymore");
		}

		this.log('constructor exit', arguments);

	},

	columns: [
		{
			xtype: "treecolumn",
			text: "Cabinets",
			flex: 2,
			sortable: true,
			dataIndex: "title",
		},
	],

	listeners: {
		beforeitemexpand: function(node, index, item, eOpts) {
			var url = new String(node.get("id"));
			var pieces = url.split(/[\s/]+/);
			var objid = pieces[pieces.length - 1];
			if (objid.length == 16) {
				folders = this.GetFolders(objid);
				if (folders.entries !== undefined) {
					node.set("entries", folders.entries)
				} else {
					node.set("entries", [])
				}

			}
		},


		itemclick: function(dv, record, item, index, e) {
			this.newObjectID = record.get("id").slice(-16);
			if (this.newObjectID != this.previousObjectId) {
				this.selectedNodeId = this.newObjectID;
				this.fireEvent('change', this, this.newObjectID, this.previousObjectId);
			}

			this.previousObjectId = this.newObjectID;
		},

	},

	processConfig: function(config) {

	},

	setFilter: function(filterCondition) {
		this.cabinetFilter = filterCondition;

		var newStore = Ext.create("Ext.data.TreeStore", {
			folderSort: true,
			rootVisible: false,
			proxy: {
				type: "rest",
				autoLoad: true,
				noCache: false,
				url: "https://3.140.76.175:8444/dctm-rest/repositories/ecm_dev_repo/cabinets?filter=" + this.cabinetFilter,
				withCredentials: false,
				appendId: false,
				method: "GET",
				headers: {
					'Authorization': token

				},
				reader: {
					type: "json",
					rootProperty: "entries",
				},
			},
		});
		this.setStore(newStore);
		console.log("Store Updated");
		//this.update();

	},

	updateTitle: function() {
		this.setTitle(this.getFieldLabel());
		console.log("title updated");
		this.update();
	},


	getSelectedNodeId: function() {
		return this.selectedNodeId;
	},

	authenticateUser: function(user, password) {
		var token = user + ":" + password;
		var hash = btoa(token);
		return "Basic " + hash;
	},

	GetFolders: function(id) {

		var request = new XMLHttpRequest();
		request.open("GET", "https://3.140.76.175:8444/dctm-rest/repositories/ecm_dev_repo/folders/" + id + "/folders", false);
		request.setRequestHeader("Authorization", this.authenticateUser("dmadmin", "dmadmin123"));
		request.send();
		var response = request.responseText;
		var obj = JSON.parse(response);
		return obj;
	},

	isDesignMode: function() {
		return !xcp.navigationManager;
	},

	/** (custom)
	 * log messages to JavaScript console if debug==true
	 */
	log: function() {
		if (this.getDebug() == true) {
			var id;

			if (this.id)
				id = this.id;
			else
				id = this.alias[0];

			console.log(id + ':', arguments);
		}
	},

});