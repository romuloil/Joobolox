from pathlib import Path
import json,subprocess,tempfile,sys,os,shutil
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT.parent/'bank-fix'
if not BASE.exists(): BASE=ROOT.parent/'banco-marco10-28'
def lit(s):return '[====['+s+']====]'
files={'mock':BASE/'tests/roblox_geometry_mock.luau','fixture':BASE/'tests/service_fixture.luau','GameConfig':BASE/'original/1482_GameConfig.lua','HeistEvents':BASE/'original/1507_HeistEvents.lua',
 'BankBuilder':ROOT/'src/BankBuilder.lua','BankService':BASE/'src/BankService.lua','BankController':BASE/'src/BankController.lua',
 'CityRoads':ROOT/'src/CityRoads.lua','HorizonteBuilder':ROOT/'tests/reference/HorizonteBuilder.lua','MoradiaBuilder':ROOT/'tests/reference/MoradiaBuilder.lua','MapBuilder':ROOT/'src/MapBuilder.lua'}
def lua(v):
 if isinstance(v,str):return lit(v)
 if isinstance(v,list):return '{'+','.join(map(lua,v))+'}'
 if isinstance(v,dict):return '{'+','.join(k+'='+lua(x)for k,x in v.items())+'}'
 return str(v)
header='local SOURCES={'+','.join(k+'='+lit(p.read_text())for k,p in files.items())+'}\nlocal VAULT='+lua(json.loads((BASE/'tests/vault_asset.json').read_text()))+'\n'
flow=(BASE/'tests/bank_flow.luau').read_text()
body=flow if '--bank' in sys.argv else flow.split('local f=fixture()')[0]+(ROOT/'tests/district.luau').read_text()
with tempfile.NamedTemporaryFile(mode='w',suffix='.luau',delete=False)as f:f.write(header+body);path=Path(f.name)
try:subprocess.run([os.environ.get('LUAU') or shutil.which('luau') or '/workspace/tooling/luau-0.698/source/luau',str(path)],check=True)
finally:path.unlink()
