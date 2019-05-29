$(document).ready(function () {
   App.waitForGameLoad().then(() => {
      radiant.call('tower_defense:get_service', 'game')
         .done(function (e) {
            App.gameView.addView(App.TowerDefenseResourceDisplay, { uri: e.result })
         })
         .fail(function (e) {
            console.log('error getting game service')
            console.dir(e)
         });
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
      
      self.donateAmount = 0;

      self.radiantTrace = new RadiantTrace();
      self.set('players', {});

		self.$('#resourceDisplay')
         .draggable();
      
      self.$().on('click', `.player .donate`, function(e) {
         radiant.call('tower_defense:donate_gold_command', self.donateAmount)
            .done(function(result) {
               // only play the sound if we successfully donated
               radiant.call('radiant:play_sound', {
                  track: 'tower_defense:sounds:coins',
                  volume: 40
               });
            });
         return false;
      });
	},

	willDestroyElement: function () {
		var self = this;

      self.radiantTrace.destroy();
      self.$('.donate').off('click');

		self._super();
	},

	_onModelPlayersChanged: function () {
		var self = this;

      radiant.each(self.get('model.players'), function(id, player) {
         self.radiantTrace.traceUri(player, {})
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

      var playerArr = radiant.map_to_array(self.get('players') || {});
      playerArr.forEach(player => {
         var steamName = App.presenceClient.getSteamName(player.player_id);
         Ember.set(player, 'playerName', steamName && steamName != '' ? steamName : player.player_id);
         var color = App.presenceClient.getPlayerColor(player.player_id)
         Ember.set(player, 'colorStyle', `color: rgba(${color.x}, ${color.y}, ${color.z}, 1)`);
         if (App.stonehearthClient.getPlayerId() == player.player_id) {
            self.donateAmount = Math.ceil(player.gold / 5);
            Ember.set(player, 'donate', i18n.t('tower_defense:ui.game.resourceDisplay.donate', {amount: self.donateAmount}));
         }
      });

		self.set('player_array', playerArr);
	}.observes('players'),

});
