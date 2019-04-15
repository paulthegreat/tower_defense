$.widget( "stonehearth.stonehearthMenu", $.stonehearth.stonehearthMenu, {
   _addItems: function(nodes, parentId, name, depth) {
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

      // add a special background div for the root group
      if (depth == 0) {
         el.append('<div class=background></div>');
      }

      $.each(nodes, function(key, node) {
         self._dataToMenuItemMap[key] = node;

         if (self.options.shouldHide) {
            if (self.options.shouldHide(key, node)) {
               return true; // return true to continue, because jquery.
            }
         }

         var item = $('<div>')
                     .attr('id', key)
                     .attr('hotkey_action', node.hotkey_action || '')
                     .addClass('menuItem')
                     .addClass('button')
                     .addClass(node.class)
                     .appendTo(el);

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
            self._addItems(node.items, key, node.name, depth + 1);
         }
      });

      if (name) {
         $('<div>').html(i18n.t(name))
                   .addClass('header')
                   .appendTo(el);
      }
   },

   unlockItems: function(kingdoms) {
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

         if (node.kingdom && kingdoms[node.kingdom]) {
            item.removeClass('unused');
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
      if (node.requirement_text && item.hasClass('locked')) {
         description = description + '<span class=warn>' + i18n.t(node.requirement_text, {i18n_data: node.towerData}) + '</span>';
      };
      if (item.warning_text) {
         description = description + '<span class=warn>' + i18n.t(item.warning_text) + '</span>';
      };
      App.hotkeyManager.makeTooltipWithHotkeys(item, i18n.t(node.name, data), i18n.t(description, data));
   }
});