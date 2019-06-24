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
                     var td = [];
                     radiant.each(mods, function(_, modData) {
                        if (modData.name == 'tower_defense') {
                           td.push(modData);
                        }
                        else if (modData.modType != mod_type.BASE_MODULE) {
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

                        var disable = $('<button>')
                           .attr('id', 'disableMods')
                           .addClass('warn')
                           .html(i18n.t('tower_defense:ui.shell.title.disable_mods'));

                        App.tooltipHelper.attachTooltipster(disable,
                           $(App.tooltipHelper.createTooltip(null, i18n.t('tower_defense:ui.shell.title.disable_mods_tooltip')))
                        );
                        disable.on('click', function() {
                           self._disableIncompatibleMods(incompatible);
                        });

                        var buttons = $('<div>')
                           .attr('id', 'shtdCompatibilityButtons')
                           .addClass('gui')
                           .append(disable);

                        var incompatibleDiv = $('<div>')
                           .attr('id', 'shtdCompatibilityWarning')
                           .html(i18n.t('tower_defense:ui.shell.title.incompatible') + sIncompatible)
                           .append(buttons);

                        $('#titlescreen').append(incompatibleDiv);
                     }
                     else {
                        radiant.call('radiant:get_config', 'mods.tower_defense.disabled_mods')
                           .done(function(response) {
                              var mods = response['mods.tower_defense.disabled_mods'] || [];

                              var compatibleText;
                              var enableText;
                              var enableTooltip;
                              if (mods.length > 0) {
                                 compatibleText = i18n.t('tower_defense:ui.shell.title.compatible_with_disabled') + '<ul>';
                                 mods.forEach(modData => {
                                    compatibleText += `<li>${modData.title} (${modData.type} > ${modData.name})</li>`
                                 });
                                 compatibleText += '</ul>';

                                 enableText = i18n.t('tower_defense:ui.shell.title.disable_shtd_enable_mods');
                                 enableTooltip = i18n.t('tower_defense:ui.shell.title.disable_shtd_enable_mods_tooltip');
                              }
                              else {
                                 compatibleText = i18n.t('tower_defense:ui.shell.title.compatible');
                                 enableText = i18n.t('tower_defense:ui.shell.title.disable_shtd');
                                 enableTooltip = i18n.t('tower_defense:ui.shell.title.disable_shtd_tooltip');
                              }

                              var enable = $('<button>')
                                 .attr('id', 'enableMods')
                                 .addClass('green')
                                 .html(enableText);

                              App.tooltipHelper.attachTooltipster(enable,
                                 $(App.tooltipHelper.createTooltip(null, enableTooltip))
                              );
                              enable.on('click', function() {
                                 self._enableIncompatibleMods(mods, td);
                              });

                              var buttons = $('<div>')
                                 .attr('id', 'shtdCompatibilityButtons')
                                 .addClass('gui')
                                 .append(enable);

                              var incompatibleDiv = $('<div>')
                                 .attr('id', 'shtdCompatibilityWarning')
                                 .addClass('compatible')
                                 .html(compatibleText)
                                 .append(buttons);

                              $('#titlescreen').append(incompatibleDiv);
                           });
                     }
                  });
            });
         });
      });
   },

   _disableIncompatibleMods: function (mods) {
      var disabledMods = [];
      mods.forEach(modData => {
         var modTypeString = App.constants.mods.mod_type_string[modData.modType];
         var modConfig = 'mods.' + modTypeString + '.' + modData.name + '.enabled';
         disabledMods.push({
            type: modTypeString,
            name: modData.name,
            title: modData.title
         });
         radiant.call('radiant:set_config', modConfig, false);
      });
      radiant.call('radiant:set_config', 'mods.tower_defense.disabled_mods', disabledMods);

      radiant.call('radiant:client:return_to_main_menu');
   },

   _enableIncompatibleMods: function (mods, towerDefenseMods) {
      mods.forEach(mod => {
         var modConfig = 'mods.' + mod.type + '.' + mod.name + '.enabled';
         radiant.call('radiant:set_config', modConfig, true);
      });
      radiant.call('radiant:set_config', 'mods.tower_defense.disabled_mods', []);

      towerDefenseMods.forEach(mod => {
         var modTypeString = App.constants.mods.mod_type_string[mod.modType];
         var modConfig = 'mods.' + modTypeString + '.' + mod.name + '.enabled';
         radiant.call('radiant:set_config', modConfig, false);
      });

      radiant.call('radiant:client:return_to_main_menu');
   }

});
