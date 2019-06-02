// helper functions that may be used in multiple places, e.g., start menu and unit frame

// spiegg's solution here: https://stackoverflow.com/questions/6491463/accessing-nested-javascript-objects-with-string-key
function interpretPropertyString(s, obj) {
   if (obj == null) {
      return null;
   }
   var properties = Array.isArray(s) ? s : s.split('.')
   return properties.reduce((prev, curr) => prev && prev[curr], obj)
}

// compare the values; if they're arrays, compare the contents, ignoring order (doesn't handle duplicates properly, but fine for this)
function arePropertiesEqual(p1, p2) {
   if (Array.isArray(p1) && Array.isArray(p2)) {
      if (p1.length != p2.length) {
         return false;
      }

      for (var i = 0; i < p1.length; i++) {
         var found = false;
         for (var j = 0; j < p2.length; j++) {
            if (arePropertiesEqual(p1[i], p2[j])) {
               found = true;
               break;
            }
         }

         if (!found) {
            return false;
         }
      }

      return true;
   }
   else if (typeof p1 == 'object' && typeof p2 == 'object') {
      var areEqual = (p1 != null);
      if (areEqual) {
         radiant.each(p1, function (k, v) {
            if (!areEqual) {
               return;
            }
            areEqual = arePropertiesEqual(v, p2 && p2[k]);
         });
      }

      return areEqual;
   }

   return p1 == p2;
}

var tower_defense = {
   _all_buffs: null,

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

   getTowerWeaponTooltipContent: function(weapon, original, upgradeCost) {
      var weaponData = App.catalog.getCatalogData(weapon);
      var passthroughAttack = false;

      if (original) {
         original = App.catalog.getCatalogData(original);
      }

      var s = '';
      if (weaponData.display_name && upgradeCost) {
         s += `<div class="weaponUpgrade"><h3>${i18n.t(weaponData.display_name)}</h3>` +
               `<div class="weaponUpgradeCost">${this.getCostString(upgradeCost)}</div></div>`;
      }
      s += (weaponData.description ? `<div class="weaponDescription">${i18n.t(weaponData.description)}</div>` : '') +
         '<table class="weaponDetails"><col class="titleCol"><col class="valueCol">';

      var t = weaponData.tower_weapon_targeting;
      if (t) {
         s += this._getLine(this._compareAndGetDifferenceSpan(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.range_title'),
               weaponData, original, ['tower_weapon_targeting.type', 'tower_weapon_targeting.radius', 'tower_weapon_targeting.region',
                  'tower_weapon_targeting.attacks_ground', 'tower_weapon_targeting.attacks_air',
                  'tower_weapon_targeting.sees_invis', 'tower_weapon_targeting.reveals_invis']),
            (t.type == 'circle' ? i18n.t('tower_defense:ui.game.tooltips.tower_weapons.range_circle', t) :
               i18n.t('tower_defense:ui.game.tooltips.tower_weapons.range_rectangle', {
                  x: t.region.max.x - t.region.min.x,
                  z: t.region.max.z - t.region.min.z
               })) +
            this._getAttackTypes(t.attacks_ground, t.attacks_air) +
            this._getInvisTypes(t.sees_invis, t.reveals_invis));
      }

      var b = weaponData.injected_buffs;
      if (b && b.length > 0) {
         s += this._getLine(this._compareAndGetDifferenceSpan(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.buffs_title'),
               weaponData, original, ['injected_buffs']),
            this._getBuffs(b));
      }

      var a = weaponData.tower_weapon_attack_info;
      if (a) {
         if (a.base_damage) {
            a.damage_type = a.damage_type || 'physical';
            s += this._getLine(this._compareAndGetDifferenceSpan(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.damage_title'),
                  weaponData, original, ['tower_weapon_attack_info.base_damage', 'tower_weapon_attack_info.damage_type',
                     'tower_weapon_attack_info.attack_times.length', 'tower_weapon_attack_info.num_targets']),
               i18n.t(a.is_percentage ? 'tower_defense:ui.game.tooltips.tower_weapons.percentage_damage' :
                  'tower_defense:ui.game.tooltips.tower_weapons.damage', a) +
               this._getAttacks(a.attack_times && a.attack_times.length || 1, a.num_targets || 1));
         }
         if (a.cooldown) {
            s += this._getLine(this._compareAndGetDifferenceSpan(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.cooldown_title'),
                  weaponData, original, ['tower_weapon_attack_info.cooldown']),
               i18n.t('tower_defense:ui.game.tooltips.tower_weapons.cooldown', {cooldown: a.cooldown * 0.001}));
         }
      }

      var d = weaponData.inflictable_debuffs;
      if (d && d.length > 0) {
         s += this._getLine(this._compareAndGetDifferenceSpan(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.debuffs_title'),
               weaponData, original, ['inflictable_debuffs']),
            this._getBuffs(d));
      }

      var aoe = t && a && a.aoe;
      if (aoe) {
         s += this._getLine(this._compareAndGetDifferenceSpan(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.aoe_range_title'),
               weaponData, original, ['tower_weapon_attack_info.aoe.range', 'tower_weapon_attack_info.aoe.hits_ground_and_air']),
            i18n.t('tower_defense:ui.game.tooltips.tower_weapons.range_square', aoe) +
            this._getAttackTypes(t.attacks_ground || aoe.hits_ground_and_air, t.attacks_air || aoe.hits_ground_and_air));
         var secondary_damage = aoe.base_damage != null ? aoe.base_damage : a.base_damage;
         if (secondary_damage != null) {
            aoe.damage_type = aoe.damage_type || 'physical';
            s += this._getLine(this._getDifferenceSpan(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.aoe_damage_title'),
                  this._compareProperties(weaponData, original, ['tower_weapon_attack_info.aoe.damage_type']) &&
                  !original || (secondary_damage == (original.tower_weapon_attack_info && ((original.tower_weapon_attack_info.aoe &&
                     original.tower_weapon_attack_info.aoe.base_damage) != null ? original.tower_weapon_attack_info.aoe.base_damage :
                     original.tower_weapon_attack_info.base_damage)))),
               i18n.t('tower_defense:ui.game.tooltips.tower_weapons.damage', {base_damage: secondary_damage}));
         }
      }

      var sec = a && a.secondary_attack;
      if (sec) {
         s += this._getLine(this._compareAndGetDifferenceSpan(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.secondary_range_title'),
               weaponData, original, ['tower_weapon_attack_info.secondary_attack.range', 'tower_weapon_attack_info.secondary_attack.hits_ground_and_air']),
            i18n.t('tower_defense:ui.game.tooltips.tower_weapons.range_square', sec) +
            this._getAttackTypes(t.attacks_ground || sec.hits_ground_and_air, t.attacks_air || sec.hits_ground_and_air));
         s += this._getLine(this._compareAndGetDifferenceSpan(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.secondary_attacks_title'),
               weaponData, original, ['tower_weapon_attack_info.secondary_attack.num_attacks',
                  'tower_weapon_attack_info.secondary_attack.num_targets', 'tower_weapon_attack_info.secondary_attack.max_attacks_per_target']),
            this._getAttacks(sec.num_attacks || 1, sec.num_targets || 1, sec.max_attacks_per_target || 1));
         if (sec.damage_multiplier) {
            s += this._getLine(this._compareAndGetDifferenceSpan(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.secondary_dmg_mult_title'),
                  weaponData, original, ['tower_weapon_attack_info.secondary_attack.damage_multiplier']), 
               i18n.t('tower_defense:ui.game.tooltips.tower_weapons.secondary_dmg_mult', sec));
         }
      }

      var beam = a && a.beam;
      if (beam) {
         passthroughAttack = passthroughAttack || beam.passthrough_attack;
         if (beam.attack_times && beam.attack_times.length > 1) {
            s += this._getLine(this._compareAndGetDifferenceSpan(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.beam_attacks_title'),
               weaponData, original, ['tower_weapon_attack_info.beam.attack_times']), beam.attack_times.length);
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
         s += this._getLine(this._compareAndGetDifferenceSpan(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.ground_presence_title'),
            weaponData, original, ['tower_weapon_attack_info.ground_presence.uri']), i18n.t(gp_entity_data.display_name));
         s += this._getLine(this._compareAndGetDifferenceSpan(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.range_title'),
               weaponData, original, ['tower_weapon_attack_info.ground_presence.range']),
            i18n.t('tower_defense:ui.game.tooltips.tower_weapons.range_square', gp), true);
         
         var i18n_data = {duration: gp.duration * 0.001, period: (gp.period || 1000) * 0.001};
         s += this._getLine(this._getDifferenceSpan(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.gp_duration_title'),
            this._compareProperties(weaponData, original,
               ['tower_weapon_attack_info.ground_presence.duration', 'tower_weapon_attack_info.ground_presence.period']) &&
               !(gp.other_times || gp.every_time) ||
               (original && original.tower_weapon_attack_info && original.tower_weapon_attack_info.ground_presence &&
                  (original.tower_weapon_attack_info.ground_presence.other_times || original.tower_weapon_attack_info.ground_presence.every_time))),
            i18n.t(gp.other_times || gp.every_time ? 'tower_defense:ui.game.tooltips.tower_weapons.gp_duration_and_period' :
               'tower_defense:ui.game.tooltips.tower_weapons.gp_duration', i18n_data), true);

         ['first_time', 'other_times', 'every_time'].forEach(instance => {
            if (gp[instance]) {
               if (gp[instance].attack_info) {
                  s += this._getLine(this._compareAndGetDifferenceSpan(i18n.t(`tower_defense:ui.game.tooltips.tower_weapons.gp_${instance}_damage_title`),
                        weaponData, original, [`tower_weapon_attack_info.ground_presence.${instance}.attack_info`]),
                     i18n.t('tower_defense:ui.game.tooltips.tower_weapons.damage', gp[instance].attack_info), true);
               }
               if (gp[instance].expanded_buffs) {
                  s += this._getLine(this._compareAndGetDifferenceSpan(i18n.t(`tower_defense:ui.game.tooltips.tower_weapons.gp_${instance}_debuffs_title`),
                        weaponData, original, [`tower_weapon_attack_info.ground_presence.${instance}.expanded_buffs`]),
                     this._getBuffs(gp[instance].expanded_buffs), true);
               }
            }
         });
      }

      s += '</table>';

      if (passthroughAttack) {
         s += `<div class='passthroughAttack'>${this._getDifferenceSpan(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.passthrough_attack'),
            !original || (passthroughAttack == (original.tower_weapon_attack_info &&
               ((original.tower_weapon_attack_info.beam && original.tower_weapon_attack_info.beam.passthrough_attack) ||
               (original.tower_weapon_attack_info.projectile && original.tower_weapon_attack_info.projectile.passthrough_attack) ||
               (original.tower_weapon_attack_info.ground_presence && original.tower_weapon_attack_info.ground_presence.passthrough_attack)))))}</div>`;
      }

      return s;
   },

   _getLine: function(title, content, indent) {
      return `<tr><td class='entryTitle${indent ? ' indented' : ''}'>${title}</td><td class='entryValue'>${content}</td></tr>`;
   },

   // returns true if they're equal
   _compareProperties: function(current, original, propertyPaths) {
      if (original) {
         if (propertyPaths) {
            for (var i = 0; i < propertyPaths.length; i++) {
               var propertyPath = propertyPaths[i];
               var areSame = arePropertiesEqual(interpretPropertyString(propertyPath, current), interpretPropertyString(propertyPath, original));
               if (!areSame) {
                  return false;
               }
            }
         }
         else {
            return arePropertiesEqual(current, original);
         }
      }

      return true;
   },

   _compareAndGetDifferenceSpan: function(content, current, original, propertyPaths) {
      return this._getDifferenceSpan(content, this._compareProperties(current, original, propertyPaths));
   },

   _getDifferenceSpan: function(content, areSame) {
      if (!areSame) {
         return `<span class="weaponModified">${content}</span>`;
      }
      return content;
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
      buffs.sort(this.buffSorter);
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
   },

   getAllBuffs: function(callbackFn) {
      if (this._all_buffs) {
         callbackFn(this._all_buffs);
      }
      else {
         radiant.call('tower_defense:get_all_buffs')
            .done(function(o) {
               if (!this._all_buffs) {
                  this._all_buffs = o.buffs;
               }
               callbackFn(this._all_buffs);
            });
      }
   },

   buffSorter: function(a, b) {
      // most significant are the buffs with no duration
      // then organize by category, and within category, by ordinal
      if (!a.default_duration && b.default_duration) {
         return -1;
      }
      else if (a.default_duration && !b.default_duration) {
         return 1;
      }

      if (a.category && !b.category) {
         return -1;
      }
      else if (!a.category && b.category) {
         return 1;
      }
      else if (a.category != b.category) {
         return a.category.localeCompare(b.category);
      }

      if (a.ordinal != null && b.ordinal != null) {
         return a.ordinal - b.ordinal;
      }

      var aUri = a.uri;
      var bUri = b.uri;
      return (aUri && bUri) ? aUri.localeCompare(bUri) : -1;
   }
};
