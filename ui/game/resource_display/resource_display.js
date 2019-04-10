$(document).ready(function () {
	radiant.call('tower_defense:get_service','game')
		.done(function (e) {
			App.gameView.addView(App.TowerDefenseResourceDisplay, { uri: e.result })
		})
		.fail(function (e) {
			console.log('error getting game service')
			console.dir(e)
		});
});

App.TowerDefenseResourceDisplay = App.View.extend({
	templateName: 'resourceDisplay',
	uriProperty: 'model',
	closeOnEsc: false,

	components: {
		'players': { '*': {} },
		'common_player': {},
		'wave_controller': {}
	},

	didInsertElement: function () {
		var self = this;

		$('#resourceDisplay')
			.draggable()

	},

	willDestroyElement: function () {
		this._super();
	},

	_onPlayersChanged: function () {
		var self = this;
		self.set('player_array', radiant.map_to_array(self.get('model.players')))
	}.observes('model.players'),



/*/old pet stuff below here
	_updateNameAndDescription: function () {
		var alias = this.get('model.uri');

		var description = this.get('model.stonehearth:unit_info.description');
		var display_name = this.get('model.stonehearth:unit_info.display_name');
		if (alias) {
			var catalogData = App.catalog.getCatalogData(alias);
			if (!catalogData) {
				console.log("no catalog data found for " + alias);
			} else {
				if (!display_name) {
					display_name = catalogData.display_name;
				}

				if (!description) {
					description = catalogData.description;
				}
			}
		}
		if (display_name) {
			var unit_name = i18n.t(display_name, { self: this.get('model') });
			this.set('unit_name', unit_name);
		}
		this.set('description', description);
	}.observes('model.uri'),

	_updateAttributes: function () {
		var health = this.get('model.stonehearth:expendable_resources.resources.health');
		var maxHealth = this.get('model.stonehearth:attributes.attributes.max_health.user_visible_value');
		var healthPercent = Math.floor(health * 100 / maxHealth);
		this.set('model.health_bar_style', 'width: ' + healthPercent + '%');
	}.observes('model.stonehearth:attributes')//*/
});
