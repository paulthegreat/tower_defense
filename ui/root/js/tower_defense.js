// helper functions that may be used in multiple places, e.g., start menu and unit frame

var tower_defense = {
   getCostString: function(costTable, towerGoldCostMultiplier) {
      var cost = '';
      radiant.each(costTable, function(resource, amount) {
         if (resource == 'gold') {
            amount = Math.ceil(amount * (towerGoldCostMultiplier || 1));
         }
         cost += `<span class='costValue'>${amount}</span><img class='inlineImg ${resource}'> `;
      });
      return cost;
   },

   getTowerWeaponTooltipContent: function(weapon, upgradeCost) {
      var weaponData = App.catalog.getCatalogData(weapon);
      var passthroughAttack = false;

      var s = '';
      if (weaponData.display_name && upgradeCost) {
         s += `<div class="weaponUpgrade"><h3>${i18n.t(weaponData.display_name)}</h3>` +
               `<div class="weaponUpgradeCost">${tower_defense.getCostString(upgradeCost)}</div></div>`;
      }
      s += (weaponData.description ? `<div class="weaponDescription">${i18n.t(weaponData.description)}</div>` : '') +
         '<table class="weaponDetails"><col class="titleCol"><col class="valueCol">';

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

      var b = weaponData.injected_buffs;
      if (b && b.length > 0) {
         s += tower_defense._getLine(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.buffs_title'), tower_defense._getBuffs(b));
      }

      var a = weaponData.tower_weapon_attack_info;
      if (a) {
         if (a.base_damage) {
            a.damage_type = a.damage_type || 'physical';
            s += tower_defense._getLine(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.damage_title'),
               i18n.t(a.is_percentage ? 'tower_defense:ui.game.tooltips.tower_weapons.percentage_damage' :
                  'tower_defense:ui.game.tooltips.tower_weapons.damage', a) +
               tower_defense._getAttacks(a.attack_times && a.attack_times.length || 1, a.num_targets || 1));
         }
         if (a.cooldown) {
            s += tower_defense._getLine(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.cooldown_title'),
               i18n.t('tower_defense:ui.game.tooltips.tower_weapons.cooldown', {cooldown: a.cooldown * 0.001}));
         }
      }

      var d = weaponData.inflictable_debuffs;
      if (d && d.length > 0) {
         s += tower_defense._getLine(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.debuffs_title'), tower_defense._getBuffs(d));
      }

      var aoe = t && a && a.aoe;
      if (aoe) {
         s += tower_defense._getLine(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.aoe_range_title'),
            i18n.t('tower_defense:ui.game.tooltips.tower_weapons.range_square', aoe) +
            tower_defense._getAttackTypes(t.attacks_ground || aoe.hits_ground_and_air, t.attacks_air || aoe.hits_ground_and_air));
         var secondary_damage = aoe.base_damage != null ? aoe.base_damage : a.base_damage;
         if (secondary_damage != null) {
            aoe.damage_type = aoe.damage_type || 'physical';
            s += tower_defense._getLine(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.aoe_damage_title'),
               i18n.t('tower_defense:ui.game.tooltips.tower_weapons.damage', {base_damage: secondary_damage}));
         }
      }

      var sec = a && a.secondary_attack;
      if (sec) {
         s += tower_defense._getLine(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.secondary_range_title'),
            i18n.t('tower_defense:ui.game.tooltips.tower_weapons.range_square', sec) +
            tower_defense._getAttackTypes(t.attacks_ground || sec.hits_ground_and_air, t.attacks_air || sec.hits_ground_and_air));
         s += tower_defense._getLine(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.secondary_attacks_title'),
            tower_defense._getAttacks(sec.num_attacks || 1, sec.num_targets || 1, sec.max_attacks_per_target || 1));
         if (sec.damage_multiplier) {
            s += tower_defense._getLine(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.secondary_dmg_mult_title'), 
               i18n.t('tower_defense:ui.game.tooltips.tower_weapons.secondary_dmg_mult', sec));
         }
      }

      var beam = a && a.beam;
      if (beam) {
         passthroughAttack = passthroughAttack || beam.passthrough_attack;
         if (beam.attack_times && beam.attack_times.length > 1) {
            s += tower_defense._getLine(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.beam_attacks_title'), beam.attack_times.length);
         }
      }

      var proj = a && a.projectile;
      if (proj) {
         passthroughAttack = passthroughAttack || proj.passthrough_attack;
      }

      var gp = a && a.ground_presence;
      if (gp) {
         passthroughAttack = passthroughAttack || gp.passthrough_attack;
         var gp_entity_data = App.catalog.getCatalogData(gp.uri);
         s += tower_defense._getLine(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.ground_presence_title'), i18n.t(gp_entity_data.display_name));
         s += tower_defense._getLine(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.range_title'),
            i18n.t('tower_defense:ui.game.tooltips.tower_weapons.range_square', gp), true);
         
         var i18n_data = {duration: gp.duration * 0.001, period: (gp.period || 1000) * 0.001};
         s += tower_defense._getLine(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.gp_duration_title'),
            i18n.t(gp.other_times || gp.every_time ? 'tower_defense:ui.game.tooltips.tower_weapons.gp_duration_and_period' :
            'tower_defense:ui.game.tooltips.tower_weapons.gp_duration', i18n_data), true);

         ['first_time', 'other_times', 'every_time'].forEach(instance => {
            if (gp[instance]) {
               if (gp[instance].attack_info) {
                  s += tower_defense._getLine(i18n.t(`tower_defense:ui.game.tooltips.tower_weapons.gp_${instance}_damage_title`),
                     i18n.t('tower_defense:ui.game.tooltips.tower_weapons.damage', gp[instance].attack_info), true);
               }
               if (gp[instance].expanded_buffs) {
                  s += tower_defense._getLine(i18n.t(`tower_defense:ui.game.tooltips.tower_weapons.gp_${instance}_debuffs_title`),
                     tower_defense._getBuffs(gp[instance].expanded_buffs), true);
               }
            }
         });
      }

      s += '</table>';

      if (passthroughAttack) {
         s += `<div class='passthroughAttack'>${i18n.t('tower_defense:ui.game.tooltips.tower_weapons.passthrough_attack')}</div>`;
      }

      return s;
   },

   _getLine: function(title, content, indent) {
      return `<tr><td class='entryTitle${indent ? ' indented' : ''}'>${title}</td><td class='entryValue'>${content}</td></tr>`;
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
               (num_targets == 999 ? i18n.t('tower_defense:ui.game.tooltips.tower_weapons.passive_aoe') :
               (num_targets > 1 ? i18n.t('tower_defense:ui.game.tooltips.tower_weapons.num_targets', {num_targets: num_targets}) : ''));
      }
      else {
         return (num_attacks > 1 ? i18n.t('tower_defense:ui.game.tooltips.tower_weapons.num_attacks', {num_attacks: num_attacks}) : '') +
            (num_targets == 999 ? i18n.t('tower_defense:ui.game.tooltips.tower_weapons.passive_aoe') :
            (num_targets > 1 ? i18n.t('tower_defense:ui.game.tooltips.tower_weapons.num_targets', {num_targets: num_targets}) : ''));
      }
   },

   _getBuffs: function(buffs) {
      var s = '';

      var wasText = false;
      buffs.forEach(buff => {
         if (buff.icon) {
            s += ` <img class='inlineImg buff' src="${buff.icon}">`;
            wasText = false;
         }
         else {
            s += (wasText ? ', ' : ' ') + i18n.t(buff.display_name);
            wasText = true;
         }
      });

      return s;
   }
};
