$(document).ready(function () {
	radiant.call('tower_defense:get_service', 'game')
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
      
      self.radiantTrace = new RadiantTrace();
      self._playerTraces = {};
      self.set('players', {});

		$('#resourceDisplay')
			.draggable();
	},

	willDestroyElement: function () {
		var self = this;
		this._super();

      self.radiantTrace.destroy();
      radiant.each(self._playerTraces, function(id, trace) {
         trace.destroy();
      })
      self._playerTraces = null;
	},

	_onModelPlayersChanged: function () {
		var self = this;

      radiant.each(self.get('model.players'), function(id, player) {
         if (self._playerTraces[id]) {
            self._playerTraces[id].destroy();
         }
         self._playerTraces[id] = self.radiantTrace.traceUri(player, {})
            .progress(function (data) {
               if (self.isDestroying || self.isDestroyed) {
                  return;
               }
               Ember.set(self.get('players'), id, data);
               self.notifyPropertyChange('players');
            });
      });
	}.observes('model.players'),

	_onPlayersChanged: function () {
		var self = this;

		self.set('player_array', radiant.map_to_array(self.get('players')))

	}.observes('players'),

});
