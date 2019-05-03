// helper functions that may be used in multiple places, e.g., start menu and unit frame

var tower_defense = {
   getTowerWeaponTooltipContent: function(weapon) {
      var weaponData = App.catalog.getCatalogData(weapon);
      var s = (weaponData.description ? i18n.t(weaponData.description) : '') + '<table>';

      var t = weaponData.tower_weapon_targeting;
      if (t) {
         s += tower_defense._getLine(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.range_title'),
            (t.type == 'circle' ? i18n.t('tower_defense:ui.game.tooltips.tower_weapons.range_circle', t) :
            i18n.t('tower_defense:ui.game.tooltips.tower_weapons.range_rectangle', {
               x: t.region.max.x - t.region.min.x,
               z: t.region.max.z - t.region.min.z
            })) +
            tower_defense._getAttackTypes(t.attacks_ground, t.attacks_air) +
            tower_defense._getInvisTypes(t.sees_invis, t.reveals_invis));
      }

      var a = weaponData.tower_weapon_attack_info;
      if (a) {
         if (a.base_damage) {
            a.damage_type = a.damage_type || 'physical';
            s += tower_defense._getLine(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.damage_title'),
               i18n.t('tower_defense:ui.game.tooltips.tower_weapons.damage', a) +
               tower_defense._getAttacks(a.attack_times && a.attack_times.length || 1, a.num_targets || 1));
         }
         if (a.cooldown) {
            s += tower_defense._getLine(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.cooldown_title'), a.cooldown * 0.001);
         }
      }

      s += '</table>';

      return s;
   },

   _getLine: function(title, content) {
      return `<tr><td class='entryTitle'>${title}</td><td class='entryValue'>${content}</td></tr>`;
   },

   _getAttackTypes: function(attacks_ground, attacks_air) {
      return (attacks_ground ? i18n.t('tower_defense:ui.game.tooltips.tower_weapons.attacks_ground') : '') +
            (attacks_air ? i18n.t('tower_defense:ui.game.tooltips.tower_weapons.attacks_air') : '');
   },

   _getInvisTypes: function(sees_invis, reveals_invis) {
      return (reveals_invis ? i18n.t('tower_defense:ui.game.tooltips.tower_weapons.reveals_invis') :
            (sees_invis ? i18n.t('tower_defense:ui.game.tooltips.tower_weapons.sees_invis') : ''));
   },

   _getAttacks: function(num_attacks, num_targets, max_per_target) {
      if (max_per_target) {
         return num_attacks + (max_per_target < num_attacks / 2 ?
               i18n.t('tower_defense:ui.game.tooltips.tower_weapons.max_attacks_per_target', {max_per_target: max_per_target}) : '') +
               (num_targets > 1 ? i18n.t('tower_defense:ui.game.tooltips.tower_weapons.num_targets', {num_targets: num_targets}) : '');
      }
      else {
         return (num_attacks > 1 ? i18n.t('tower_defense:ui.game.tooltips.tower_weapons.num_attacks', {num_attacks: num_attacks}) : '') +
            (num_targets > 1 ? i18n.t('tower_defense:ui.game.tooltips.tower_weapons.num_targets', {num_targets: num_targets}) : '');
      }
   }
};
