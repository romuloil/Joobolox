from pathlib import Path
import sys,hashlib,json,tempfile,subprocess,os,re
from rbxl_sources import Place
R=Path(__file__).resolve().parents[1]
base=Path(sys.argv[1]);out=Path(sys.argv[2]);out.parent.mkdir(parents=True,exist_ok=True)
assert hashlib.sha256(base.read_bytes()).hexdigest()=='c12ebf66575c0bda6895b0c571aa15fa332b43b39d5adfb0569595ff6dc4feec','Use the delivered V5 base'
p=Place(base);changes={};paths=[]
for name in ['CityRoads','FavelaBuilder','FinancialDistrictBuilder','MapController']:
 found=[s for s in p.scripts() if s['name']==name and not s['path'].startswith('ServerStorage/')]
 assert len(found)==1,(name,len(found))
 changes[found[0]['ref']]=(R/'src'/f'{name}.lua').read_text();paths.append(found[0]['path'])
p.patch(changes,out);q=Place(out)
with tempfile.TemporaryDirectory()as td:
 for script in q.scripts():
  path=Path(td)/f"{script['ref']}.lua";path.write_text(script['source'])
  r=subprocess.run([os.environ.get('LUAU_COMPILE','/workspace/tooling/luau-0.698/source/luau-compile'),'--binary',str(path)],capture_output=True)
  assert r.returncode==0,(script['path'],r.stderr.decode())
props=0
for key,prop in p.props.items():
 if key[1]!='Source':assert q.props[key]['body']==prop['body'],key;props+=1
preserved=['BankBuilder','BankService','BankController','GameConfig','LitoralBuilder','LitoralService','LitoralController','DealershipBuilder','DealershipController','VehicleService','GangService','PlayerDataService','ObraBuilder','MapBuilder','HomeService','HomeConfig']
for name in preserved:
 for s in p.scripts():
  if s['name']==name:assert q.instances[s['ref']]['source']==s['source'],name
logs=R/'delivery'
g=(logs/'geometry.log').read_text();h=(logs/'housing.log').read_text()
assert 'Traceback' not in g+h
checks=re.search(r'TOTAL\s+(\d+)\s+DISTRICT\s+(\d+)\s+HOMES\s+(\d+)\s+(\d+)',g)
hchecks=re.search(r'TOTAL HOUSING\s+(\d+)',h)
assert checks and hchecks,'Tests must complete before release build'
report={'base_file':base.name,'base_sha256':hashlib.sha256(base.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'original_instances_preserved':len(p.instances),'original_non_source_property_chunks_preserved':props,'original_scripts_unchanged':len(p.scripts())-len(changes),'modified_scripts':paths,'compiled_scripts':len(q.scripts()),'preserved_systems':preserved,'geometry_checks':int(checks[1]),'housing_checks':int(hchecks[1]),'district_lots':int(checks[2]),'free_gang_homes':int(checks[3]),'purchasable_gang_homes':int(checks[4]),'studio_playtest':False}
out.with_suffix('.validation.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n');print(json.dumps(report,indent=2,ensure_ascii=False))
