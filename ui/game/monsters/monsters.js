var monstersLastSortKey = 'name';
var monstersLastSortDirection = 1;

App.TowerDefenseMonsterView = App.View.extend({
   templateName: 'monsters',
   uriProperty: 'model',
   classNames: ['flex', 'exclusive'],
   skipInvisibleUpdates: true,
   hideOnCreate: false,
   components: {
      "spawned_monsters" : {
         "*": {
            "monster": {
               "stonehearth:unit_info": {},
               "stonehearth:ai": {
                  "status_text_data": {}
               },
               "stonehearth:attributes": {},
               "stonehearth:expendable_resources": {},
               "stonehearth:buffs": {}
            }
         }
      }
   },

   init: function() {
      var self = this;
      self._super();
   },

   willDestroyElement: function() {
      var self = this;
      self.$().find('.tooltipstered').tooltipster('destroy');

      self.$().off('click');

      this._super();
   },

   didInsertElement: function() {
      var self = this;
      self._super();

      this.$().draggable({ handle: '.title' });

      App.tooltipHelper.createDynamicTooltip($('.listTitle'));

      self.$().on('click', '.listTitle', function() {
         var newSortKey = $(this).attr('data-sort-key');
         if (newSortKey) {
            if (newSortKey == self.get('sortKey')) {
               self.set('sortDirection', -(self.get('sortDirection') || 1));
            } else {
               self.set('sortKey', newSortKey);
               self.set('sortDirection', 1);
            }

            monstersLastSortKey = newSortKey;
            monstersLastSortDirection = self.get('sortDirection');
         }
      });
   },

   monsterChanged: function (monster, monsterId) {
      var self = this;
      var existingSelected = self.get('selected');
      if (existingSelected && monster && existingSelected.__self == monster.__self) {
         self.setSelectedCitizen(monster, monsterId, false);
      }
   },

   _updateMonstersArray: function() {
      var self = this;
      var monstersMap = self.get('model.spawned_monsters');
      delete monstersMap.size;
      if (self._containerView) {
         // Construct and manage monster row views manually
         self._containerView.updateRows(monstersMap);
      }
   }.observes('model.spawned_monsters'),

   _onSortChanged: function() {
      var self = this;
      var monstersMap = self.get('model.spawned_monsters');
      delete monstersMap.size;
      if (self._containerView) {
         self._containerView.updateRows(monstersMap, true);
      }
   }.observes('sortKey', 'sortDirection'),

   setSelectedCitizen: function(monster, monsterId, userClicked) {
      var self = this;
      var existingSelected = self.get('selected');
      if (monster) {
         var uri = monster.__self;
         var portrait_url = '/r/get_portrait/?type=headshot&animation=idle_breathe.json&entity=' + uri + '&cache_buster=' + Math.random();
         self.$('#selectedPortrait').css('background-image', 'url(' + portrait_url + ')');

         if (userClicked) { // keep zooming to the person even if they are already selected
            radiant.call('stonehearth:camera_look_at_entity', uri);
            radiant.call('stonehearth:select_entity', uri);
            if (self._moodIconClicked) {
               App.stonehearthClient.showCharacterSheet(uri);
               self._moodIconClicked = false;
            }
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:focus' });
         }
      } else {
         self.$('#selectedPortrait').css('background-image', 'url()');
      }

      self.set('selected', monster);
   },

   setCitizenRowContainerView: function(containerView) {
      this._containerView = containerView;
   }
});

App.StonehearthCitizenTasksRowView = App.View.extend({
   tagName: 'tr',
   classNames: ['row'],
   templateName: 'monsterTasksRow',
   uriProperty: 'model',

   components: {
      "stonehearth:unit_info": {},
      "stonehearth:ai": {
         "status_text_data": {}
      },
      "stonehearth:attributes": {},
      "stonehearth:expendable_resources": {},
      "stonehearth:buffs": {}
   },

   didInsertElement: function() {
      this._super();
      var self = this;
      self._jobDisplayName = null;

      radiant.each(self.taskView.stats, function(i, stat) {
         App.tooltipHelper.createDynamicTooltip(self.$('.' + stat), function () {
            return $(App.tooltipHelper.getTooltip(stat));
         });
      });

      self.$()[0].setAttribute('data-monster-id', self.get('monsterId'));

      App.tooltipHelper.createDynamicTooltip($('#changeWorkingFor'));

      self._update();
      self._onWorkingForChanged();
      self._updateMoodTooltip();
      self._updateDescriptionTooltip();
      self._onJobChanged();
   },

   willDestroyElement: function() {
      var self = this;

      self.$().find('.tooltipstered').tooltipster('destroy');

      if (self._moodTrace) {
         self._moodTrace.destroy();
         self._moodTrace = null;
      }

      if (self._containerView) {
         self._containerView.destroy();
         self._containerView = null;
      }

      self._super();
   },

   click: function(e) {
      var self = this;
      if (!e.target || !$(e.target).hasClass("ignoreClick")) {
         self._selectRow(true);
      }
   },

   actions: {
      changeWorkingFor: function() {
         this.taskView.openPlayerPickerView(this.get('model'));
      }
   },

   _selectRow: function(userClicked) {
      var self = this;
      if (!self.$() || !self.get('model')) {
         return;
      }

      var selected = self.$().hasClass('selected'); // Is this row already selected?
      if (!selected) {
         self.taskView.$('.row').removeClass('selected'); // Unselect everything in the parent view
         self.$().addClass('selected');
      }

      self.taskView.setSelectedCitizen(self.get('model'), self.get('monsterId'), userClicked);
   },

   _update: function() {
      var self = this;
      var monsterData = self.get('model');
      if (self.$() && monsterData) {
         var uri = monsterData.__self;
         if (uri && uri != self._uri) {
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

         // fixup row selection
         if (!self.$().hasClass('selected')) {
            var existingSelected = self.taskView.get('selected');
            if (!existingSelected) {
               // If no selected, select ourself if our Hearthling is selected in the world or first in the monsters manager
               radiant.call_obj('stonehearth.selection', 'get_selected_command')
                  .done(function(o) {
                        var selected = o.selected_entity;

                        if (self.$('.row') && (self._isFirstRow() || self.get('uri') == selected)){
                           self.$('.row').removeClass('selected');
                           self._selectRow();
                        }
                     });
            } else {
               if (self.get('uri') == existingSelected.__self) {
                  self._selectRow();
               }
            }
         }
      }
      self.taskView.monsterChanged(self.get('model'), self.get('monsterId'));
   }.observes('model'),

   isMultiplayer: function() {
      return this.taskView.get('isMultiplayer');
   }.property('taskView.isMultiplayer'),

   _onWorkingForChanged: function() {
      var self = this;
      var workingForPlayerId = self.get('model.stonehearth:work_order.working_for');
      var playerName;
      if (App.stonehearthClient.getPlayerId() == workingForPlayerId) {
         playerName = i18n.t('stonehearth:ui.game.monsters.working_for.myself');
      } else {
         playerName = App.presenceClient.getSteamName(workingForPlayerId) ||
            App.presenceClient.getPlayerDisplayName(workingForPlayerId);
      }

      self.set('workingForPlayerName', playerName);
      var color = App.presenceClient.getPlayerColor(workingForPlayerId);
      if (color) {
         self.set('colorStyle', 'color: rgba(' + color.x + ',' + color.y + ',' + color.z + ', 1)');
      }
   }.observes('model.stonehearth:work_order.working_for'),

   _onJobChanged: function() {
      var self = this;
      var newDisplayName = self.get('model.stonehearth:job.curr_job_name');
      self._jobDisplayName = newDisplayName;
   }.observes('model.stonehearth:job.curr_job_name'),

   _updateMoodTooltip: function() {
      var self = this;
      var moodData = self.get('moodData');
      if (!moodData || !moodData.current_mood_buff) {
         return;
      }
      var currentMood = moodData.mood;
      if (self._currentMood != currentMood) {
         self._currentMood = currentMood;
         Ember.run.scheduleOnce('afterRender', self, function() {
            var monsterData = self.get('model');
            if (monsterData) {
               App.tooltipHelper.createDynamicTooltip(self.$('.moodColumn'), function () {
                  if (!moodData || !moodData.current_mood_buff) {
                     return;
                  }
                  var moodString = App.tooltipHelper.createTooltip(
                     i18n.t(moodData.current_mood_buff.display_name),
                     i18n.t(moodData.current_mood_buff.description));
                  return $(moodString);
               });
            }
         });
      };
   }.observes('moodData'),

   _updateDescriptionTooltip: function() {
      var self = this;
      Ember.run.scheduleOnce('afterRender', self, function() {
         var monsterData = self.get('model');
         if (monsterData) {
            App.tooltipHelper.createDynamicTooltip(self.$('.nameColumn'), function () {
               if (monsterData['stonehearth:unit_info']) {
                  return i18n.t(monsterData['stonehearth:unit_info'].description, { self: monsterData });
               }
            });
         }
      });
   }.observes('model.stonehearth:unit_info'),

   _isFirstRow: function() {
      var tableEl = $('#tasksListTableBody');
      if (tableEl) {
         var rowEls = tableEl.children();
         if (rowEls.length > 0) {
            var viewEl = rowEls[0];
            return viewEl.getAttribute('data-monster-id') == this.get('monsterId');
         }
      }

      return false;
   }
});

// Manually manage child views using this container view for performance reasons
// Reduces DOM and view reconstruction
App.StonehearthCitizenTasksContainerView = App.StonehearthCitizenRowContainerView.extend({
   tagName: 'tbody',
   templateName: 'monsterTasksContainer',
   elementId: 'tasksListTableBody',
   containerParentView: null,
   currentMonstersMap: {},
   rowCtor: App.StonehearthCitizenTasksRowView,

   constructRowViewArgs: function(monsterId, entry) {
      return {
         taskView: this.containerParentView,
         uri:entry.__self,
         monsterId: monsterId
      };
   },

   updateRows: function(monstersMap, sortRequested) {
      var self = this;
      var rowChanges = self.getRowChanges(monstersMap);
      self._super(monstersMap);

      if (rowChanges.numRowsChanged == 1 && self._domModified) {
         // Refresh all rows if added/removed a single row, but dom was modified manually
         self.resetChildren(rowChanges);
      } else if (sortRequested) {
         // If no rows have changed but we need to sort
         self._sortMonstersDom(monstersMap);
      }
   },

   // Add a single row in sorted order
   insertInSortedOrder: function(rowToInsert) {
      var self = this;
      var addIndex = self.get('length') || 0;
      var sortFn = self._getCitizenRowsSortFn(self.currentMonstersMap);
      for (var i = 0; i < self.get('length'); i++) {
         var rowView = self.objectAt(i);
         var sortValue = sortFn(rowToInsert.monsterId, rowView.monsterId);
         if (sortValue < 0) {
            addIndex = i;
            break;
         }
      }

      self.addRow(rowToInsert, addIndex);
   },

   // Re-set container view internal array in sorted order
   resetChildren: function() {
      var self = this;
      var sortFn = self._getCitizenRowsSortFn();
      var sorted = self.toArray().sort(function(a, b) {
         var aMonsterId = a.monsterId;
         var bMonsterId = b.monsterId;

         return sortFn(aMonsterId, bMonsterId);
      });

      self.setObjects(sorted);
      Ember.run.scheduleOnce('afterRender', function() {
         var firstRow = self.objectAt(0);
         if (firstRow) {
            firstRow._selectRow();
         }
      });
      self._domModified = false;
   },

   removeRow: function(monsterId) {
      // Select the first row if the row we are removing is selected
      var selected = this.containerParentView.$('.selected');
      if (selected && selected[0]) {
         var selectedCitizenId = selected[0].getAttribute('data-monster-id');
         if (monsterId == selectedCitizenId && this.get('length') > 1) {
            this.objectAt(0)._selectRow();
         }
      }

      this._super(monsterId);
   },

   _getCitizenRowsSortFn: function(monstersMap) {
      var self = this;
      // Sort based on the sorting property selected by player
      var sortDirection = self.containerParentView.get('sortDirection') || monstersLastSortDirection;
      var sortKey = self.containerParentView.get('sortKey') || monstersLastSortKey;
      var keyExtractors = {
         'name': function(x) {
            // don't actually sort on name; just sort on entity id, which should correspond to creation order
            //return x['stonehearth:unit_info'] && i18n.t(x['stonehearth:unit_info'].custom_name, {self: x});
            return x.id;
         },
         'health': function(x) {
            var resources = x['stonehearth:expendable_resources'] && x['stonehearth:expendable_resources'].resources;
            return resources && resources.health || 0;
         }
      };

      return function(aMonsterId, bMonsterId) {
         if (!aMonsterId || !bMonsterId) {
            return 0;
         }

         var aModel = self.currentMonstersMap[aMonsterId];
         var bModel = self.currentMonstersMap[bMonsterId];

         if (!aModel || !bModel) {
            return 0;
         }
         var aKey = keyExtractors[sortKey](aModel);
         var bKey = keyExtractors[sortKey](bModel);
         var n = (typeof aKey == 'string') ? aKey.localeCompare(bKey) : (aKey < bKey ? -1 : (aKey > bKey) ? 1 : 0);
         if (n == 0) {
            var aName = keyExtractors['name'](aModel);
            var bName = keyExtractors['name'](bModel);
            n = aName ? aName.localeCompare(bName) : 0;
         }

         return n * sortDirection;
      };
   },

   // Hacky but wayyy faster. Manually sort the rows in the DOM.
   // Important note: If we've messed with the DOM this way, the container view's internal
   // child order array will not reflect the changes and thus be in an invalid state. This
   // fine if the the array isn't mutated, but if we need to add or remove a row, we must reset
   // the array using `setObjects` otherwise Ember will render the container view incorrectly.
   _sortMonstersDom: function() {
      var self = this;
      var sortFn = self._getCitizenRowsSortFn();
      var sorted = $('#tasksListTableBody').children().sort(function(a, b) {
         var aMonsterId = a.getAttribute('data-monster-id');
         var bMonsterId = b.getAttribute('data-monster-id');

         return sortFn(aMonsterId, bMonsterId);
      });

      $('#tasksListTableBody').append(sorted);
      self._domModified = true;
   },
});
