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
      "tower_defense:tower": {
         "status_text_data": {}
      },
      "stonehearth:attributes": {
         "attributes": {}
      },
      "stonehearth:building": {},
      "stonehearth:fabricator": {},
      "stonehearth:incapacitation": {
         "sm": {}
      },
      "stonehearth:item_quality": {
      },
      "stonehearth:commands": {},
      "stonehearth:job" : {
         'curr_job_controller' : {}
      },
      "stonehearth:buffs" : {
         "buffs" : {
            "*" : {}
         }
      },
      'stonehearth:expendable_resources' : {},
      "stonehearth:unit_info": {},
      "stonehearth:stacks": {},
      "stonehearth:material": {},
      "stonehearth:workshop": {
         "crafter": {},
         "crafting_progress": {},
         "order": {}
      },
      "stonehearth:pet": {},
      "stonehearth:party" : {},
      "stonehearth:party_member" : {
         "party" : {
            "stonehearth:unit_info" : {}
         }
      },
      "stonehearth:siege_weapon" : {},
      "stonehearth:door": {},
      "stonehearth:iconic_form" : {
         "root_entity" : {
            "uri" : {},
            'stonehearth:item_quality': {},
            'stonehearth:traveler_gift': {},
         }
      },
      "stonehearth:traveler_gift": {}
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
   }.observes('model.uri', 'model.stonehearth:commands.commands', 'model.tower_defense:tower', 'model.stonehearth:unit_info', 'model.stonehearth:job'),

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

   //Friday TODO: get icons for classes, do styling!
   _updateEquipment: function () {
      if (!this.$('#equipmentPane')) return;
      this.$('#equipmentPane').find('.tooltipstered').tooltipster('destroy');

      if (this.get('model.stonehearth:iconic_form') && this.get('model.stonehearth:iconic_form').root_entity) {
         var playerId = this.get('model.player_id');
         var currPlayerId = App.stonehearthClient.getPlayerId();
         var isPlayerOwner = playerId == currPlayerId;
         var equipmentPiece = this.get('model.stonehearth:iconic_form').root_entity.uri.components['stonehearth:equipment_piece'];
         if(equipmentPiece && isPlayerOwner && (equipmentPiece.required_job_level || equipmentPiece.roles)) {
            var tooltipString = i18n.t('stonehearth:ui.game.unit_frame.no_requirements');
            if (equipmentPiece.roles) {
               //this._collectClasses(equipmentPiece.roles);
               var classArray = radiant.findRelevantClassesArray(equipmentPiece.roles);
               this.set('allowedClasses', classArray);
               tooltipString = i18n.t(
                  'stonehearth:ui.game.unit_frame.equipment_description',
                  {class_list: radiant.getClassString(classArray)});
            }
            if (equipmentPiece.required_job_level) {
               this.$('#levelRequirement').text( i18n.t('stonehearth:ui.game.unit_frame.level')  + equipmentPiece.required_job_level);
               tooltipString += i18n.t(
                  'stonehearth:ui.game.unit_frame.level_description',
                  {level_req: equipmentPiece.required_job_level});
            } else {
               this.$('#levelRequirement').text('');
            }

            //Make tooltips
            //Setup tooltips for the combat commands
            var requirementsTooltip = App.tooltipHelper.createTooltip(
                i18n.t('stonehearth:ui.game.unit_frame.class_lv_title'),
               tooltipString);
            this.$('#acceptableClasses').tooltipster({
               content: $(requirementsTooltip)
            });

            this.$('#equipmentPane').show();
         } else {
            this.$('#equipmentPane').hide();
         }
      } else {
         this.$('#equipmentPane').hide();
      }
   }.observes('model.stonehearth:iconic_form.root_entity.uri'),

   _updateSiege: function() {
      var self = this;
      self.set('siegeNumUses', self.get('model.stonehearth:siege_weapon.num_uses'));
      self.set('siegeMaxUses', self.get('model.stonehearth:siege_weapon.max_uses'));
   }.observes('model.stonehearth:siege_weapon.num_uses'),

   _updateItemLimit: function() {
      var self = this;
      var uri = self._getRootUri();
      var setItemLimitInfo = function(info) {
         var itemName = info && ("i18n(stonehearth:ui.game.unit_frame.placement_tags." + info.placement_tag + ")");
         self.set('placementTag', itemName);
         self.set('numPlaced', info && info.num_placed);
         self.set('maxPlaceable', info && info.max_placeable);
      };
      if (uri) {
         radiant.call('stonehearth:check_can_place_item', uri, self._getItemQuality())
            .done(function(response) {
               setItemLimitInfo(response);
            })
            .fail(function(response) {
               setItemLimitInfo(response);
            });
      } else {
         setItemLimitInfo(null);
      }
   }.observes('model.stonehearth:siege_weapon', 'mode.stonehearth:iconic_form.root_entity.components.stonehearth:siege_weapon'),

   _updateDoorLock: function() {
      var self = this;
      var isLocked = self.get('model.stonehearth:door.locked');
      var str = isLocked ? 'locked' : 'unlocked';
      self.set('hasLock', isLocked != null);
      self.set('doorLockIcon', '/stonehearth/ui/game/unit_frame/images/door_' + str + '.png');
      self.set('doorLockedText', str);
   }.observes('model.stonehearth:door.locked'),

   _updatePartyBanner: function() {
      var image_uri = this.get('model.stonehearth:party_member.party.stonehearth:unit_info.icon');
      if (this.$('#partyButton')) {
         if (image_uri) {
            this.$('#partyButton').css('background-image', 'url(' + image_uri + ')');
            this.$('#partyButton').show();
         } else {
            //TODO: is this the best way to figure out if we don't have a party?
            this.$('#partyButton').hide();
         }
      }
   }.observes('model.stonehearth:party_member.party.stonehearth:unit_info'),

   _updateHealth: function() {
      var self = this;
      var currentHealth = self.get('model.stonehearth:expendable_resources.resources.health');
      self.set('currentHealth', Math.floor(currentHealth));

      var maxHealth = self.get('model.stonehearth:attributes.attributes.max_health.user_visible_value');
      self.set('maxHealth', Math.ceil(maxHealth));
   }.observes('model.stonehearth:expendable_resources', 'model.stonehearth:attributes.attributes.max_health'),

   _updateRescue: function() {
      var self = this;

      var curState = self.get('model.stonehearth:incapacitation.sm.current_state');

      self.set('needsRescue', Boolean(curState) && (curState == 'awaiting_rescue' || curState == 'rescuing'));
   }.observes('model.stonehearth:incapacitation.sm'),

   _updateCraftingProgress: function() {
      var self = this;
      var progress = self.get('model.stonehearth:workshop.crafting_progress');
      if (progress) {
         var doneSoFar = progress.game_seconds_done;
         var total = progress.game_seconds_total;
         var percentage = Math.round((doneSoFar * 100) / total);
         self.set('progress', percentage);
         Ember.run.scheduleOnce('afterRender', self, function() {
            self.$('#progress').css("width", percentage / 100 * this.$('#progressbar').width());
         });
      }
   }.observes('model.stonehearth:workshop.crafting_progress'),

   _clearItemQualityIndicator: function() {
      var self = this;
      if (self.$('#qualityGem')) {
         if (self.$('#qualityGem').hasClass('tooltipstered')) {
            self.$('#qualityGem').tooltipster('destroy');
         }
         self.$('#qualityGem').removeClass();
      }
      self.$('#nametag').removeClass();
      self.set('qualityItemCreationDescription', null);
   },

   _applyQuality: function() {
      var self = this;

      self._clearItemQualityIndicator();

      var itemQuality = self._getItemQuality();
      
      if (itemQuality > 1) {
         var qualityLvl = 'quality-' + itemQuality;

         var craftedKey = 'stonehearth:ui.game.unit_frame.crafted_by';
         if (self.get('model.stonehearth:item_quality.author_type') == 'place') {
            craftedKey = 'stonehearth:ui.game.unit_frame.crafted_in';
         }

         var authorName = self._getItemAuthor();
         if (authorName) {
            self.set('qualityItemCreationDescription', i18n.t(
               craftedKey,
               { author_name: authorName }));
         }
         self.$('#qualityGem').addClass(qualityLvl + '-icon');
         self.$('#nametag').addClass(qualityLvl);

         var qualityTooltip = App.tooltipHelper.createTooltip(i18n.t('stonehearth:ui.game.unit_frame.quality.' + qualityLvl));
         self.$('#qualityGem').tooltipster({
            content: self.$(qualityTooltip)
         });
      }
   }.observes('model.stonehearth:item_quality'),

   _applyGifter: function() {
      var self = this;

      self.set('gifterDescription', null)
      var gifterName = self._getGifterName()
      if (gifterName) {
         self.set('gifterDescription', i18n.t(
            'stonehearth:ui.game.unit_frame.traveler.gifted_by',
            { gifter_name: gifterName }));
      }
   }.observes('model.stonehearth:traveler_gift'),

   _updateAppeal: function() {
      var self = this;

      // First, get a client-side approximation so we avoid flicker in most cases.
      var uri = self.get('model.uri');
      var catalogData = App.catalog.getCatalogData(uri);
      if (catalogData && catalogData.appeal) {
         var appeal = catalogData.appeal;
         var itemQuality = self._getItemQuality();
         if (itemQuality) {
            appeal = radiant.applyItemQualityBonus('appeal', appeal, itemQuality);
         }
         self.set('appeal', appeal);
      } else {
         self.set('appeal', null);
      }

      // Then, for server objects, ask the server to give us the truth, the full truth, and nothing but the truth.
      // This matters e.g. for plants that are affected by the Vitality town bonus.
      var address = self.get('model.__self');
      if (address && !address.startsWith('object://tmp/')) {
         radiant.call('stonehearth:get_appeal_command', address)
            .done(function (response) {
               self.set('appeal', response.result);
            });
      }
   }.observes('model.uri'),

   _getRootUri: function() {
      var iconic = this.get('model.stonehearth:iconic_form.root_entity.uri.__self');
      return iconic || this.get('model.uri');
   },

   _getItemQuality: function() {
      return this.get('model.stonehearth:item_quality.quality') || this.get('model.stonehearth:iconic_form.root_entity.stonehearth:item_quality.quality');
   },

   _getItemAuthor: function() {
      return this.get('model.stonehearth:item_quality.author_name') || this.get('model.stonehearth:iconic_form.root_entity.stonehearth:item_quality.author_name');
   },

   _getGifterName: function() {
      return this.get('model.stonehearth:traveler_gift.gifter_name') || this.get('model.stonehearth:iconic_form.root_entity.stonehearth:traveler_gift.gifter_name');
   },

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
