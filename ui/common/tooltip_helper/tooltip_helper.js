App.RootView.reopen({
   init: function() {
      this._super();

      App.tooltipHelper.createBuffTooltip = function(buff) {
         var calendarView = App.gameView.getView(App.StonehearthCalendarView);
         var remainingDuration = null;
         if (calendarView && buff.expire_time) {
            var timeRemaining = calendarView.getRemainingRealTime(buff.expire_time, 1);
            remainingDuration = i18n.t('tower_defense:data.buffs.buff_duration_seconds', {seconds: timeRemaining});
         }
      
         return App.tooltipHelper.createTooltip(i18n.t(buff.display_name), i18n.t(buff.description), remainingDuration);
      };
   }
});
