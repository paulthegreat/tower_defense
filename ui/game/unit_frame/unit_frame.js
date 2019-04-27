var updateUnitFrame = function(data) {
   if (!App.gameView) {
      return;
   }
   let unitFrame = App.gameView.getView(App.StonehearthUnitFrameView);
   if (unitFrame) {
      unitFrame.set('uri', data.selected_entity);
   }
};

$(document).ready(function(){
   $(top).on("radiant_selection_changed.unit_frame", function (_, data) {
      updateUnitFrame(data);
   });
   $(top).on("radiant_toggle_lock", function(_, data) {
      if (!App.gameView) {
         return;
      }
      radiant.call('stonehearth:toggle_lock', data.entity);
   });
});

App.StonehearthUnitFrameView = App.View.extend({
   templateName: 'unitFrame',
   uriProperty: 'model',
   components: {
      "tower_defense:ai": {},
      "tower_defense:tower": {
         "stats": {}
      },
      "stonehearth:attributes": {
         "attributes": {}
      },
      "stonehearth:incapacitation": {
         "sm": {}
      },
      "stonehearth:commands": {},
      "stonehearth:buffs" : {
         "buffs" : {
            "*" : {}
         }
      },
      'stonehearth:expendable_resources' : {},
      "stonehearth:unit_info": {},
      "stonehearth:material": {}
   },

   allowedClasses: null,

   init: function() {
      this._super();
      var self = this;
      radiant.call_obj('stonehearth.selection', 'get_selected_command')
         .done(updateUnitFrame);
   },

   _updateUnitFrameShown: function () {
      var unitFrameElement = this.$('#unitFrame');
      if (!unitFrameElement) {
         return;  // Too early or too late.
      }
      var alias = this.get('model.uri');
      // hide the unit frame for buildings because they look stupid
      if (alias && !this.get('model.stonehearth:building') && !this.get('model.stonehearth:fabricator')) {
         unitFrameElement.removeClass('hidden');
      } else {
         unitFrameElement.addClass('hidden');
      }
   }.observes('model.uri'),

   commandsEnabled: function() {
      return !this.get('model.stonehearth:commands.disabled');
   }.property('model.stonehearth:commands.disabled'),

   showButtons: function() {
      var playerId = App.stonehearthClient.getPlayerId();
      var entityPlayerId = this.get('model.player_id');
      //allow for no player id for things like berry bushes and wild plants that are not owned
      //make sure commands are not disabled
      return this.get('commandsEnabled') && (!entityPlayerId || entityPlayerId == playerId);
   }.property('model.uri'),

   _updateVisibility: function() {
      var self = this;
      var selectedEntity = this.get('uri');
      if (App.getGameMode() == 'normal' && selectedEntity) {
         this.set('visible', true);
      } else {
         this.set('visible', false);
      }
   },

   supressSelection: function(supress) {
      this._supressSelection = supress;
   },

   _updateMoodBuff: function() {
      var self = this;
      var icon = self.get('moodData.current_mood_buff.icon');

      // check if we need to display a different mood icon
      if (icon !== self._moodIcon) {
         self._moodIcon = icon;
         self.set('moodIcon', icon);
      }
   }.observes('moodData', 'model.uri'),

   _updateBuffs: function() {
      var self = this;
      self._buffs = [];
      var attributeMap = self.get('model.stonehearth:buffs.buffs');

      var moodBuff;
      if (attributeMap) {
         radiant.each(attributeMap, function(name, buff) {
            //only push public buffs (buffs who have an is_private unset or false)
            if (buff.invisible_to_player == undefined || !buff.invisible_to_player) {
               var this_buff = radiant.shallow_copy(buff);
               if (this_buff.max_stacks > 1) {
                  this_buff.hasStacks = true;
                  if (this_buff.stacks_vis != null) {
                     this_buff.stacks = this_buff.stacks_vis;
                  }
               }
               self._buffs.push(this_buff);
            }
         });
      }

      self._buffs.sort(function(a, b){
         var aUri = a.uri;
         var bUri = b.uri;
         return (aUri && bUri) ? aUri.localeCompare(bUri) : -1;
      });

      self.set('buffs', self._buffs);
   }.observes('model.stonehearth:buffs'),

   didInsertElement: function() {
      var self = this;

      this._super();

      self.$("#portrait").tooltipster();

      this.$('#nametag').click(function() {
         if ($(this).hasClass('clickable')) {
            var isPet = self.get('model.stonehearth:pet');
            if (isPet) {
               App.stonehearthClient.showPetCharacterSheet(self.get('uri'));
            }
         }
      });

      this.$('#nametag').tooltipster({
         delay: 500,  // Don't trigger unless the player really wants to see it.
         content: ' ',  // Just to force the tooltip to appear. The actual content is created dynamically below, since we might not have the name yet.
         functionBefore: function (instance, proceed) {
            instance.tooltipster('content', self.$('#nametag').text().trim());
            proceed();
         }
      });

      this.$('#portrait').click(function (){
        radiant.call('stonehearth:camera_look_at_entity', self.get('uri'));
      });

      //Setup tooltips for the combat commands
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#defendLocation'),
                                                      'stonehearth:ui.game.unit_frame.defend_location.display_name',
                                                      'stonehearth:ui.game.unit_frame.defend_location.description');
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#attackLocationOrEntity'),
                                                      'stonehearth:ui.game.unit_frame.attack_target.display_name',
                                                      'stonehearth:ui.game.unit_frame.attack_target.description');
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#moveToLocation'),
                                                      'stonehearth:ui.game.unit_frame.move_unit.display_name',
                                                      'stonehearth:ui.game.unit_frame.move_unit.description');
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#partyButton'),
                                                      'stonehearth:ui.game.unit_frame.manage_party.display_name',
                                                      'stonehearth:ui.game.unit_frame.manage_party.description');
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#cancelCombatButton'),
                                                      'stonehearth:ui.game.unit_frame.cancel_order.display_name',
                                                      'stonehearth:ui.game.unit_frame.cancel_order.description');

      this._updateUnitFrameShown();

      self._targetFilters = App.constants.tower_defense.tower.target_filters;

      self.$('#stickyTargetingCheckbox').change(function() {
         radiant.call('tower_defense:set_tower_sticky_targeting', self.get('uri'), this.checked);
      });

      self.$().on('change', '.filterTypeCheckbox', function() {
         var filterType = $(this).attr('filterType');
         var checked = this.checked;

         var filters = self.get('model.tower_defense:tower.target_filters');
         if (checked) {
            filters.push(filterType);
         }
         else {
            for (var i = 0; i < filters.length; i++) {
               if (filters[i] == filterType) {
                  filters.splice(i, 1);
                  break;
               }
            }
         }

         radiant.call('tower_defense:set_tower_target_filters', self.get('uri'), filters);
      });

      // https://stackoverflow.com/questions/2072848/reorder-html-table-rows-using-drag-and-drop
      // if checked and dragged, reorder (always remain checked)
      // if unchecked and dragged, mark checked and reorder only if dragged at least above lowest checked, otherwise ignore
      self.$().on('mousedown', '.grabbable', function (e) {
         var tr = $(e.target).closest('tr');
         var sy = e.pageY;
         var drag;

         if ($(e.target).is('tr')) {
            tr = $(e.target);
         }
         var index = tr.index();
         $(tr).addClass('grabbed');

         var thisFilter = $(this).attr('filterType');
         var curFilters = self.get('model.tower_defense:tower.target_filters');
         var isChecked = false;
         radiant.each(curFilters, function(i, key) {
            if (thisFilter == key) {
               isChecked = true;
            }
         });

         function move (e) {
            if (!drag && Math.abs(e.pageY - sy) < 10) {
               return;
            }
            drag = true;

            tr.siblings().each(function() {
               var s = $(this), i = s.index(), y = s.offset().top;

               if (e.pageY >= y && e.pageY < y + s.outerHeight()) {
                  if (i < tr.index()) {
                     s.insertAfter(tr);
                  }
                  else {
                     s.insertBefore(tr);
                  }
                  return false;
               }
            });
         }

         function up (e) {
            var newIndex = tr.index();
            if (drag && index != newIndex) {
               drag = false;
               if (!isChecked) {
                  if (newIndex < curFilters.length) {
                     // we dragged an unchecked filter up into the checked filters, so check it and apply changes
                     curFilters.splice(newIndex, 0, thisFilter);
                     radiant.call('tower_defense:set_tower_target_filters', self.get('uri'), curFilters);
                  }
                  else {
                     // we dragged an unchecked filter, so just reset the table
                     self._updateTargetFilters();
                  }
               }
               else {
                  // first remove the old one
                  curFilters.splice(index, 1);
                  // then add the new one
                  curFilters.splice(newIndex, 0, thisFilter);
                  radiant.call('tower_defense:set_tower_target_filters', self.get('uri'), curFilters);
               }
            }
            $(document).unbind('mousemove', move).unbind('mouseup', up);
            $(tr).removeClass('grabbed');
         }

         $(document).mousemove(move).mouseup(up);
      });
   },

   willDestroyElement: function() {
      this.$().find('.tooltipstered').tooltipster('destroy');
      this.$('.name').off('click');
      this.$('#portrait').off('click');

      if (self._moodTrace) {
         self._moodTrace.destroy();
         self._moodTrace = null;
      }
   },

   commands: function() {
      // Hide commands if this is another player's entity, unless the command is
      // set to be visible to all players
      var playerId = App.stonehearthClient.getPlayerId();
      var entityPlayerId = this.get('model.player_id');
      var filterFn = null;
      var playerIdValid = !entityPlayerId || entityPlayerId == playerId || entityPlayerId == 'critters' || entityPlayerId == 'animals';
      if (!playerIdValid) {
         filterFn = function(key, value) {
            if (!value.visible_to_all_players) {
               return false;
            }
         };
      }
      var commands = radiant.map_to_array(this.get('model.stonehearth:commands.commands'), filterFn);
      commands.sort(function(a, b){
         var aName = a.ordinal ? a.ordinal : 0;
         var bName = b.ordinal ? b.ordinal : 0;
         var n = bName - aName;
         return n;
      });
      return commands;
   }.property('model.stonehearth:commands.commands'),

   _modelUpdated: function() {
      var self = this;
      var uri = self.get('uri');
      self.set('moodData', null);
      if (uri && self._uri != uri) {
         self._uri = uri;
         radiant.call('stonehearth:get_mood_datastore', uri)
            .done(function (response) {
               if (self.isDestroying || self.isDestroyed) {
                  return;
               }
               if (self._moodTrace) {
                  self._moodTrace.destroy();
               }
               self._moodTrace = new RadiantTrace(response.mood_datastore, { current_mood_buff: {} })
                  .progress(function (data) {
                     if (self.isDestroying || self.isDestroyed) {
                        return;
                     }
                     self.set('moodData', data);
                  })
            });
      }
   }.observes('model.uri'),

   _updateUnitFrameWidth: function() {
      //the following is some rough dynamic sizing to prevent descriptions and command buttons from overlapping
      //it has to happen after render to check the elements for the unit frame for the newly selected item, not the previous
      Ember.run.scheduleOnce('afterRender', this, function() {
         var width = Math.max(this.$('#descriptionDiv').width(), this.$('#activityDiv').width()) + this.$('#commandButtons').width() + 30; // + 30 to account for margins
         if (this.get('hasPortrait')) {
            width += this.$('#portrait-frame').width();
         }

         this.$('#unitFrame').css('width', Math.max(500, width) + 'px'); //don't want it getting too bitty
      });
   }.observes('model.uri', 'model.stonehearth:commands.commands', 'model.tower_defense:ai', 'model.stonehearth:unit_info', 'model.stonehearth:job'),

   _updateMaterial: function() {
      var self = this;
      var hasCharacterSheet = false;
      var alias = this.get('model.uri');
      if (alias) {
         var catalogData = App.catalog.getCatalogData(alias);
         if (catalogData) {
            var materials = null;
            if (catalogData.materials){
               if ((typeof catalogData.materials) === 'string') {
                  materials = catalogData.materials.split(' ');
               } else {
                  materials = catalogData.materials;
               }
            } else {
               materials = [];
            }
            if (materials.indexOf('human') >= 0) {
               hasCharacterSheet = true;
               self._moodIcon = null;
            }

            self.set('itemIcon', catalogData.icon);
         }
      }

      var self = this;
      var isPet = false;
      var petComponent = self.get('model.stonehearth:pet');
      if (petComponent) {
         hasCharacterSheet = true;
         isPet = true;
         self._moodIcon = null;
         self._updatePortrait();
         self.set('itemIcon', null);
      }

      self.set('isPet', isPet);
      self.set('hasCharacterSheet', hasCharacterSheet);
   }.observes('model.stonehearth:pet', 'model.stonehearth:unit_info'),

   _hasPortrait: function() {
      if (this.get('model.stonehearth:job')) {
         return true;
      }
      //Parties have icons too
      if (this.get('model.stonehearth:party')) {
         return true;
      }
      var isPet = this.get('model.stonehearth:pet');

      if (isPet && isPet.is_pet) {
         return true;
      }
      return false;
   },

   _updatePortrait: function() {
      if (!this.$()) {
         return;
      }
      var uri = this.uri;

      if (uri && this._hasPortrait()) {
         var portrait_url = '';
         if (this.get('model.stonehearth:party')) {
            portrait_url = this.get('model.stonehearth:unit_info.icon');
         } else {
            portrait_url = '/r/get_portrait/?type=headshot&animation=idle_breathe.json&entity=' + uri + '&cache_buster=' + Math.random();
         }
         //this.set('portraitSrc', portrait_url);
         this.set('hasPortrait', true);
         this.$('#portrait-frame').removeClass('hidden');
         this.$('#portrait').css('background-image', 'url(' + portrait_url + ')');
      } else {
         this.set('hasPortrait', false);
         this.set('portraitSrc', "");
         this.$('#portrait').css('background-image', '');
         this.$('#portrait-frame').addClass('hidden');
      }

      this._updateDisplayNameAndDescription();
   }.observes('model.stonehearth:unit_info', 'model.stonehearth:job'),

   _updateDisplayNameAndDescription: function() {
      var alias = this.get('model.uri');
      this.set('entityWithNonworkerJob', false);

      var description = this.get('model.stonehearth:unit_info.description');
      if (this.get('model.stonehearth:job') && !this.get('model.stonehearth:job.curr_job_controller.no_levels') && this.get('model.stonehearth:job.curr_job_name') !== '') {
         this.set('entityWithNonworkerJob', true);
         this.$('#Lvl').text( i18n.t('stonehearth:ui.game.unit_frame.Lvl'));
      }

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

      this.set('display_name', display_name);
      this.notifyPropertyChange('display_name');
      this.set('description', description);
      this.notifyPropertyChange('description');
   }.observes('model.uri'),

   _updateJobDescription: function() {
      // Force the unit info description to update again after curr job name changes.
      // This used to work (or I never noticed.) but now the timing is such that the description change comes in before the job name. -yshan 1/19/2016
      this._updateDisplayNameAndDescription();
   }.observes('model.stonehearth:job.curr_job_name'),

   _updateItemStacks: function() {
      // Force the unit info description to update again after item stacks changes.
      this._updateDisplayNameAndDescription();
   }.observes('model.stonehearth:stacks'),

   _updateCombatTools: function() {
      var isCombatClass = this.get('model.stonehearth:job.curr_job_controller.is_combat_class');
      var playerId = this.get('model.player_id');
      var currPlayerId = App.stonehearthClient.getPlayerId();
      var isPlayerOwner = playerId == currPlayerId;
      var combatControlsElement = this.$('#combatControls');
      if (combatControlsElement) {
         if (isPlayerOwner && (isCombatClass || this.get('model.stonehearth:party'))) {
            combatControlsElement.show();
         } else {
            combatControlsElement.hide();
         }
      }
   }.observes('model.stonehearth:job.curr_job_controller', 'model.stonehearth:party'),

   _callCombatCommand: function(command) {
      App.stonehearthClient.giveCombatCommand(command, this.get('uri'));
   },

   _updateHealth: function() {
      var self = this;
      var currentHealth = self.get('model.stonehearth:expendable_resources.resources.health');
      self.set('currentHealth', Math.floor(currentHealth));

      var maxHealth = self.get('model.stonehearth:attributes.attributes.max_health.user_visible_value');
      self.set('maxHealth', Math.ceil(maxHealth));
   }.observes('model.stonehearth:expendable_resources', 'model.stonehearth:attributes.attributes.max_health'),

   _getRootUri: function() {
      var iconic = this.get('model.stonehearth:iconic_form.root_entity.uri.__self');
      return iconic || this.get('model.uri');
   },

   _updateTargetFilters: function() {
      var self = this;
      var filters = self.get('model.tower_defense:tower.target_filters');
      if (!filters) {
         self.set('targetFilters', null);
         return;
      }

      var filterTbl = {};
      var filterArr = [];
      radiant.each(filters, function(i, key) {
         filterTbl[key] = i;
      });
      radiant.each(self._targetFilters, function(_, filter) {
         var f = radiant.shallow_copy(filter);
         f.ordinal = filterTbl[f.key];
         f.id = 'checkbox_' + f.key;
         filterArr.push(f);
      });
      filterArr.sort((a, b) => {
         if (a.ordinal == null && b.ordinal == null) {
            return a.key < b.key ? -1 : (a.key > b.key ? 1 : 0);
        }
        else if (a.ordinal == null) {
            return 1;
        }
        else if (b.ordinal == null) {
            return -1;
        }
        else {
            return a.ordinal - b.ordinal;
        }
      });
      
      self.set('targetFilters', filterArr);

      Ember.run.scheduleOnce('afterRender', self, '_setTargetFilterStyling');
   }.observes('model.tower_defense:tower.target_filters'),

   _setTargetFilterStyling: function() {
      var self = this;
      radiant.each(self.get('targetFilters'), function(_, filter) {
         self.$('#' + filter.id).prop('checked', filter.ordinal != null);
         
         App.tooltipHelper.attachTooltipster(self.$('.filterType[filterType="' + filter.key + '"]'),
            $(App.tooltipHelper.createTooltip(null,
               i18n.t(filter.description)
            ))
         );
      });
   },

   _updateStickyTargeting: function() {
      var self = this;
      var sticky = self.get('model.tower_defense:tower.sticky_targeting');
      self.$('#stickyTargetingCheckbox').prop('checked', sticky);
      App.tooltipHelper.attachTooltipster(self.$('#stickyTargeting'),
            $(App.tooltipHelper.createTooltip(null,
               i18n.t('i18n(tower_defense:ui.game.towerTargetingWindow.stickyTargeting.description)')
            ))
         );
   }.observes('model.tower_defense:tower.sticky_targeting'),

   actions: {
      selectParty: function() {
         radiant.call_obj('stonehearth.party_editor', 'select_party_for_entity_command', this.get('uri'))
            .fail(function(response){
               console.error(response);
            });
      },
      moveToLocation: function() {
         this._callCombatCommand('place_move_target_command');
      },
      attackTarget: function() {
         this._callCombatCommand('place_attack_target_command');
      },
      defendLocation: function() {
         this._callCombatCommand('place_hold_location_command');
      },
      cancelOrders: function() {
         radiant.call_obj('stonehearth.combat_commands', 'cancel_order_on_entity', this.get('uri'))
            .done(function(response){
               //TODO: pick a better sound?
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
            });
      },
      toggleRescueTarget: function() {
         radiant.call_obj('stonehearth.population', 'toggle_rescue_command', this.get('uri'));
      }
   }
});

App.StonehearthCommandButtonView = App.View.extend({
   classNames: ['inlineBlock'],

   didInsertElement: function () {
      var hkaction = this.content.hotkey_action;
      this.$('div').attr('hotkey_action', hkaction);
      this._super();
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('div'), this.content.display_name, this.content.description);
   },

   willDestroyElement: function() {
      this.$().find('.tooltipstered').tooltipster('destroy');
   },

   actions: {
      doCommand: function(command) {
         App.stonehearthClient.doCommand(this.get("parentView.uri"), this.get("parentView.model.player_id"), command);
      }
   }
});
