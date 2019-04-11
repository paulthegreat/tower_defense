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
		'common_player': {}
	},

	didInsertElement: function () {
		var self = this;

		$('#resourceDisplay')
			.draggable();

		self.radiantTrace = new RadiantTrace();
		self.radiantTrace.traceUri(self.get('uri'), { 'players': { "*": {} }})
			.progress(function (data) {
				if (self.isDestroying || self.isDestroyed) {
					return;
				}
				self.set('players',data.players);
				self.notifyPropertyChange('players');
			});
	},

	willDestroyElement: function () {
		var self = this;

		self.radiantTrace.destroy();
		this._super();
	},

	_onPlayersChanged: function () {
		var self = this;

		self.set('player_array', radiant.map_to_array(self.get('players')))

	}.observes('players'),

});
