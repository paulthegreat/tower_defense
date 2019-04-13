App.StonehearthSelectGameStoryView.reopen({
   _doStartNow: function() {
      radiant.call('stonehearth:embark_client');
      App.navigate('game');
      radiant.call('radiant:reload_browser');
      self.destroy();
   },
   
   actions: {
      beginStory: function () {
         var self = this;
         radiant.call('radiant:play_sound', { 'track': 'stonehearth:sounds:ui:start_menu:embark' });
         self._options.starting_kingdom = self._selectedKingdomData.__self;
         self._options.starting_items = {
            [self._selectedKingdomData.starting_talisman]: 1
         };
         self._options.game_mode = self._selectedGameModeData.__self;
         self._options.biome_src = self._selectedBiomeData.__self;
         self._options.loadouts = self._selectedKingdomData.loadouts;

         self.send('continueSelection');
      },

      continueSelection: function() {
         var self = this;
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_click' });
         radiant.call_obj('stonehearth.game_creation', 'set_custom_game_info_command', {
               biome_name : self.get('selectedBiome').display_name,
               translated_biome_name : i18n.t(self.get('selectedBiome').display_name),
               biome_random_name : self.get('selectedBiomeRandomName'),
               translated_biome_random_name : i18n.t(self.get('selectedBiomeRandomName')),
               game_mode : self.get('selectedGameMode').display_name,
               translated_game_mode : i18n.t(self.get('selectedGameMode').display_name)
            });
         radiant.call_obj('stonehearth.game_creation', 'select_player_kingdom', self._options.starting_kingdom)
            .done(function(e) {
               // if you're the host, go ahead and do the other stuff
               if (self._isHostPlayer) {
                  radiant.call_obj('stonehearth.terrain', 'set_fow_command', false);
                  radiant.call_obj('stonehearth.game_creation', 'new_game_command', 0, 0, 0, self._options)
                     .done(function(e) {
                        radiant.call_obj('stonehearth.game_creation', 'generate_start_location_command', 0, 0, e.map_info)
                           .done(function(e) {
                              self._doStartNow();
                           });
                     });
               }
               else {
                  radiant.call('tower_defense:start_game_command')
                     .done(function(e) {
                        self._doStartNow();
                     });
               }
            })
            .fail(function(e) {
               console.error('selecting a kingdom failed:', e)
            });
      }
   }
});
