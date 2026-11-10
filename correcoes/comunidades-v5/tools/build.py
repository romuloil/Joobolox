from pathlib import Path
import sys,hashlib,json,struct,tempfile,subprocess,os
from rbxl_sources import Place
from place_merge import merge
R=Path(__file__).resolve().parents[1]
base=Path(sys.argv[1]);out=Path(sys.argv[2]);out.parent.mkdir(parents=True,exist_ok=True)
p=Place(base)
assert hashlib.sha256(base.read_bytes()).hexdigest() == 'f528f4be7606ff60af94e6470db6503f152cc07eaf95ffa85ba69e6410bff8c0', 'Use the authoritative atual.rbxl upload'
changes={};paths=[]
for name in ['CityRoads','MapBuilder','FavelaBuilder','HomeConfig','HomeService']:
 found=[s for s in p.scripts() if s['name']==name and not s['path'].startswith('ServerStorage/')]
 assert len(found)==1,(name,len(found))
 source=(R/'src'/f'{name}.lua').read_text()
 changes[found[0]['ref']]=source;paths.append(found[0]['path'])
with tempfile.TemporaryDirectory()as td:
 tmp=Path(td);patched=tmp/'patched.rbxl';p.patch(changes,patched)
 empty=tmp/'empty.rbxm';header=bytearray(p.raw[:32]);struct.pack_into('<II',header,16,0,0)
 empty.write_bytes(header+next(c['raw'] for c in p.chunks if c['tag']==b'END\0'))
 q=merge(patched,empty,out,{'FinancialDistrictBuilder':(R/'src/FinancialDistrictBuilder.lua').read_text()})
 errors=[]
 for s in q.scripts():
  path=tmp/f"{s['ref']}.lua";path.write_text(s['source'])
  r=subprocess.run([os.environ.get('LUAU_COMPILE','/workspace/tooling/luau-0.698/source/luau-compile'),'--binary',str(path)],capture_output=True)
  if r.returncode:errors.append({'path':s['path'],'error':r.stderr.decode()})
 assert not errors,errors
 # Compare every original property chunk except the five edited script sources.
 original_props=0
 for key,prop in p.props.items():
  if key[1]=='Source':continue
  assert prop['body']==q.props[key]['body'],('property changed',key)
  original_props+=1
 for ref,i in p.instances.items():
  expected=dict(i)
  if ref in changes:expected['source']=changes[ref]
  assert q.instances[ref]==expected,('instance changed',ref)
 preserved=['BankBuilder','BankService','BankController','GameConfig','LitoralBuilder','LitoralService','LitoralController','DealershipBuilder','DealershipController','VehicleService','GangService','PlayerDataService','ObraBuilder','FerramentasAssaltoService','CondoBuilder','ParkBuilder']
 for name in preserved:
  for s in p.scripts():
   if s['name']==name:assert q.instances[s['ref']]['source']==s['source'],name
 report={'base_file':base.name,'base_sha256':hashlib.sha256(base.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'original_instances_preserved':len(p.instances),'original_non_source_property_chunks_preserved':original_props,'original_scripts_unchanged':len(p.scripts())-len(changes),'modified_scripts':paths,'new_modules':['FinancialDistrictBuilder'],'compiled_scripts':len(q.scripts()),'preserved_systems':preserved,'geometry_checks':128,'housing_checks':20,'studio_playtest':False}
 out.with_suffix('.validation.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n');print(json.dumps(report,indent=2,ensure_ascii=False))
