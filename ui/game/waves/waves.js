App.TowerDefenseWaveView = App.View.extend({
   templateName: 'wavesWindow',
   closeOnEsc: true,

   init: function() {
      var self = this;
      self._super();
   },

   dismiss: function () {
      this.hide();
   },

   show: function() {
      this._super();
      Ember.run.scheduleOnce('afterRender', this, '_scrollToCurrentWave');
   },

   destroy: function() {
      var self = this;
      self._super();
      if (this.game_trace) {
         this.game_trace.destroy();
         this.game_trace = null;
      }
   },

   willDestroyElement: function() {
      this.tabs.off('click');

      this.waveGrid.togglegrid('destroy');
      this.$().find('.tooltipstered').tooltipster('destroy');
      this._super();
   },

   didInsertElement: function() {
      this._super();
      var self = this;

      this.$('#wavesWindow').draggable({ handle: '.title' });

      this.waveGrid = this.$('#waveGrid');
      this.waveGrid.togglegrid();

      radiant.call('tower_defense:get_service','game')
         .done(function (o) {
            self.game_trace = radiant.trace(o.result)
               .progress(function (o2) {
                  var prevWave = self._currentWave;
                  self._currentWave = o2.wave;

                  if (!self._waves) {
                     radiant.call_obj('tower_defense.game', 'get_wave_index_command')
                        .done(function (o3) {
                           self._waves = o3.waves;
                           
                           var waves = [];
                           for (var i = 0; i < o3.last_wave; i++) {
                              var wave = o3.waves[i];
                              var waveData = {
                                 data: wave,
                                 index: i + 1,
                                 title: i18n.t('tower_defense:ui.game.wavesWindow.wave_title', {wave: i + 1, title: i18n.t(wave.display_name)}),
                                 content: tower_defense.getWaveDescription(wave)
                              };
                              waveData.classes = self._getWaveClasses(waveData, self._currentWave);

                              waves.push(waveData);
                           }

                           self.set('waves', waves);
                           Ember.run.scheduleOnce('afterRender', self, '_updateTooltips');
                        });
                  }
                  else if (prevWave != self._currentWave) {
                     var waves = self.get('waves');
                     radiant.each(waves, function(i, wave) {
                        Ember.set(wave, 'classes', self._getWaveClasses(wave, self._currentWave));
                     });
                     Ember.run.scheduleOnce('afterRender', self, '_scrollToCurrentWave');
                  }
               });
         });
   },

   _getWaveClasses: function(waveData, currentWave) {
      var s = 'row';

      if (waveData.index < currentWave) {
         s += ' past';
      }
      else if (waveData.index == currentWave) {
         s += ' present';
      }
      else {
         s += ' future';
      }

      if (waveData.data.category) {
         s += ' category ' + waveData.data.category;
      }

      return s;
   },

   _updateTooltips: function() {
      var self = this;
      var waveEls = self.$('.waveData');
      if (waveEls) {
         var waves = self.get('waves');
         waveEls.each(function() {
            var element = $( this );
            var wave = waves[element.attr('data-wave-id') - 1];
            var buffs = element.find('.buff');
            if (wave && wave.data.buffs && buffs.length > 0) {
               buffs.each(function(i) {
                  var buff = wave.data.buffs[i];
                  if (buff) {
                     App.tooltipHelper.attachTooltipster($(this),
                        $(App.tooltipHelper.createTooltip(i18n.t(buff.display_name), i18n.t(buff.description)))
                     );
                  }
               });
            }
         });
         self._scrollToCurrentWave();
      }
   },

   _scrollToCurrentWave: function() {
      var self = this;
      var curWave = self._currentWave || 1;
      var row = self.waveGrid && self.waveGrid.find(`tr[data-wave-id="${curWave}"]`);
      var scrollPos = row && row.position();
      if (scrollPos != null) {
         self.$('.downSection').animate({scrollTop: scrollPos.top - self.waveGrid.position().top}, 500);
      }
   }
});
