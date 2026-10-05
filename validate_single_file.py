"""Test the PS installer actually embedded in the CT, using disposable game fixtures.

Run: python validate_single_file.py --game-root PATH
Requires Windows PowerShell and local game data; no live game/save is changed.
"""
from pathlib import Path
import argparse, base64, ctypes, hashlib, json, os, re, shutil, subprocess, tempfile, time
import xml.etree.ElementTree as ET

here = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--game-root', type=Path, default=here.parent)
parser.add_argument('--ce-dir', type=Path)
args = parser.parse_args()
table = ET.parse(here/'DRAPLINE_SingleFile.CT')
lua = table.findtext('LuaScript')
match = re.search(r"P\.write\(script,'\\239\\187\\191'\.\.(.+)\)", lua)
script = json.loads(match[1])
payload = json.loads(base64.b64decode(re.search(r"FromBase64String\('([^']+)'\)",script)[1]))
assert 'runtime = nil' in lua and '__SETUP_SCRIPT__' not in lua and '__RUNTIME__' not in lua
ids = [entry.text for entry in table.findall('.//CheatEntry/ID')]
assert len(ids) == len(set(ids))
if args.ce_dir:
    dll = ctypes.CDLL(str(args.ce_dir/'lua53-64.dll'))
    dll.luaL_newstate.restype=ctypes.c_void_p
    dll.luaL_loadbufferx.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_size_t,ctypes.c_char_p,ctypes.c_char_p]
    dll.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p]; dll.lua_tolstring.restype=ctypes.c_char_p
    dll.lua_settop.argtypes=[ctypes.c_void_p,ctypes.c_int]; dll.lua_close.argtypes=[ctypes.c_void_p]
    state=dll.luaL_newstate()
    chunks=[lua]
    for element in table.findall('.//AssemblerScript'):
        chunks.extend(re.findall(r'\{\$lua\}(.*?)\{\$asm\}',element.text,re.S))
    for index,chunk in enumerate(chunks):
        encoded=chunk.encode('utf-8')
        assert dll.luaL_loadbufferx(state,encoded,len(encoded),str(index).encode(),None)==0,dll.lua_tolstring(state,-1,None)
        dll.lua_settop(state,0)
    dll.lua_close(state)
    print(f'PASS {len(chunks)} CE Lua chunks compile; {len(ids)} unique XML record IDs.')

destination=Path(tempfile.mkdtemp(prefix='DRAPLINE-single-test-'))
helper=destination/'embedded.ps1'; helper.write_text(script,encoding='utf-8-sig')
game=destination/"Game \u9f99\u5a18 [test] & ' space"
original=b'// fixture\r\n  await mainWindow.loadFile(join(APP_DIR_PATH, "index.html"));\r\n'
for name,expected in payload['compatibility'].items():
    source=args.game_root/'resources/app/app'/name
    assert hashlib.sha256(source.read_bytes()).hexdigest()==expected
    target=game/'resources/app/app'/name; target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(source,target)
main=game/'resources/app/electron/main.mjs'; main.parent.mkdir(parents=True,exist_ok=True); main.write_bytes(original)
exe=game/'DRAPLINE.exe'; exe.write_bytes(b'NOT EXECUTABLE - TEST FIXTURE')
save=game/'save/fixture.rmmzsave'; save.parent.mkdir(); save.write_bytes(b'SAVE CONTENT MUST REMAIN UNCHANGED')
ps=str(Path(os.environ['SystemRoot'])/'System32/WindowsPowerShell/v1.0/powershell.exe')
serial=0
def run(mode, selected=exe, ps_file=helper):
    global serial
    serial+=1
    request=destination/f'request-{serial}.json'; response=destination/f'result-{serial}.tsv'
    request.write_text(json.dumps({'mode':mode,'exe':str(selected),'result':str(response),'tempRoot':str(destination)},ensure_ascii=False),encoding='utf-8')
    completed=subprocess.run([ps,'-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(ps_file),'-Request',str(request)],capture_output=True,timeout=60)
    assert completed.returncode==0,completed.stderr.decode(errors='replace')
    assert response.is_file(),completed.stdout.decode(errors='replace')
    return dict(line.split('\t',1) for line in response.read_text(encoding='utf-8').splitlines())

result=run('install'); assert result['status']=='installed',result
installed=main.read_bytes(); assert installed.count(b'// DRAPLINE CE bridge v1')==1
backup=game/'CE-DRAPLINE/backup'
assert (backup/'main.mjs.original').read_bytes()==original
assert (backup/'save-before-install/fixture.rmmzsave').read_bytes()==save.read_bytes()
for name in ['main.mjs','renderer.js']:
    assert (game/'resources/app/electron/drapline-ce'/name).read_bytes()==base64.b64decode(payload[name])
expected_runtime=destination/('DRAPLINE-CE-'+hashlib.sha256(str(game).lower().encode()).hexdigest()[:12])
assert Path(result['runtime'])==expected_runtime
assert run('install')['status']=='installed' and main.read_bytes()==installed
print('PASS Unicode/spaces/quotes paths, embedded payload, backups, path hash, repeated installation.')

expected_runtime.mkdir()
status=expected_runtime/'status.tsv'
def fake_status():
    status.write_text(f'protocol\t1\nbridge_version\t2\npid\t{os.getpid()}\ntime\t{int(time.time()*1000)}\ngame_root\t{game}\n',encoding='utf-8')
fake_status(); assert run('probe')['status']=='connected'
assert run('install')['status']=='connected'  # Existing live bridge: no installation required.
fake_status(); assert run('probe',selected='')['status']=='connected'
status.write_text('protocol\t1\nbridge_version\t2\npid\t0\ntime\t0\n',encoding='utf-8')
assert run('probe')['status']=='select'
print('PASS selected/global bridge discovery and stale-session rejection.')

main.write_bytes(installed+b'// another mod\n')
assert run('uninstall')['status']=='error' and main.read_bytes().endswith(b'// another mod\n')
assert run('install')['status']=='error'
main.write_bytes(installed)
moved=destination/'Moved \u6e38\u620f'
shutil.copytree(game,moved)
result=run('uninstall',selected=moved/'DRAPLINE.exe'); assert result['status']=='uninstalled',result
assert (moved/'resources/app/electron/main.mjs').read_bytes()==original
assert run('uninstall')['status']=='uninstalled' and main.read_bytes()==original
assert save.read_bytes()==b'SAVE CONTENT MUST REMAIN UNCHANGED'
assert run('install')['status']=='installed'  # Reinstall after uninstall.
print('PASS other-mod protection, moved-game uninstall, exact restore, reinstall, no save changes.')

items=game/'resources/app/app/data/Items.json'; original_items=items.read_bytes(); items.write_bytes(b'[]')
before=main.read_bytes(); assert run('install')['status']=='error' and main.read_bytes()==before
items.write_bytes(original_items)
mock=destination/'closed-game-guard.ps1'
mock_body="function Get-CimInstance { [pscustomobject]@{ExecutablePath = '"+str(exe).replace("'","''")+"'} }\n"
mock.write_text(script.replace("$ErrorActionPreference = 'Stop'",mock_body+"$ErrorActionPreference = 'Stop'",1),encoding='utf-8-sig')
assert run('uninstall',ps_file=mock)['status']=='error' and main.read_bytes()==before
print('PASS game-version mismatch and running-game guard.')

# Also exercise the separate installer shipped in the source repository.
script_game=destination/'ScriptGame 中文 moved'
shutil.copytree(game,script_game)
script_dir=script_game/'CE-DRAPLINE'
for name in ['Install.ps1','Uninstall.ps1','compatibility.json']:
    shutil.copy2(here/name,script_dir/name)
shutil.copytree(here/'bridge',script_dir/'bridge')
script_main=script_game/'resources/app/electron/main.mjs'
script_backup=script_dir/'backup/main.mjs.original'
def run_cli(name, success=True):
    result=subprocess.run([ps,'-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(script_dir/name)],capture_output=True,timeout=60)
    assert (result.returncode==0)==success,result.stderr.decode(errors='replace')
run_cli('Install.ps1')  # Update at the copied/moved path.
run_cli('Uninstall.ps1'); assert script_main.read_bytes()==original
run_cli('Install.ps1')  # Reinstall without overwriting the original backup.
assert script_backup.read_bytes()==original
script_main.write_bytes(original)  # Already restored manually: archive stale manifest too.
run_cli('Uninstall.ps1'); run_cli('Install.ps1')
script_backup.write_bytes(b'WRONG BACKUP')
before=script_main.read_bytes(); run_cli('Install.ps1',success=False)
assert script_main.read_bytes()==before
script_backup.write_bytes(original)
run_cli('Uninstall.ps1')
assert (script_game/'save/fixture.rmmzsave').read_bytes()==save.read_bytes()
print('PASS source scripts: moved-path update, uninstall/reinstall, already-restored cleanup and backup protection.')
(destination/'table.lua').write_text(lua,encoding='utf-8')
(destination/'fixture-path.txt').write_text(str(game),encoding='utf-8')
print('Fixture retained for native CE verification:',destination)
