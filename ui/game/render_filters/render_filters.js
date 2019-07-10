$(document).ready(function () {
   App.waitForGameLoad().then(() => {
      App.gameView.addView(App.TowerDefenseRenderFilters);
   });
});

App.TowerDefenseRenderFilters = App.View.extend({
	templateName: 'renderFilters',
	uriProperty: 'model',
   closeOnEsc: false,

   init: function () {
      var self = this;
      self._super();

      radiant.call('tower_defense:get_render_filters_enabled_command')
         .done(function(response) {
            if (self.isDestroyed || self.isDestroying) {
               return;
            }
            self._setFiltersEnabled(response.enabled);
         });

      $.getJSON('/tower_defense/data/render_filters/render_filters.json', function(data) {
         if (self.isDestroyed || self.isDestroying) {
            return;
         }
         self._allFilters = data.render_filters;

         radiant.call('tower_defense:get_render_filters_command')
            .done(function(response) {
               if (self.isDestroyed || self.isDestroying) {
                  return;
               }
               tower_defense.getAllBuffs(function() {
                  if (self.isDestroyed || self.isDestroying) {
                     return;
                  }
                  self._setRenderFilters(response.filters);
               });
            });
      });
   },

	didInsertElement: function () {
      var self = this;
      
      self.donateAmount = 0;

		self.$('#enableRenderFilters').on('click', function(e) {
         self._setFiltersEnabled(!self._filtersEnabled);
         radiant.call('tower_defense:set_render_filters_enabled_command', self._filtersEnabled);
      });

      self.$('#selectAll').on('click', function(e) {
         self._checkClearAllRenderFilters(true);
      });
      self.$('#selectNone').on('click', function(e) {
         self._checkClearAllRenderFilters(false);
      });
      
      self.$().on('click', `.renderFilter`, function(e) {
         self._toggleRenderFilter($(this).attr('data-filter'));
      });
	},

	willDestroyElement: function () {
		var self = this;

      self.$('.button').off('click');

		self._super();
   },
   
   _setFiltersEnabled: function(enabled) {
      var self = this;
      self._filtersEnabled = enabled;
      self.set('enableFiltersClass', 'button' + (enabled ? '' : ' inactive'));
   },

   _setRenderFilters: function(activeFilters) {
      var self = this;

      if (!Array.isArray(activeFilters)) {
         activeFilters = [];
      }

      var filters = [];
      self._renderFilters = [];
      radiant.each(self._allFilters, function(name, filter) {
         var icon = filter.icon;
         var colorTbl = filter.color;
         if (filter.buffs && filter.buffs.length > 0) {
            var buff = tower_defense.getBuff(filter.buffs[0]);
            icon = icon || buff.icon;
            colorTbl = buff.color;
         }
         filter.color = self._getColorString(colorTbl);

         var active = activeFilters.includes(name);
         if (active) {
            self._renderFilters.push(name);
         }
         filters.push({
            name: name,
            class: 'renderFilter button' + (active ? '' : ' inactive'),
            icon: icon,
            color: filter.color,
            active: active,
            ui_ordinal: filter.ui_ordinal || 0
         });
      });

      filters.sort((a, b) => a.ui_ordinal < b.ui_ordinal ? -1 : (a.ui_ordinal > b.ui_ordinal ? 1 : 0));

      self.set('renderFilters', filters);
      Ember.run.scheduleOnce('afterRender', this, '_applyTooltips');
   },

   _getColorString: function(colorTbl) {
      if (colorTbl) {
         var r = colorTbl.r || colorTbl.x || 0;
         var g = colorTbl.g || colorTbl.y || 0;
         var b = colorTbl.b || colorTbl.z || 0;
         return `rgba(${r},${g},${b},1)`;
      }

      return 'rgba(0,0,0,1)';
   },

   _applyTooltips: function() {
      var self = this;

      App.tooltipHelper.createDynamicTooltip(self.$('#enableRenderFilters'), function() {
         var localStr = 'tower_defense:ui.game.renderFilters.' + (self._filtersEnabled ? 'disable' : 'enable') + '.';
         return $(App.tooltipHelper.createTooltip(i18n.t(localStr + 'display_name'), i18n.t(localStr + 'description')));
      });
      
      var ttStr = `tower_defense:ui.game.renderFilters.select_all.`;
      App.tooltipHelper.attachTooltipster(self.$('#selectAll'),
         $(App.tooltipHelper.createTooltip(i18n.t(ttStr + 'display_name'), i18n.t(ttStr + 'description'))));
      ttStr = `tower_defense:ui.game.renderFilters.select_none.`;
      App.tooltipHelper.attachTooltipster(self.$('#selectNone'),
         $(App.tooltipHelper.createTooltip(i18n.t(ttStr + 'display_name'), i18n.t(ttStr + 'description'))));

      radiant.each(self._allFilters, function(name, filter) {
         var btn = self.$(`.renderFilter[data-filter="${name}"]`);
         if (btn && btn.length > 0) {
            if (self._renderFilters.includes(name)) {
               btn.find('img').css({outlineColor: filter.color});
            }
            btn.tooltipster({
               content: $(App.tooltipHelper.createTooltip(i18n.t(filter.display_name), i18n.t(filter.description)))
            });
         }
      });
   },

   _toggleRenderFilter: function(name) {
      var self = this;

      var filters = self.get('renderFilters');
      filters.forEach(filter => {
         if (filter.name == name) {
            var active = !filter.active;
            var index = self._renderFilters.indexOf(name);
            if (index >= 0) {
               self._renderFilters.splice(index, 1);
            }
            else {
               self._renderFilters.push(name);
            }
            var f = self._setFilterActive(filter, active);
            Ember.run.scheduleOnce('afterRender', () => f());
         }
      });

      radiant.call('tower_defense:set_render_filters_command', self._renderFilters);
   },

   _checkClearAllRenderFilters: function(active) {
      var self = this;

      var filters = self.get('renderFilters');
      self._renderFilters = [];
      var f = [];
      filters.forEach(filter => {
         f.push(self._setFilterActive(filter, active));
         if (active) {
            self._renderFilters.push(filter.name);
         }
      });

      Ember.run.scheduleOnce('afterRender', function() {
         f.forEach(fn => fn());
      });

      radiant.call('tower_defense:set_render_filters_command', self._renderFilters);
   },

   _setFilterActive: function(filter, active) {
      var self = this;

      Ember.set(filter, 'active', active);
      Ember.set(filter, 'class', 'renderFilter button' + (active ? '' : ' inactive'));
      return function() {
         var btn = self.$(`.renderFilter[data-filter="${filter.name}"]`);
         if (btn && btn.length > 0) {
            btn.find('img').css({outlineColor: active ? filter.color : ''});
         }
      };
   }
});
