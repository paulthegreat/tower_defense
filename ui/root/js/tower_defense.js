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

   getWaveDescription: function(waveData) {
      var s = ''
      if (waveData) {
         if (waveData.monsters) {
            // for each monster, load up basic information about it (image, name, description)
            radiant.each(waveData.monsters, function(uri, info) {
               var monster = App.catalog.getCatalogData(uri);
               if (monster) {
                  s += tower_defense._getMonster(monster, info);
                  radiant.each(info.summons, function(summon_uri, _) {
                     var summon = App.catalog.getCatalogData(summon_uri);
                     s += tower_defense._getMonster(summon, {damage: 1});
                  });
               }
            });
         }

         if (waveData.buffs) {
            s += `<div>${i18n.t('tower_defense:data.waves.monster_buffs') + this._getBuffs(waveData.buffs)}</div>`;
         }
      }
      return s;
   },

   getTowerWeaponTooltipContent: function(weapon, original, upgradeCost) {
      var weaponData = App.catalog.getCatalogData(weapon);
      var passthroughAttack = false;

      if (original) {
         original = App.catalog.getCatalogData(original);
      }

      var s = '';
      if (weaponData.display_name && upgradeCost) {
         s += `<div class="weaponUpgrade"><h3>${i18n.t('tower_defense:ui.game.tooltips.tower_weapons.upgrade_name', weaponData)}</h3>` +
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
            a.damage_value = this._getDamageString(a.base_damage);
            s += this._getLine(this._compareAndGetDifferenceSpan(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.damage_title'),
                  weaponData, original, ['tower_weapon_attack_info.base_damage', 'tower_weapon_attack_info.damage_type',
                     'tower_weapon_attack_info.attack_times.length', 'tower_weapon_attack_info.num_targets']),
               i18n.t(a.is_percentage ? 'tower_defense:ui.game.tooltips.tower_weapons.percentage_damage' :
                  'tower_defense:ui.game.tooltips.tower_weapons.damage', a) +
               this._getAttacks(a.attack_times && a.attack_times.length || 1, a.num_targets || 1));
            
            a.accuracy = a.accuracy == null ? 1 : a.accuracy;
            var original_accuracy = interpretPropertyString('tower_weapon_attack_info.accuracy', original);
            if (original_accuracy == null) {
               original_accuracy = 1;
            }
            if (a.accuracy != 1 || original_accuracy != 1) {
               s += this._getLine(this._getDifferenceSpan(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.accuracy_title'),
                     a.accuracy == original_accuracy),
                  i18n.t('tower_defense:ui.game.tooltips.tower_weapons.accuracy', {accuracy: a.accuracy * 100}));
            }
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
         var secondary_damage = aoe.base_damage != null ? aoe.base_damage : a.damage_value;
         if (secondary_damage != null) {
            aoe.damage_type = aoe.damage_type || a.damage_type || 'physical';
            aoe.damage_value = this._getDamageString(secondary_damage);
            var original_damage = original && original.tower_weapon_attack_info && ((original.tower_weapon_attack_info.aoe && original.tower_weapon_attack_info.aoe.base_damage) != null ?
                  original.tower_weapon_attack_info.aoe.base_damage : original.tower_weapon_attack_info.base_damage);
            var original_damage_value = original_damage != null && this._getDamageString(original_damage);

            s += this._getLine(this._getDifferenceSpan(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.aoe_damage_title'),
                  this._compareProperties(weaponData, original, ['tower_weapon_attack_info.aoe.damage_type']) &&
                  !original || (aoe.damage_value == original_damage_value)),
               i18n.t('tower_defense:ui.game.tooltips.tower_weapons.damage', {damage_value: aoe.damage_value, damage_type: aoe.damage_value != '0' && aoe.damage_type}));
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
               !(gp.other_times || gp.every_time) || !original ||
               (original.tower_weapon_attack_info && original.tower_weapon_attack_info.ground_presence &&
                  (original.tower_weapon_attack_info.ground_presence.other_times || original.tower_weapon_attack_info.ground_presence.every_time))),
            i18n.t(gp.other_times || gp.every_time ? 'tower_defense:ui.game.tooltips.tower_weapons.gp_duration_and_period' :
               'tower_defense:ui.game.tooltips.tower_weapons.gp_duration', i18n_data), true);

         ['first_time', 'other_times', 'every_time'].forEach(instance => {
            if (gp[instance]) {
               var gpa = gp[instance].attack_info;
               if (gpa) {
                  gpa.damage_value = this._getDamageString(gpa.base_damage);
                  s += this._getLine(this._compareAndGetDifferenceSpan(i18n.t(`tower_defense:ui.game.tooltips.tower_weapons.gp_${instance}_damage_title`),
                        weaponData, original, [`tower_weapon_attack_info.ground_presence.${instance}.attack_info`]),
                     i18n.t('tower_defense:ui.game.tooltips.tower_weapons.damage', gpa), true);

                  var accuracy = gpa.accuracy == null ? 1 : gpa.accuracy;
                  var original_accuracy = interpretPropertyString(`tower_weapon_attack_info.ground_presence.${instance}.attack_info.accuracy`, original);
                  if (original_accuracy == null) {
                     original_accuracy = 1;
                  }
                  if (accuracy != 1 || original_accuracy != 1) {
                     s += this._getLine(this._getDifferenceSpan(i18n.t('tower_defense:ui.game.tooltips.tower_weapons.accuracy_title'),
                           accuracy == original_accuracy),
                        i18n.t('tower_defense:ui.game.tooltips.tower_weapons.accuracy', {accuracy: accuracy * 100}), true);
                  }
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

   addTowersByBuffs: function(towersByBuff, uri, tower) {
      var self = this;
      
      var weaponData = App.catalog.getCatalogData(tower.weapons.default_weapon);
      var t = weaponData.tower_weapon_targeting;
      var defWpn = {
         uri: uri,
         weapon: tower.weapons.default_weapon,
         is_default: true,
         level: tower.level,
         required_kingdoms: tower.required_kingdoms,
         targets: t && self._getAttackTypes(t.attacks_ground, t.attacks_air)
      }

      var buffs = tower_defense._getWeaponBuffs(weaponData);
      buffs.forEach(buff => {
         var towers = towersByBuff[buff];
         if (!towers) {
            towers = [];
            towersByBuff[buff] = towers;
         }
         towers.push(defWpn);
      });

      var upgrades = tower.weapons.upgrades;
      if (upgrades) {
         radiant.each(upgrades, function(k, v) {
            var upgradeWeaponData = App.catalog.getCatalogData(v.uri);
            var uT = upgradeWeaponData.tower_weapon_targeting;
            var upWpn = {
               uri: uri,
               weapon: v.uri,
               level: tower.level,
               required_kingdoms: tower.required_kingdoms,
               targets: uT && self._getAttackTypes(uT.attacks_ground, uT.attacks_air)
            }

            var upgradeBuffs = tower_defense._getWeaponBuffs(upgradeWeaponData);
            upgradeBuffs.forEach(buff => {
               // only add a reference if the base tower wasn't already giving this buff, or if it had different targeting
               if (!buffs.includes(buff) || defWpn.targets != upWpn.targets) {
                  var towers = towersByBuff[buff];
                  if (!towers) {
                     towers = [];
                     towersByBuff[buff] = towers;
                  }
                  towers.push(upWpn);
               }
            });
         });
      }
   },

   _getWeaponBuffs: function(weaponData) {
      var buffs = [];
      
      [weaponData.injected_buffs, weaponData.inflictable_debuffs].forEach(b => {
         if (b && b.length > 0) {
            buffs = buffs.concat(this._getBuffUris(b));
         }   
      });

      var gp = weaponData.tower_weapon_attack_info && weaponData.tower_weapon_attack_info.ground_presence;
      if (gp) {
         ['first_time', 'other_times', 'every_time'].forEach(instance => {
            if (gp[instance] && gp[instance].expanded_buffs) {
               buffs = buffs.concat(this._getBuffUris(gp[instance].expanded_buffs));
            }
         });
      }

      return buffs;
   },

   setTowersByBuff: function(towersByBuff) {
      radiant.each(towersByBuff, function(buff, towers) {
         towers.sort((a, b) => {
            var result = a.required_kingdoms.localeCompare(b.required_kingdoms);
            if (result == 0) {
               result = a.level - b.level;
            }
            if (result == 0) {
               result = a.weapon.localeCompare(b.weapon);
            }
            return result;
         })
      });
      this.towersByBuff = towersByBuff;
   },

   getTowersByBuff: function(buff) {
      var towers = this.towersByBuff && this.towersByBuff[buff];
      return towers;
   },

   getFormattedTowersByBuff: function(buff) {
      var towers = this.getTowersByBuff(buff);
      if (towers && towers.length > 0) {
         var s = `<div class='appliedByTowers'>${i18n.t('tower_defense:ui.game.tooltips.buffs.applied_by')}<table class='towerList'>`;
         // add title row
         s += `<tr class='titleRow'><td>${i18n.t('tower_defense:ui.game.tooltips.buffs.towers_table.name_title')}</td>` +
            `<td>${i18n.t('tower_defense:ui.game.tooltips.buffs.towers_table.upgrade_title')}</td>` +
            `<td>${i18n.t('tower_defense:ui.game.tooltips.buffs.towers_table.level_title')}</td>` +
            `<td>${i18n.t('tower_defense:ui.game.tooltips.buffs.towers_table.required_kingdoms_title')}</td>` +
            `<td>${i18n.t('tower_defense:ui.game.tooltips.buffs.towers_table.targets_title')}</td></tr>`;

         towers.forEach(tower => {
            var name = i18n.t(App.catalog.getCatalogData(tower.uri).display_name);
            var weaponName = tower.is_default ? '' : i18n.t(App.catalog.getCatalogData(tower.weapon).display_name);
            s += `<tr class='towerRow'><td>${name}</td><td>${weaponName}</td><td>${tower.level}</td>` +
               `<td>${tower.required_kingdoms}</td><td>${tower.targets}</td></tr>`;
         });
         s += '</table></div>';
         return s;
      }
      return '';
   },

   _getBuffUris: function(buffs) {
      var uris = [];
      buffs.forEach(buff => {
         uris.push(buff.uri);
      });
      return uris;
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

   _isDamageEqual: function(d1, d2) {
      if (Array.isArray(d1) && Array.isArray(d2)) {
         return d1[0] == d2[0] && d1[1] == d2[1];
      }
      else {
         return d1 == d2;
      }
   },

   _getDamageString: function(damage) {
      return Array.isArray(damage) ? damage[0] + '–' + damage[1] : damage.toString();
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

   _getMonster: function(monster, info) {
      var s = '';

      s += `<table class='monster'><tr><td class='monsterPortrait'><img src="${monster.icon}"></td><td class='monsterContent'>`

      if (monster.display_name) {
         s += `<div class='monsterName'>${i18n.t(monster.display_name)} (${info.count ? 'x' + info.count : i18n.t('tower_defense:data.waves.summoned_monster')})</div>`;
      }
      if (monster.description) {
         var sDmg = info.damage ? `<div class='monsterDamage'>${i18n.t('tower_defense:data.waves.monster_damage', {damage: info.damage})}</div>` : '';
         s += `<div class='monsterDescription'>${i18n.t(monster.description)}${sDmg}</div>`;
      }
      // currently this isn't used at all - buffs aren't added to catalog data for monsters, only tower weapons
      if (monster.buffs) {
         s += `<div>${this._getBuffs(monster.buffs)}</div>`;
      }

      s += '</td></tr></table>';

      return s;
   },

   _getBuffs: function(buffs) {
      var s = '';

      var wasText = false;
      buffs.sort(this.buffSorter);
      buffs.forEach(buff => {
         if (buff.icon) {
            for (var i = 0; i < (buff.stacks || 1); i++) {
               s += ` <img class='inlineImg buff' src="${buff.icon}">`;
               if (buff.chance != null && buff.chance != 1) {
                  s += `(${Math.floor(buff.chance * 100)}%) `;
               }
            }
            wasText = false;
         }
         else {
            s += (wasText ? ', ' : ' ') + i18n.t(buff.display_name);
            if (buff.chance != null && buff.chance != 1) {
               s += `(${Math.floor(buff.chance * 100)}%) `;
            }
            wasText = true;
         }
      });

      return s;
   },

   getBuff: function(uri) {
      return this._all_buffs && this._all_buffs[uri];
   },

   getAllBuffs: function(callbackFn) {
      if (tower_defense._all_buffs) {
         callbackFn(tower_defense._all_buffs);
      }
      else {
         radiant.call('tower_defense:get_all_buffs')
            .done(function(o) {
               if (!tower_defense._all_buffs) {
                  tower_defense._all_buffs = o.buffs;
               }
               callbackFn(tower_defense._all_buffs);
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
