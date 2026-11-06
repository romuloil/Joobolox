"""Run actual bank modules in Luau with controlled Roblox service doubles."""
from pathlib import Path
import shutil
import subprocess, tempfile, os, json
ROOT=Path(__file__).resolve().parents[1]
LUAU=os.environ.get('LUAU') or shutil.which('luau') or '/workspace/tooling/luau-0.698/source/luau'
original=os.environ.get('BANK_ORIGINAL')=='1'
files={'mock':ROOT/'tests/roblox_geometry_mock.luau','fixture':ROOT/'tests/service_fixture.luau',
 'GameConfig':ROOT/'original/1482_GameConfig.lua','HeistEvents':ROOT/'original/1507_HeistEvents.lua'}
for name,ref in [('BankBuilder','1491'),('BankService','1492'),('BankController','0024')]:
 files[name]=ROOT/(f'original/{ref}_{name}.lua' if original else f'src/{name}.lua')
def literal(s):
 eq='===='
 assert ']'+eq+']' not in s
 return '['+eq+'['+s+']'+eq+']'
header='local SOURCES = {\n'+',\n'.join(f'{k}={literal(p.read_text())}' for k,p in files.items())+'\n}\n'
def lua(v):
 if isinstance(v,str):return literal(v)
 if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
 if isinstance(v,dict):return '{'+','.join(k+'='+lua(x) for k,x in v.items())+'}'
 return str(v)
header+='local VAULT = '+lua(json.loads((ROOT/'tests/vault_asset.json').read_text()))+'\n'
with tempfile.NamedTemporaryFile(mode='w',suffix='.luau',dir=ROOT/'tests',delete=False) as f:
 f.write(header+(ROOT/'tests/bank_flow.luau').read_text()); script=Path(f.name)
try: subprocess.run([LUAU,str(script)],check=True)
finally: script.unlink()
