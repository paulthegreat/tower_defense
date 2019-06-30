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

      var filters = [];
      self._renderFilters = [];
      radiant.each(self._allFilters, function(name, filter) {
         var icon = filter.icon;
         if (!icon && filter.buffs && filter.buffs.length > 0) {
            var buff = tower_defense.getBuff(filter.buffs[0]);
            icon = buff.icon;
         }
         var active = activeFilters.includes(name);
         if (active) {
            self._renderFilters.push(name);
         }
         filters.push({
            name: name,
            class: 'renderFilter button' + (active ? '' : ' inactive'),
            icon: icon,
            active: active
         });
      });

      self.set('renderFilters', filters);
      Ember.run.scheduleOnce('afterRender', this, '_applyTooltips');
   },

   _applyTooltips: function() {
      var self = this;

      App.tooltipHelper.createDynamicTooltip(self.$('#enableRenderFilters'), function() {
         var localStr = 'tower_defense:ui.game.renderFilters.' + (self._filtersEnabled ? 'disable' : 'enable') + '.';
         return $(App.tooltipHelper.createTooltip(i18n.t(localStr + 'display_name'), i18n.t(localStr + 'description')));
      });
      radiant.each(self._allFilters, function(name, filter) {
         var btn = self.$(`.renderFilter[data-filter="${name}"]`);
         if (btn && btn.length > 0) {
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
            Ember.set(filter, 'active', active);
            Ember.set(filter, 'class', 'renderFilter button' + (active ? '' : ' inactive'));
         }
      });

      radiant.call('tower_defense:set_render_filters_command', self._renderFilters);
   }
});
