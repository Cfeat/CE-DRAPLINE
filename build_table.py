"""Build the readable CE XML table from table.lua. No game-file changes."""
from pathlib import Path
import argparse, hashlib, json, re, xml.etree.ElementTree as ET

here = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--game-root', type=Path, default=here.parent)
parser.add_argument('--single-file', action='store_true', help='Embed setup and generate a portable CT.')
args = parser.parse_args()
game_root = str(args.game_root.resolve()).lower().rstrip('\\/')
tag = hashlib.sha256(game_root.encode('utf-8')).hexdigest()[:12]
root = ET.Element('CheatTable', CheatEngineTableVersion='45')
entries = ET.SubElement(root, 'CheatEntries')

def node(parent, id, description, script=None):
    e = ET.SubElement(parent, 'CheatEntry')
    ET.SubElement(e, 'ID').text = str(id)
    ET.SubElement(e, 'Description').text = '"' + description + '"'
    if script is None:
        ET.SubElement(e, 'GroupHeader').text = '1'
    else:
        ET.SubElement(e, 'VariableType').text = 'Auto Assembler Script'
        ET.SubElement(e, 'AssemblerScript').text = script
    return e

def lua_action(enable, disable=''):
    def section(name, code):
        return f'[{name}]\n{{$lua}}\nif syntaxcheck then return end\n{code}\n{{$asm}}\n'
    return section('ENABLE', enable) + section('DISABLE', disable)

top = node(entries, 1, 'DRAPLINE 中文增强版 v3.0.0 — 单文件自动连接' if args.single_file else 'DRAPLINE 中文增强版 v2.1 — 完整道具与技能')
children = ET.SubElement(top, 'CheatEntries')
node(children, 2, '使用：允许本表 Lua；自动连接；首次选择游戏并在表内安装' if args.single_file else '使用：安装 → 重启游戏 → 允许本表 Lua → 勾选启用连接')
node(children, 3, '双击“值”修改；勾选数值行锁定；取消连接释放全部锁定')
node(children, 10, '启用连接（无需手动附加进程）', lua_action('assert(drapCE, "Please allow the table Lua script.")\ndrapCE.start()', 'if drapCE then drapCE.stop() end'))
status = node(children, 11, '连接状态 / 当前场景', lua_action('',''))
week = node(children, 12, '已过周数（只读）', lua_action('',''))
if args.single_file:
    setup = node(children, 20, '单文件设置（内置模块；无需 Python 或外部安装脚本）')
    setup_entries = ET.SubElement(setup, 'CheatEntries')
    for rid, action, label in [(21,'connect','一键连接 / 首次安装'), (22,'select','选择或切换游戏'), (23,'uninstall','卸载桥接（先保存并退出游戏）')]:
        node(setup_entries,rid,label,lua_action(f'''drapCE.portable.{action}()
local entry=getAddressList().getMemoryRecordByID({rid})
createTimer(50,function() if entry then entry.disableWithoutExecute() end end)'''))
    node(setup_entries,24,'首次安装需关闭游戏；模块和备份由 CT 自动生成；保留原有数值与技能功能')

specs = [
    (100, '资金', [
        (101,'gold','金币', '0 到游戏资金上限；修改真实队伍资金。'),
        (102,'debt','债务', '0 到 1000000000；变量 130，0 表示无债务。')]),
    (200, '行动力 / 气质', [
        (201,'energy','当前行动力', '0 到当前最大行动力；需已开始养成。'),
        (202,'energy_max','最大行动力', '1 到 100000；减少上限会同时限制当前行动力。'),
        (203,'temperament','气质（-50～50）', '-50 到 50；正负方向沿用游戏气质坐标。')]),
    (300, '养成属性（永久基础值，不含战斗增减益）', [
        (301,'grow_hp','HP / 养成最大生命', '1 到 1000000000；战斗实际最大 HP 可能受状态影响。'),
        (302,'str','STR / 力量', '0 到 1000000000。'),
        (303,'vit','VIT / 防御', '0 到 1000000000。'),
        (304,'int','INT / 智力', '0 到 1000000000。'),
        (305,'res','RES / 抗性', '0 到 1000000000。'),
        (306,'agi','AGI / 速度', '0 到 1000000000。')]),
    (400, '战斗（龙娘：角色 1）', [
        (401,'hp','当前 HP', '1 到当前实际最大 HP；锁定可阻止常规 HP 扣减。'),
        (402,'bp','当前 BP', '0 到游戏 BP 上限；对应角色 TP。')]),
]
bindings = []
for gid, title, rows in specs:
    group = node(children, gid, title)
    sub = ET.SubElement(group, 'CheatEntries')
    for rid, key, label, hint in rows:
        node(sub, rid, label, lua_action(f'drapCE.lock("{key}", true)', f'if drapCE and drapCE.active then drapCE.lock("{key}", false) end'))
        bindings.append((rid,key,hint,True))
    if gid == 400:
        node(sub, 403, '战斗中保持满 HP（常规伤害）', lua_action('drapCE.lock("full_hp", true)', 'if drapCE and drapCE.active then drapCE.lock("full_hp", false) end'))
        bindings.append((403,'full_hp','',False))
        node(sub, 404, '单次回满 HP（勾选执行一次，可取消后再次执行）', lua_action('drapCE.heal()'))

extra = node(children, 500, '道具 / 技能（支持中文名称与 ID 搜索）')
extra_entries = ET.SubElement(extra, 'CheatEntries')
for rid, mode, label in [(501,'items','打开道具数量编辑器'),(502,'skills','打开技能拥有状态编辑器')]:
    action = f'''drapCE.openEditor("{mode}")
local entry = getAddressList().getMemoryRecordByID({rid})
createTimer(50, function() if entry then pcall(function() entry.disableWithoutExecute() end) end end)'''
    node(extra_entries,rid,label,lua_action(action))
node(extra_entries,503,'道具默认含神器 / 重要道具；搜索全部分类；数量 0 移除；技能学会 / 忘记')

data = args.game_root/'resources/app/app/data'
translation = json.loads((data/'Database_Simplified_Chinese.json').read_text(encoding='utf-8-sig')) if data.exists() else None
def plain(text):
    text = str(text or '')
    # Retain the Chinese language branch when the source contains multilingual UI text.
    text = re.sub(r'\\LANG\[2\](.*?)\\LANGEND', lambda m:m[1], text, flags=re.S)
    text = re.sub(r'\\LANG\[\d+\].*?\\LANGEND', '', text, flags=re.S)
    text = re.sub(r'\\SCRIPT\{.*?\}', '[动态数值]', text, flags=re.S)
    text = re.sub(r'\\[vV]\[(\d+)\]', lambda m:'[变量'+m[1]+']', text)
    text = re.sub(r'\\(?:[a-zA-Z_]+\[[^\]]*\]|[a-zA-Z_]+|[!><{}|.^$])', '', text)
    text = re.sub(r'[\x00-\x1f]+', ' ', text)
    return re.sub(r'\s+', ' ', text).strip()

catalogue = {}
for source, kind in ([('Items','items'),('Skills','skills')] if translation else []):
    records = json.loads((data/(source+'.json')).read_text(encoding='utf-8-sig'))
    translated = {row['id']:row for row in translation['item' if kind=='items' else 'skill']}
    rows=[]
    for record in records:
        if not record or not record['name'].strip(): continue
        lang=translated.get(record['id'],{})
        name=plain(lang.get('name') or record['name'])
        separator=bool(re.search(r'[-─━]{3,}|^[▼▽↓◆★]|(?:^|:)TIPS|^SKILL', name))
        category=record['itypeId' if kind=='items' else 'stypeId']
        regular = not separator
        if kind=='skills': regular = regular and '<NoName>' not in record['note'] and ('<AbilitySkill>' in record['note'] or category==2)
        description = ' '.join(plain(lang[key]) for key in ['description_1st','description_2nd'] if key in lang)
        if not description: description=plain(record['description'])
        rows.append({'id':record['id'],'name':name or ('ID '+str(record['id'])),'category':category,'regular':bool(regular),'description':description[:600]})
    catalogue[kind]=rows

def lua_literal(value):
    if isinstance(value,bool): return str(value).lower()
    if isinstance(value,int): return str(value)
    if isinstance(value,str): return json.dumps(value,ensure_ascii=False)
    if isinstance(value,list): return '{'+',\n'.join(lua_literal(item) for item in value)+'}'
    if isinstance(value,dict): return '{'+','.join(key+'='+lua_literal(item) for key,item in value.items())+'}'
    raise TypeError(type(value))

code = (here/'table.lua').read_text(encoding='utf-8')
code = code.replace('__RUNTIME__', "nil" if args.single_file else "(os.getenv('TEMP') or os.getenv('TMP')) .. [[\\DRAPLINE-CE-" + tag + ']]')
if catalogue:
    catalogue_code='D.catalogue = '+lua_literal(catalogue)
else:
    existing=ET.parse(here/'DRAPLINE.CT').findtext('LuaScript')
    catalogue_code=re.search(r'D\.catalogue = .*?(?=\nfunction D\.openEditor)',existing,re.S)[0]
code = code.replace('__CATALOGUE__',catalogue_code)
lines = []
for rid,key,hint,editable in bindings:
    lines.append(f'''do
  local record = list.getMemoryRecordByID({rid})
  if record then
    local item = {{record=record,key={json.dumps(key)},hint={json.dumps(hint,ensure_ascii=False)},editable={str(editable).lower()}}}
    D.records[{rid}] = item; D.records[{json.dumps(key)}] = item
    record.OnGetDisplayValue = function()
      if not live() then return true, '--' end
      return true, tostring(D.state[item.key] or '--')
    end
  end
end''')
lines.append('''local status = list.getMemoryRecordByID(11)
if status then
  status.OnGetDisplayValue = function()
    if not D.active then return true, '未连接' end
    if not D.seen or getTickCount()-D.seen >= 3000 then return true, '游戏无响应' end
    return true, (D.state.ready == 1 and '已连接：' or '等待进入存档：') .. tostring(D.state.scene or '')
  end
  status.OnActivate = function() return false end
end
local week = list.getMemoryRecordByID(12)
if week then
  week.OnGetDisplayValue = function() return true, live() and tostring(D.state.week or 0) or '--' end
  week.OnActivate = function() return false end
end''')
code = code.replace('__BINDINGS__','\n'.join(lines))
if args.single_file:
    import base64
    setup_script=(here/'single_file.ps1').read_text(encoding='utf-8-sig')
    payload={name:base64.b64encode((here/'bridge'/name).read_bytes()).decode('ascii') for name in ['main.mjs','renderer.js']}
    payload['compatibility']=json.loads((here/'compatibility.json').read_text(encoding='utf-8'))
    setup_script=setup_script.replace('__PAYLOAD__',base64.b64encode(json.dumps(payload).encode()).decode('ascii'))
    portable_code=(here/'single_file.lua').read_text(encoding='utf-8')
    portable_code=portable_code.replace('__SETUP_SCRIPT__',lua_literal(setup_script))
    code+='\n'+portable_code
ET.SubElement(root,'UserdefinedSymbols')
ET.SubElement(root,'LuaScript').text = code
ET.indent(root, space='  ')
output=here/('DRAPLINE_SingleFile.CT' if args.single_file else 'DRAPLINE.CT')
ET.ElementTree(root).write(output,encoding='utf-8',xml_declaration=True)
print(f'Built {output.name}: {len(bindings)} base rows; embedded inventory and skills; '+('portable runtime selection' if args.single_file else 'runtime tag '+tag))
