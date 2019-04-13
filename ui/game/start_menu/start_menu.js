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
                     alert(i18n.t(response.message, response.i18n_data));
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

      $.get('/stonehearth/data/ui/start_menu.json')
         .done(function(json) {
            self._buildMenu(json);
            self._addHotkeys();
            self._tracePopulation();

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
   },

   destroy: function() {
      if (this._popTrace) {
         this._popTrace.destroy();
         this._popTrace = null;
      }
      if (this._jobTrace) {
         this._jobTrace.destroy();
         this._jobTrace = null;
      }
      if (this._presenceCallbackName) {
         App.presenceClient.removeChangeCallback(this._presenceCallbackName);
      }

      this._super();
   },

   _buildMenu : function(data) {
      var self = this;

      // load in all the towers from catalog data and create build menu data for that


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

   _trackJobs: function() {
      // find all the jobs in the population
      var self = this;
      self.$('#startMenu').stonehearthMenu('lockAllItems');

      radiant.each(App.jobController.getJobMemberCounts(), function(jobAlias, num_members) {
         if (num_members > 0) {
            var alias = jobAlias.split(":").join('\\:');
            self.$('#startMenu').stonehearthMenu('unlockItem', 'job', alias);
         }
      });

      var jobRoles = App.jobController.getUnlockedJobRoles();
      radiant.each(jobRoles, function(role, someVar) {
         self.$('#startMenu').stonehearthMenu('unlockItem', 'job_role', role);
      });
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

   // create a trace to enable and disable menu items based on the availability
   _tracePopulation: function() {
      var self = this;

      
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
