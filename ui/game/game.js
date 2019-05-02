App.StonehearthGameUiView.reopen({
   addCompleteViews: function() {
      this.views.complete = [
         "StonehearthCalendarView",
         'StonehearthStartMenuView',
         'StonehearthTaskManagerView',
         'StonehearthGameSpeedWidget',
         'StonehearthUnitFrameView',
         'StonehearthMpStatusTextWidget',
         'StonehearthChatButtonView',
         'StonehearthOffscreenSignalIndicatorWidget',
         'StonehearthTitanstormView',
      ];
      this._addViews(this.views.complete);

      // Preconstruct these views as well
      // Wait until a delay period after start menu load
      // so that we can offset some of the load time until later
      App.waitForStartMenuLoad().then(() => {
         setTimeout(() => {
            App.stonehearthClient.showSettings(true); // true for hide
            App.stonehearthClient.showSaveMenu(true);
            App.stonehearthClient.showMultiplayerMenu(true);
         }, 100);
      });
   }
});
