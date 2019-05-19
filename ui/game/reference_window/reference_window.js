var lastTabPage = 'buffsTab';

App.TowerDefenseReferenceView = App.View.extend({
   templateName: 'referenceWindow',
   closeOnEsc: true,

   init: function() {
      var self = this;
      self._super();
   },

   dismiss: function () {
      this.hide();
   },

   destroy: function() {
      var self = this;
      self._super();
   },

   willDestroyElement: function() {
      this.tabs.off('click');

      this.buffGrid.togglegrid('destroy');
      this.$().find('.tooltipstered').tooltipster('destroy');
      this._super();
   },

   didInsertElement: function() {
      this._super();
      var self = this;

      this.$().draggable({ handle: '.title' });

      this.buffGrid = this.$('#buffGrid');

      this.tabs = this.$('.tab');

      this.tabs.click(function() {
         lastTabPage = $(this).attr('tabPage');
      });

      this.buffGrid.togglegrid();

      // Resume on last selected tab
      self._resumeLastTab();

      tower_defense.getAllBuffs(function(allBuffs) {
         var byCategory = {};
         var categoryArr = [];
         radiant.each(allBuffs, function(uri, buff) {
            var category = buff.category;
            // we only care about properly categorized buffs that are visible to the player
            if (category && !buff.invisible_to_player) {
               var buffsByCategory = byCategory[category];
               if (!buffsByCategory) {
                  buffsByCategory = {
                     category: category,
                     categoryName: `i18n(tower_defense:ui.game.referenceWindow.buffs.categories.${category})`,
                     buffs: []
                  };
                  byCategory[category] = buffsByCategory;
                  categoryArr.push(buffsByCategory);
               }
               buffsByCategory.buffs.push(buff);
            }
         });
         categoryArr.forEach(categoryBuffs => {
            categoryBuffs.buffs.sort(tower_defense.buffSorter);
         });

         self._allBuffs = allBuffs;
         self.set('buffsByCategory', categoryArr);
         Ember.run.scheduleOnce('afterRender', self, '_updateTabs');
         Ember.run.scheduleOnce('afterRender', self, '_updateTooltips');
      });
   },

   _updateTooltips: function() {
      var self = this;
      var buffs = self.$('.buff');
      if (buffs) {
         buffs.each(function() {
            var element = $( this );
            var buff = self._allBuffs[element.attr('uri')];
            if (buff) {
               App.tooltipHelper.attachTooltipster(element,
                  $(App.tooltipHelper.createTooltip(i18n.t(buff.display_name), i18n.t(buff.description)))
               );
            }
         });
      }
   },

   _updateTabs: function() {
      var self = this;

      var buffsTabElement = self.$('div[tabPage=buffsTab]');
      if (!buffsTabElement) {  // Too early or too late.
         return;
      }

      buffsTabElement.show();
      self._resumeLastTab();
   },

   _resumeLastTab: function() {
      this.$('div[tabPage]').removeClass('active');
      this.$('.tabPage').hide();

      var tab = this.$('div[tabPage=' + lastTabPage + ']');
      tab.addClass('active');

      var tabPage = this.$('#' + lastTabPage);
      tabPage.show();
   },
});
