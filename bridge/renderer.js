// DRAPLINE CE bridge v2. No save-file writes or added fields in saved objects.
(() => {
  'use strict';
  if (globalThis.__drapCE) return;
  const locks = new Map();
  const params = { grow_hp: 0, str: 2, vit: 3, int: 4, res: 5, agi: 6 };
  const variables = { debt: 130, energy: 127, energy_max: 128, temperament: 381 };
  let expires = 0, applying = false, hooked = false, identity = null, clientId = '';
  const actor = () => globalThis.$gameActors?._data?.[1];
  const isReady = () => Boolean(actor() && globalThis.$gameParty?._actors?.includes(1) &&
    globalThis.$gameVariables && globalThis.SceneManager?._scene &&
    !/Scene_(Boot|Title|Load|Gameover)/.test(SceneManager._scene.constructor.name));
  const locked = key => Date.now() < expires && isReady() && locks.has(key);
  function databaseEntry(key) {
    const match = /^(item|skill)_([1-9]\d*)$/.exec(key);
    if (!match) return null;
    const id = Number(match[2]);
    const data = (match[1] === 'item' ? globalThis.$dataItems : globalThis.$dataSkills)?.[id];
    if (!data || !data.name) throw new Error('Unknown ' + match[1] + ' ID: ' + id);
    return { kind: match[1], id, data };
  }
  function ownedSkillIds() {
    const a = actor();
    return [...new Set([...(a._skills || []), ...(a._hasAbilitySkills || []), ...(a._equipAbilitySkills || [])])]
      .filter(id => Number.isInteger(id) && id > 0 && globalThis.$dataSkills?.[id]);
  }
  function clear() { locks.clear(); expires = 0; }
  function hook() {
    if (hooked || !globalThis.Game_BattlerBase || !globalThis.Game_Party || !globalThis.Game_Variables) return;
    hooked = true;
    const setHp = Game_BattlerBase.prototype.setHp;
    Game_BattlerBase.prototype.setHp = function(value) {
      if (!applying && this === actor()) {
        if (locked('full_hp') && $gameParty.inBattle()) value = this.mhp;
        else if (locked('hp')) value = Math.min(this.mhp, locks.get('hp'));
      }
      return setHp.call(this, value);
    };
    const gainGold = Game_Party.prototype.gainGold;
    Game_Party.prototype.gainGold = function(value) {
      if (!applying && this === globalThis.$gameParty && locked('gold')) {
        this._gold = locks.get('gold');
        return;
      }
      return gainGold.call(this, value);
    };
    const setVariable = Game_Variables.prototype.setValue;
    Game_Variables.prototype.setValue = function(id, value) {
      if (!applying && this === globalThis.$gameVariables) {
        const key = Object.keys(variables).find(k => variables[k] === id);
        if (key && locked(key)) value = locks.get(key);
      }
      return setVariable.call(this, id, value);
    };
    const addParam = Game_BattlerBase.prototype.addParam;
    Game_BattlerBase.prototype.addParam = function(id, value) {
      const key = Object.keys(params).find(k => params[k] === id);
      if (!applying && this === actor() && key && locked(key)) return;
      return addParam.call(this, id, value);
    };
  }
  function read(key) {
    const a = actor();
    const entry = databaseEntry(key);
    if (entry?.kind === 'item') return $gameParty.numItems(entry.data);
    if (entry?.kind === 'skill') return ownedSkillIds().includes(entry.id) ? 1 : 0;
    if (key in params) return a.paramBasePlus(params[key]);
    if (key in variables) return $gameVariables.value(variables[key]);
    if (key === 'gold') return $gameParty.gold();
    if (key === 'hp') return a.hp;
    if (key === 'bp') return a.tp;
    if (key === 'full_hp') return locks.has(key) ? 1 : 0;
    throw new Error('Unknown key: ' + key);
  }
  function validate(key, value) {
    if (!Number.isSafeInteger(value)) throw new Error('Please enter a finite integer.');
    const a = actor();
    const entry = databaseEntry(key);
    if (entry) {
      const max = entry.kind === 'item' ? $gameParty.maxItems(entry.data) : 1;
      if (value < 0 || value > max) throw new Error('Allowed range: 0..' + max);
      if (entry.kind === 'skill') {
        if ($gameParty.inBattle()) throw new Error('Leave battle before editing skills.');
        if (value === 0 && a.addedSkills().includes(entry.id))
          throw new Error('This skill is granted by equipment or a state. Remove its source first.');
      }
      return value;
    }
    let min = 0, max = 1000000000;
    if (key === 'gold') max = $gameParty.maxGold();
    else if (key === 'hp') { min = 1; max = a.mhp; }
    else if (key === 'bp') max = a.maxTp();
    else if (key === 'temperament') { min = -50; max = 50; }
    else if (key === 'energy') max = Math.max(0, $gameVariables.value(128));
    else if (key === 'energy_max') { min = 1; max = 100000; }
    else if (key === 'grow_hp') min = 1;
    else if (!(key in params) && !(key in variables)) throw new Error('Unknown key: ' + key);
    if (value < min || value > max) throw new Error('Allowed range: ' + min + '..' + max);
    if ((key === 'energy' || key === 'energy_max') && $gameVariables.value(128) <= 0)
      throw new Error('Training has not started.');
    return value;
  }
  function write(key, value) {
    applying = true;
    try {
      const a = actor();
      const entry = databaseEntry(key);
      if (entry?.kind === 'item') {
        $gameParty.gainItem(entry.data, value - $gameParty.numItems(entry.data));
      } else if (entry?.kind === 'skill') {
        if (typeof a.safeInit === 'function') a.safeInit();
        if (value === 1) a.learnSkill(entry.id);
        else a.forgetSkill(entry.id);
        a.refresh();
        $gameMap.requestRefresh();
      } else if (key in params) {
        const id = params[key];
        a.addParam(id, value - a.paramBasePlus(id));
        $gameVariables.setValue(101 + (id === 0 ? 0 : id - 1), a.param(id));
      } else if (key in variables) {
        $gameVariables.setValue(variables[key], value);
        if (key === 'energy_max' && $gameVariables.value(127) > value) $gameVariables.setValue(127, value);
      } else if (key === 'gold') {
        $gameParty.gainGold(value - $gameParty.gold());
        $gameVariables.setValue(129, $gameParty.gold());
      } else if (key === 'hp') a.setHp(Math.min(value, a.mhp));
      else if (key === 'bp') a.setTp(value);
    } finally { applying = false; }
  }
  function snapshot() {
    const result = { bridge_version: 2, features: 'inventory,skills', ready: isReady() ? 1 : 0, scene: globalThis.SceneManager?._scene?.constructor.name || 'Loading' };
    if (!result.ready) return result;
    for (const key of [...Object.keys(params), ...Object.keys(variables), 'gold', 'hp', 'bp', 'full_hp']) result[key] = read(key);
    result.hp_max = actor().mhp;
    result.week = $gameVariables.value(121);
    result.actor = actor().name();
    result.items = Object.entries($gameParty._items || {}).filter(([id, count]) => count > 0 && globalThis.$dataItems?.[id])
      .map(([id, count]) => `${id}:${count}`).join(',');
    result.item_max = $gameParty.maxItems();
    result.skill_owned = ownedSkillIds().join(',');
    result.skill_equipped = (actor()._equipAbilitySkills || []).filter(id => id > 0).join(',');
    result.skill_granted = actor().addedSkills().join(',');
    return result;
  }
  function tick(request, lease, client) {
    hook();
    const current = actor();
    if (identity !== current || clientId !== client || !isReady()) clear();
    identity = current; clientId = client;
    if (lease) expires = Date.now() + 2000;
    else clear();
    let error = '';
    try {
      if (request) {
        if (!lease) throw new Error('CE session is disconnected.');
        if (request.op === 'clear') clear();
        else {
          if (!isReady()) throw new Error('Load a game with the dragon in the party first.');
          const { op, key } = request;
          if (op === 'unlock') locks.delete(key);
          else if (key === 'heal' && op === 'set') write('hp', actor().mhp);
          else if (key === 'full_hp' && op === 'lock') locks.set(key, 1);
          else if (op === 'set' || op === 'lock') {
            if (op === 'lock' && /^skill_/.test(key)) throw new Error('Skills support learn/forget, not freezing.');
            const value = validate(key, request.value);
            write(key, value);
            if (op === 'lock' || locks.has(key)) locks.set(key, value);
          } else throw new Error('Unknown operation.');
        }
      }
      if (lease && isReady()) for (const [key, value] of locks) {
        if (key === 'full_hp') { if ($gameParty.inBattle()) write('hp', actor().mhp); }
        else if (key === 'hp' && locks.has('full_hp') && $gameParty.inBattle()) continue;
        else if (key === 'energy') write(key, Math.min(value, $gameVariables.value(128)));
        else write(key, value);
      }
    } catch (e) { error = String(e.message || e); }
    return { ...snapshot(), error, locks: [...locks.keys()].join(',') };
  }
  globalThis.__drapCE = Object.freeze({ tick, snapshot, clear });
})();
