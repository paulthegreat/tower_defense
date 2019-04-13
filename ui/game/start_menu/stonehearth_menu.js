$.widget( "stonehearth.stonehearthMenu", $.stonehearth.stonehearthMenu, {
   _buildTooltip: function(item) {
      var node = this._dataToMenuItemMap[item.attr('id')];

      var description = i18n.t(node.description);
      if (node.required_job_text && item.hasClass('locked')) {
         description = description + '<span class=warn>' + i18n.t(node.required_job_text) + '</span>';
      };
      if (item.warning_text) {
         description = description + '<span class=warn>' + i18n.t(item.warning_text) + '</span>';
      };

      var data = {
         i18n_data: node.towerData,
         escapeHTML: true
      }
      App.hotkeyManager.makeTooltipWithHotkeys(item, i18n.t(node.name, data), i18n.t(description, data));
   }
});