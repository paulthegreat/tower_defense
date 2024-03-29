App.StonehearthStartMenuView = App.View.extend({
   templateName: 'stonehearthStartMenu',
   //classNames: ['flex', 'fullScreen'],

   _foundjobs : {},
   CHANGE_CALLBACK_NAME: 'start_menu',

   menuActions: {
      td_create_tower: function(self, data) {
         // try to create and place the specified tower
         if (data && data.uri) {
            radiant.call('tower_defense:create_and_place_entity', data.uri)
               .done(function() {
                  // if we successfully placed one, try doing it again
                  self.menuActions.td_create_tower(self, data);
               })
               .fail(function(response) {
                  if (response.message) {
                     $(document).trigger('td_player_alert', {
                        message: i18n.t(response.message, response.i18n_data)
                     });
                  }
               });
         }
      },
      td_give_gold: function(self, data) {
         // cheat give yourself gold
         if (data && data.gold_amount) {
            radiant.call('tower_defense:give_gold_cheat_command', data.gold_amount);
         }
      },
      td_give_wood: function(self, data) {
         // cheat give yourself wood
         if (data && data.wood_amount) {
            radiant.call('tower_defense:give_wood_cheat_command', data.wood_amount);
         }
      },
      td_unlock_all: function() {
         // cheat unlock all kingdoms
         radiant.call('tower_defense:unlock_all_kingdoms_cheat_command');
      },
      reference_menu: function() {
         //return;  // TODO: actually make the reference view
         var referenceWindow = App.gameView.getView(App.TowerDefenseReferenceView);
         if (referenceWindow) {
            if (referenceWindow.isVisible) {
               referenceWindow.hide();
            }
            else {
               referenceWindow.show();
            }
         }
         else {
            App.gameView.addView(App.TowerDefenseReferenceView);
         }
      },
      bulletin_manager: function() {
         App.bulletinBoard.toggleListView();
      },
      multiplayer_menu: function() {
         App.stonehearthClient.showMultiplayerMenu();
      }
   },

   hideConditions: {
      multiplayer_disabled: function () {
         return !App.stonehearthClient.isMultiplayerEnabled();
      }
   },

   init: function() {
      this._super();
      var self = this;

      self._kingdomOrdinals = {};
   },

   didInsertElement: function() {
      this._super();

      var self = this;

      if (!this.$()) {
         return;
      }

      $('#startMenuTrigger').click(function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:trigger_click'} );
      });

      App.stonehearth.startMenu = self.$('#startMenu');

      self._kingdomTrace  = new StonehearthDataTrace('stonehearth:playable_kingdom_index', {"kingdoms": {"*": {} } })
         .progress(function(response) {
            // Process the response
            radiant.each(response.kingdoms, function(k, v) {
               self._kingdomOrdinals[v.kingdom_id] = v.ordinal;
            });

            radiant.call_obj('tower_defense.game', 'get_tower_gold_cost_multiplier_command')
               .done(function(response) {
                  self._towerGoldCostMultiplier = response.multiplier || 1;

                  self._getBaseStartMenu(function(json) {
                     self._buildMenu(json);
                     self._addHotkeys();
                     self._tracePlayers();

                     // Add badges for notifications
                     App.bulletinBoard.getTrace()
                        .progress(function(result) {
                           var bulletins = result.bulletins;
                           var alerts = result.alerts;
                           var numBulletins = bulletins ? Object.keys(bulletins).length : 0;
                           var numAlerts = alerts ? Object.keys(alerts).length : 0;

                           if (numBulletins > 0 || numAlerts > 0) {
                              //self.$('#bulletin_manager').pulse();
                              self.$('#bulletin_manager').addClass('active');
                           } else {
                              self.$('#bulletin_manager').removeClass('active');
                           }
                           self._updateBulletinCount(numBulletins + numAlerts);
                        });

                     // Add badges for number of players connected
                     var presenceCallback = function(presenceData) {
                        var numConnected = 0;
                        radiant.each(presenceData, function(playerId, data) {
                           var connectionStates = App.constants.multiplayer.connection_state;
                           if (data.connection_state == connectionStates.CONNECTED || data.connection_state == connectionStates.CONNECTING) {
                              numConnected++;
                           }
                        });

                        self._updateConnectedPlayerCount(numConnected);
                     };

                     App.presenceClient.addChangeCallback(self.CHANGE_CALLBACK_NAME, presenceCallback, true);
                     self._presenceCallbackName = self.CHANGE_CALLBACK_NAME;

                     App.resolveStartMenuLoad();
                  });
            });
         });
   },

   destroy: function() {
      if (this._playerTrace) {
         this._playerTrace.destroy();
         this._playerTrace = null;
      }
      if (this._kingdomTrace) {
         this._kingdomTrace.destroy();
         this._kingdomTrace = null;
      }

      this._super();
   },

   _getBaseStartMenu: function(cb) {
      $.get('/stonehearth/data/ui/start_menu.json')
         .done(function(json) {
            radiant.call('radiant:get_config', 'mods.tower_defense.cheats_enabled')
               .done(function(response) {
                  var cheatsEnabled = response['mods.tower_defense.cheats_enabled'];
                  if (cheatsEnabled) {
                     $.get('/tower_defense/data/ui/start_menu_cheats.json')
                        .done(function(cheats_json) {
                           radiant.each(cheats_json, function(k, v) {
                              json[k] = v;
                           });
                           cb(json);
                        });
                  }
                  else {
                     cb(json);
                  }
               });
            });
   },

   _buildMenu : function(data) {
      var self = this;

      // load in all the towers from catalog data and create build menu data for that
      data = self._prependBuildMenus(data);

      this.$('#startMenu').stonehearthMenu({
         data : data,
         click : function (id, nodeData) {
            self._onMenuClick(self, id, nodeData);
         },
         shouldHide : function (id, nodeData) {
            return self._shouldHide(id, nodeData)
         },
      });

   },

   _prependBuildMenus: function(data) {
      var self = this;
      var catalogData = App.catalog.getAllCatalogData();

      var towersByBuff = {};
      var newDataTbl = {};
      radiant.each(catalogData, function(uri, entityData) {
         var tower = entityData.tower;
         if (tower && Array.isArray(tower.kingdoms)) {
            tower.gold_cost = (tower.cost && tower.cost.gold || 0) * self._towerGoldCostMultiplier;
            tower.cost = tower_defense.getCostString(tower.cost, self._towerGoldCostMultiplier);
            tower.detailed_description = tower.description || 'i18n(tower_defense:entities.towers.generic.detailed_description)';
            tower.description = entityData.description;
            tower.required_kingdoms = self._getRequiredKingdoms(tower);
            tower.requirement_text = tower.requirement_text || self._getRequirementText(tower);

            // examine the tower's weapons and determine what buffs they apply
            if (tower.weapons && tower.weapons.default_weapon) {
               tower_defense.addTowersByBuffs(towersByBuff, uri, tower);
            }

            tower.kingdoms.forEach(kingdom => {
               var kingdomTowers = newDataTbl[kingdom];
               if (!kingdomTowers) {
                  kingdomTowers = {
                     key: kingdom,
                     ordinal: self._kingdomOrdinals[kingdom],
                     towers: [],
                     entry: {
                        class: 'dock',
                        game_mode: 'place',
                        menuHideSound: 'stonehearth:sounds:ui:start_menu:wash_out',
                        menuShowSound: 'stonehearth:sounds:ui:start_menu:wash_in',
                        name: `i18n(tower_defense:data.population.${kingdom}.display_name)`,
                        description: `i18n(tower_defense:data.population.${kingdom}.description)`,
                        icon: `/tower_defense/ui/game/start_menu/images/build_${kingdom}.png`,
                        kingdom: kingdom,
                        items: {}
                     }
                  };
                  newDataTbl[kingdom] = kingdomTowers;
               }
               kingdomTowers.towers.push(radiant.shallow_copy(entityData));
            });
         }
      });

      tower_defense.setTowersByBuff(towersByBuff);

      var newDataArr = [];
      radiant.each(newDataTbl, function(k, v) {
         // sort by level descending, then by ordinal ascending
         // this way we can divide vertically into tiers
         v.towers.sort((a, b) => {
            var result = b.tower.level - a.tower.level;
            if (result == 0) {
               result = a.tower.ordinal - b.tower.ordinal;
            }
            return result;
         });

         radiant.each(v.towers, function(i, t) {
            var entry = {
               name: t.display_name,
               description: t.tower.detailed_description,
               icon: t.icon,
               level: t.tower.level || 0,
               ordinal: (t.tower.ordinal || t.tower.level || 0) + (t.name || ''),
               is_mixed_tower: t.tower.kingdoms.length > 1,
               class: 'button',
               sticky: 'true',
               menu_action: 'td_create_tower',
               uri: t.uri,
               tower: true,
               requirement_text: t.tower.requirement_text,
               towerData: t.tower
            };
            v.entry.items[`${k}_tower_${i}`] = entry;
         })

         newDataArr.push(v);
      });

      newDataArr.sort((a, b) => a.ordinal - b.ordinal);
      var newData = {};
      radiant.each(newDataArr, function(k, v) {
         newData[v.key] = v.entry;
      });
      radiant.each(data, function(k, v) {
         newData[k] = v;
      });

      return newData;
   },

   _getRequiredKingdoms: function(towerData) {
      return towerData.kingdoms.map(kingdom => "<span class='requiredKingdom'>" +
            i18n.t(`i18n(tower_defense:data.population.${kingdom}.display_name)`) +
            "</span>").join(' & ');
   },

   _getRequirementText: function(towerData) {
      // tower entity data has a kingdoms array and a level
      return `i18n(tower_defense:entities.towers.generic.requires_kingdoms)`;
   },

   _updateKingdomCapabilities: function() {
      // find all the jobs in the population
      var self = this;
      self.$('#startMenu').stonehearthMenu('unlockItems', self._playerKingdomsCache, self._playerKingdomLevelCosts);
   },

   _updateConnectedPlayerCount: function(num) {
      if (this.$('#multiplayer_menu')) {
         if (num > 1) {
            this.$('#multiplayer_menu .badgeNum').text(num);
            this.$('#multiplayer_menu .badgeNum').show();
         } else {
            this.$('#multiplayer_menu .badgeNum').hide();
         }
      }
   },

   _updateBulletinCount: function(num_bulletins) {
      var self = this;
      if (num_bulletins > 0) {
         self.$('#bulletin_manager .badgeNum').text(num_bulletins);
         self.$('#bulletin_manager .badgeNum').show();
      } else {
         self.$('#bulletin_manager .badgeNum').hide();
      }
   },

   // TODO: create a trace to enable and disable menu items based on the availability
   _tracePlayers: function() {
      var self = this;

      self._playerTrace = new RadiantTrace();
      radiant.call_obj('tower_defense.game', 'get_current_player_command')
         .done(function(result) {
            self._playerTrace.traceUri(result.player)
               .progress(function(data) {
                  // this is going to get updated a lot just from resource changes, so compare kingdom levels to cached version
                  if (self._didKingdomsChange(data.kingdoms)) {
                     self._playerKingdomsCache = data.kingdoms;
                     self._playerKingdomLevelCosts = data.kingdom_level_costs;
                     self._updateKingdomCapabilities();
                  }
               });
         });
   },

   _didKingdomsChange: function(kingdoms) {
      var self = this;
      
      if (!self._playerKingdomsCache) {
         return true;
      }

      // don't need to compare size because we can only add capabilities, never remove them
      // if (radiant.size(self._playerKingdomsCache) != radiant.size(kingdoms)) {
      //    return true;
      // }

      var changed = false;
      radiant.each(kingdoms, function(k, v) {
         if (self._playerKingdomsCache[k] != v) {
            changed = true;
         }
      });

      return changed;
   },

   _onMenuClick: function(self, menuId, nodeData) {
      var menuAction = nodeData.menu_action? this.menuActions[nodeData.menu_action] : this.menuActions[menuId];
      // do the menu action
      if (menuAction) {
         menuAction(self, nodeData);
      }
   },

   _shouldHide: function (menuId, nodeData) {
      var shouldHideFn = nodeData.hide_condition ? this.hideConditions[nodeData.hide_condition] : null;
      if (shouldHideFn) {
         return shouldHideFn.call(this, nodeData);
      }
      return false;
   }

});
