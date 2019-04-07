App.StonehearthStartMenuView.reopen({
   init: function() {
      var self = this;

      self.menuActions.td_create_tower = function(data) {
         // try to create and place the specified tower
         if (data && data.uri) {
            radiant.call('tower_defense:create_and_place_entity', data.uri)
            .fail(function(response) {
               if (response.message) {
                  alert(i18n.t(response.message, response.i18n_data));
               }
            });
         }
      };
      
      self.menuActions.td_give_gold = function(data) {
         // cheat give yourself gold
         if (data && data.gold_amount) {
            radiant.call('tower_defense:give_gold_cheat_command', data.gold_amount);
         }
      };

      self._super();
   }
});
