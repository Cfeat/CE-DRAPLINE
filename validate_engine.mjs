// Exercise the bridge using this game's actual RPG Maker objects and a read-only save copy.
import { readFileSync } from 'node:fs';
import { inflateSync } from 'node:zlib';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const here = dirname(fileURLToPath(import.meta.url));
let game = dirname(here), saveFile;
const args = process.argv.slice(2);
for (let index = 0; index < args.length; index++) {
  if (args[index] === '--game-root' && args[index + 1]) game = resolve(args[++index]);
  else if (args[index] === '--save' && args[index + 1]) saveFile = resolve(args[++index]);
  else throw new Error('Usage: node validate_engine.mjs --save "file.rmmzsave" [--game-root "game directory"]');
}
if (!saveFile) throw new Error('Provide --save with a local save containing actor 1. Only an in-memory copy will be edited.');
const base = join(game, 'resources/app/app');
const c = vm.createContext({ console, Utils: { isOptionValid: () => false } });
c.window = c;
const core = readFileSync(join(base, 'js/rmmz_core.js'), 'utf8');
vm.runInContext(core.slice(0, core.indexOf('function Utils()')), c);
vm.runInContext(readFileSync(join(base, 'js/rmmz_objects.js'), 'utf8'), c);
vm.runInContext(core.slice(core.indexOf('function JsonEx()')), c);
for (const name of ['System','Actors','Classes','States','Skills','Items','Armors','Weapons']) {
  vm.runInContext(`$data${name} = ${readFileSync(join(base, `data/${name}.json`), 'utf8')}`, c);
}
const managers = readFileSync(join(base,'js/rmmz_managers.js'),'utf8');
vm.runInContext('var DataManager = {};',c);
for (const name of ['isItem','isWeapon','isArmor','extractMetadata']) {
  const start=managers.indexOf(`DataManager.${name} = function(`);
  const end=managers.indexOf('\n};',start)+4;
  vm.runInContext(managers.slice(start,end),c);
}
vm.runInContext(`for (const data of [$dataActors,$dataClasses,$dataStates,$dataSkills,$dataItems,$dataArmors,$dataWeapons]) for (const entry of data) if(entry) DataManager.extractMetadata(entry);`,c);
const saved = readFileSync(saveFile, 'utf8');
c.saveJSON = inflateSync(Buffer.from(saved, 'latin1')).toString('utf8');
vm.runInContext(`
  var contents = JsonEx.parse(saveJSON);
  for (const [key, name] of Object.entries({system:'System',screen:'Screen',timer:'Timer',switches:'Switches',variables:'Variables',selfSwitches:'SelfSwitches',actors:'Actors',party:'Party',map:'Map',player:'Player'})) globalThis['$game'+name] = contents[key];
  var $gameTemp = new Game_Temp();
  function Scene_Map() {};
  function Scene_Title() {};
  var SceneManager = {_scene:new Scene_Map()};
`, c);
vm.runInContext(readFileSync(join(here,'bridge/renderer.js'),'utf8'), c);
const evaluate = code => vm.runInContext(code, c);
const request = (op,key,value=0,lease=true,client='validation') => evaluate(`__drapCE.tick(${JSON.stringify({op,key,value})}, ${lease}, ${JSON.stringify(client)})`);
const tick = (lease=true,client='validation') => evaluate(`__drapCE.tick(null,${lease},${JSON.stringify(client)})`);
assert.equal(tick().ready,1);
for (const [key,value] of Object.entries({gold:123456,debt:54321,energy:60,energy_max:120,temperament:-25,grow_hp:5000,str:777,vit:888,int:999,res:666,agi:555,hp:4321,bp:50})) {
  const result=request('set',key,value);
  assert.equal(result.error,'',`${key}: ${result.error}`);
  assert.equal(result[key],value,`${key} did not update actual game object`);
}
assert.equal(evaluate('$gameVariables.value(129)'),123456);
assert.equal(evaluate('$gameVariables.value(102)'),777);
request('lock','gold',123456);
evaluate('$gameParty.loseGold(50)');assert.equal(tick().gold,123456);
request('unlock','gold');evaluate('$gameParty.loseGold(50)');assert.equal(tick().gold,123406);
request('lock','energy',60);
evaluate('$gameVariables.setValue(127,10)');assert.equal(tick().energy,60);
request('lock','str',777);
evaluate('$gameActors._data[1].addParam(2,20)');assert.equal(tick().str,777);
request('lock','hp',4321);
evaluate('$gameActors._data[1].gainHp(-99999)');assert.equal(tick().hp,4321);
assert.equal(evaluate('$gameActors._data[1].isDead()'),false);
request('set','hp',4000);assert.equal(tick().hp,4000);
tick(false);evaluate('$gameActors._data[1].gainHp(-50)');assert.equal(tick().hp,3950);
assert.match(request('set','hp',900000).error,/Allowed range/);
assert.match(request('set','energy',999).error,/Allowed range/);
assert.match(request('set','temperament',51).error,/Allowed range/);
assert.match(request('set','gold',12.5).error,/integer/);
request('lock','gold',123456);
evaluate('$gameActors = JsonEx.parse(saveJSON).actors');tick();
evaluate('$gameParty.loseGold(1)');assert.equal(tick().gold,123455);
evaluate('SceneManager._scene = new Scene_Title()');
const oldGold=evaluate('$gameParty.gold()');
assert.match(request('set','gold',99999).error,/Load a game/);
assert.equal(evaluate('$gameParty.gold()'),oldGold);
evaluate('SceneManager._scene = new Scene_Map()');
request('lock','full_hp');evaluate('$gameParty._inBattle = true; $gameActors._data[1].setHp(1)');
assert.equal(tick().hp,tick().hp_max);
tick(false);assert.equal(tick().locks,'');
evaluate('$gameParty._inBattle = false');
for (const id of [21,170]) for (const value of [7,99,0]) {
  const result=request('set','item_'+id,value);
  assert.equal(result.error,'');assert.equal(evaluate(`$gameParty.numItems($dataItems[${id}])`),value);
}
assert.match(request('set','item_21',100).error,/Allowed range/);
assert.match(request('set','item_999999',1).error,/Unknown item ID/);
assert.match(request('set','item_21',1.5).error,/integer/);
const ability=readFileSync(join(base,'js/plugins/AbilitySystem.js'),'utf8');
const utils=ability.slice(ability.indexOf('class AbilitySystemUtils'),ability.indexOf('class Scene_Ability'));
const actorMethods=ability.slice(ability.indexOf('const _Game_Actor_initMembers'),ability.indexOf('// Add equip abilities to menu command.'));
const learnedOverride=ability.slice(ability.indexOf('const _Game_Actor_isLearnedSkill'));
vm.runInContext(`
  const EnableAutoEquipSkillSwitchId=0, EnableUsableAllSkillsByMapSceneSwitchId=0, MaxEquipAbilities=5, CostManagementByClasses=false;
  ${utils}\n${actorMethods}\n${learnedOverride}
`,c);
assert.equal(request('set','skill_121',0).error,'');
assert.equal(request('set','skill_121',1).error,'');
assert.equal(evaluate('$gameActors._data[1]._hasAbilitySkills.includes(121)'),true);
assert.equal(tick().skill_owned.split(',').includes('121'),true);
request('set','skill_121',1);
assert.equal(evaluate('$gameActors._data[1]._hasAbilitySkills.filter(id=>id===121).length'),1);
evaluate('$gameActors._data[1].doChangeEquipAbilitySkill(0,121)');
assert.equal(evaluate('$gameActors._data[1].isLearnedSkill(121)'),false,'Game plugin reports only unequipped pool as learned; bridge must include equipped pool.');
assert.equal(tick().skill_owned.split(',').includes('121'),true);
assert.equal(tick().skill_equipped.split(',').includes('121'),true);
assert.equal(request('set','skill_121',0).error,'');
assert.equal(tick().skill_owned.split(',').includes('121'),false);
assert.equal(evaluate('$gameActors._data[1]._equipAbilitySkills.includes(121)'),false);
assert.equal(evaluate('$gameActors._data[1]._hasAbilitySkills.includes(121)'),false);
const passive=evaluate('$dataSkills.find(s=>s && s.stypeId===2 && s.note.includes("パッシブスキル"))?.id');
assert.equal(request('set','skill_'+passive,1).error,'');
assert.equal(evaluate(`$gameActors._data[1]._skills.includes(${passive})`),true);
assert.equal(request('set','skill_'+passive,0).error,'');
assert.equal(evaluate(`$gameActors._data[1]._skills.includes(${passive})`),false);
evaluate('$gameParty._inBattle=true');assert.match(request('set','skill_121',1).error,/Leave battle/);
evaluate('$gameParty._inBattle=false; $dataStates[2000]={...$dataStates[2],id:2000,traits:[{code:43,dataId:121,value:1}]}; $gameActors._data[1]._states.push(2000)');
const granted=121;
assert.match(request('set','skill_'+granted,0).error,/granted/);
assert.match(request('set','skill_121',2).error,/Allowed range/);
assert.match(request('lock','skill_121',1).error,/not freezing/);
console.log('PASS: base edits and locks; item quantities/removal/limits; actual AbilitySystem learned/equipped pools, duplicate prevention and forgetting; passive skills; battle and external-grant guards. No save writes.');
