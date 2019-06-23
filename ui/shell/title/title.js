App.StonehearthTitleScreenView.reopen({
   didInsertElement: function() {
      var self = this;
      self._super();

      App.waitForGameLoad().then(() => {
         self._splashLoaded.then(() => {
            $.getJSON('/tower_defense/data/compatible_mods.json', function(data) {
               if (self.isDestroyed || self.isDestroying) {
                  return;
               }
               var compatibleMods = data && data.mods || {};

               radiant.call('radiant:get_all_mods')
                  .done(function(mods) {
                     if (self.isDestroyed || self.isDestroying) {
                        return;
                     }
                     
                     // check to see if there are any non-base mods enabled
                     // if there are, check to see if they're SH:TD-compatible
                     // show a warning for any incompatible mods
                     var mod_type = App.constants.mods.mod_type;
                     var mod_type_string = App.constants.mods.mod_type_string;
                     var incompatible = [];
                     radiant.each(mods, function(_, modData) {
                        if (modData.modType != mod_type.BASE_MODULE && modData.name != 'tower_defense') {
                           if (modData.userEnabled && !compatibleMods[modData.name]) {
                              incompatible.push(modData);
                           }
                        }
                     });

                     if (incompatible.length > 0) {
                        var sIncompatible = '<ul>';
                        incompatible.forEach(modData => {
                           sIncompatible += `<li>${modData.title} (${mod_type_string[modData.modType]} > ${modData.name})</li>`
                        });
                        sIncompatible += '</ul>';

                        var incompatibleDiv = $('<div>')
                           .attr('id', 'shtdCompatibilityWarning')
                           .html(i18n.t('tower_defense:ui.shell.title.incompatible') + sIncompatible);

                        $('#titlescreen').append(incompatibleDiv);
                     }
                  });
            });
         });
      });
   },

});
