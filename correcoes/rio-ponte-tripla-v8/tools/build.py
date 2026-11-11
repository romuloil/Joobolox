from pathlib import Path
import sys,hashlib,json,tempfile,subprocess,os,re
from rbxl_sources import Place
R=Path(__file__).resolve().parents[1]
base,out=map(Path,sys.argv[1:3]);out.parent.mkdir(parents=True,exist_ok=True)
assert hashlib.sha256(base.read_bytes()).hexdigest()=='7d1b4030ab2a0c9355b86851419e0f6cd54d13d3b96ff61d66251f7ce0f3bc0f','Use the delivered V7 base'
p=Place(base);changes={};paths=[]
for name in ['RiverLayout','RiverBuilder']:
 found=[s for s in p.scripts()if s['name']==name and not s['path'].startswith('ServerStorage/')]
 assert len(found)==1,name
 changes[found[0]['ref']]=(R/'src'/f'{name}.lua').read_text();paths.append(found[0]['path'])
p.patch(changes,out);q=Place(out)
with tempfile.TemporaryDirectory()as td:
 for s in q.scripts():
  path=Path(td)/f"{s['ref']}.lua";path.write_text(s['source'])
  c=subprocess.run([os.environ.get('LUAU_COMPILE','/workspace/tooling/luau-0.698/source/luau-compile'),'--binary',str(path)],capture_output=True)
  assert c.returncode==0,(s['path'],c.stderr.decode())
for key,prop in p.props.items():
 if key[1]!='Source':assert q.props[key]['body']==prop['body'],key
logs=R/'delivery';river=(logs/'river.log').read_text();regression=(logs/'regression.log').read_text()
a=re.search(r'TOTAL RIVER\s+(\d+)\s+PARTS\s+(\d+)\s+LENGTH\s+([\d.]+)',river)
b=re.search(r'TOTAL\s+(\d+)\s+DISTRICT\s+(\d+)\s+HOMES\s+(\d+)\s+(\d+)',regression)
assert a and b and 'Traceback'not in river+regression,'Complete tests first'
report={'base_file':base.name,'base_sha256':hashlib.sha256(base.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'original_instances_preserved':len(p.instances),'modified_scripts':paths,'original_scripts_unchanged':len(p.scripts())-len(changes),'compiled_scripts':len(q.scripts()),'river_checks':int(a[1]),'regression_checks':int(b[1]),'river_and_bridge_parts_in_simulation':int(a[2]),'river_length_studs':float(a[3]),'river_length_meters':round(float(a[3])*.28,2),'water_width_at_bridge_studs':72,'water_width_at_bridge_meters':20.16,'width_multiplier':2,'bridge_modules':3,'bridge_deck_length_studs':360,'bridge_deck_length_meters':100.8,'district_lots':int(b[2]),'free_gang_homes':int(b[3]),'purchasable_gang_homes':int(b[4]),'studio_playtest':False}
out.with_suffix('.validation.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n');print(json.dumps(report,indent=2,ensure_ascii=False))
