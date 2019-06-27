$.widget( "stonehearth.stonehearthMenu", $.stonehearth.stonehearthMenu, {
   _addItems: function(nodes, parentId, name, depth, kingdom) {
      if (!nodes) {
         return;
      }

      if (!depth) {
         depth = 0;
      }

      var self = this;
      var groupClass = depth == 0 ? 'rootGroup' : 'menuItemGroup'
      var el = $('<div>').attr('parent', parentId)
                         .addClass(groupClass)
                         .addClass('depth' + depth)
                         .append('<div class=close></div>')
                         .appendTo(self.menu);
      var tbl;
      var singleCell;
      var mixedCell;

      // add a special background div for the root group
      if (depth == 0) {
         el.append('<div class=background></div>');
      }
      else if(kingdom) {
         tbl = $('<table>')
            .addClass('buildTowersTable')
            .appendTo(el);
      }

      var prevTier;

      $.each(nodes, function(key, node) {
         self._dataToMenuItemMap[key] = node;

         if (self.options.shouldHide) {
            if (self.options.shouldHide(key, node)) {
               return true; // return true to continue, because jquery.
            }
         }

         if (tbl && prevTier != node.level) {
            prevTier = node.level;
            var row = $('<tr>').appendTo(tbl);
            singleCell = $('<td>').appendTo(row);
            mixedCell = $('<td>').appendTo(row);
         }

         var elToAppendTo = (node.is_mixed_tower ? mixedCell : singleCell) || el;

         var item = $('<div>')
                     .attr('id', key)
                     .attr('hotkey_action', node.hotkey_action || '')
                     .addClass('menuItem')
                     .addClass('button')
                     .addClass(node.class)
                     .appendTo(elToAppendTo);

         var icon = $('<img>')
                     .attr('src', node.icon)
                     .addClass('icon')
                     .appendTo(item);

         item.append('<div class="notificationPip"></div>');
         item.append('<div class="badgeNum"></div>');

         if ((node.items || node.has_custom_menu) && depth == 0) {
            item.append('<img class=arrow>')
         }

         if (node.tower) {
            item.addClass('locked'); // initially lock all tower nodes
         }

         if (node.kingdom) {
            item.addClass('unused');
         }

         if (node.menu_action) {
            item.attr('menu_action', node.menu_action);
         }

         self._buildTooltip(item);

         if (node.items) {
            self._addItems(node.items, key, node.name, depth + 1, node.kingdom);
         }
      });

      if (name) {
         $('<div>').html(i18n.t(name))
                   .addClass('header')
                   .appendTo(el);
      }
   },

   unlockItems: function(kingdoms, levelCosts) {
      var self = this;

      radiant.each(self._dataToMenuItemMap, function(id, node) {
         var item = $('#' + id);

         if (node.towerData) {
            for (var i = 0; i < node.towerData.kingdoms.length; i++) {
               var kingdom = node.towerData.kingdoms[i];
               if (!kingdoms[kingdom] || kingdoms[kingdom] < (node.towerData.level || 0)) {
                  return;
               }
            }

            item.removeClass('locked');
            self._buildTooltip(item);
         }

         if (node.kingdom) {
            var curLevel = kingdoms[node.kingdom];
            if (curLevel) {
               item.removeClass('unused');
               item.find('.badgeNum')
                  .text(curLevel)
                  .show();
            }
            var costs = levelCosts && levelCosts[node.kingdom];
            node.kingdom_level_cost = costs && costs[curLevel || 0];
            self._buildTooltip(item);
         }
      });
   },

   _buildTooltip: function(item) {
      var node = this._dataToMenuItemMap[item.attr('id')];

      var data = {
         i18n_data: node.towerData,
         escapeHTML: true
      }

      var description = i18n.t(node.description, data);
      if (node.towerData) {
         if (node.towerData.weapons && node.towerData.weapons.default_weapon) {
            description = tower_defense.getTowerWeaponTooltipContent(node.towerData.weapons.default_weapon);
            var upgrades = node.towerData.weapons.upgrades;
            if (upgrades) {
               radiant.each(upgrades, function(k, v) {
                  description += tower_defense.getTowerWeaponTooltipContent(v.uri, node.towerData.weapons.default_weapon, v.cost);
               });
            }
         }
         if (node.towerData.cost) {
            description += `<div class='towerCost'>${node.towerData.cost}</div>`;
         }
      }
      if (node.requirement_text && item.hasClass('locked')) {
         description = description + '<span class=warn>' + i18n.t(node.requirement_text, {i18n_data: node.towerData}) + '</span>';
      }
      if (node.kingdom) {
         item.off('click.upgrade');
         
         if (node.kingdom_level_cost) {
            var cost = tower_defense.getCostString(node.kingdom_level_cost);
            description += '<span class=warn>' + i18n.t('i18n(tower_defense:ui.game.menu.build_menu.kingdom_level_cost)', {i18n_data: {cost: cost} }) + '</span>';
            item.on('click.upgrade', function(e) {
               if (e.altKey) {
                  radiant.call('tower_defense:unlock_kingdom_command', node.kingdom)
                     .done(function() {
                        // we successfully upgraded
                     })
                     .fail(function(response) {
                        if (response.message) {
                           $(document).trigger('td_player_alert', {
                              message: i18n.t(response.message, response)
                           });
                        }
                     });
                  return false;
               }
            });
         }
      }
      if (item.warning_text) {
         description = description + '<span class=warn>' + i18n.t(item.warning_text) + '</span>';
      };
      App.hotkeyManager.makeTooltipWithHotkeys(item, i18n.t(node.name, data), i18n.t(description, data));
   }
});