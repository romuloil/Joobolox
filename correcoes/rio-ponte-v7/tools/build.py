from pathlib import Path
import sys,struct,hashlib,json,tempfile,subprocess,os,re
import zstandard
from rbxl_sources import Place
R=Path(__file__).resolve().parents[1]
def string(s):
 b=s.encode();return struct.pack('<I',len(b))+b
def refs(values):
 last=0;out=[]
 for value in values:
  delta=value-last;last=value;out.append(((delta<<1)^(delta>>31))&0xffffffff)
 return b''.join(bytes((v>>shift)&255 for v in out)for shift in (24,16,8,0))
def chunk(tag,data):
 packed=zstandard.ZstdCompressor(level=9).compress(data)
 return struct.pack('<4sIII',tag,len(packed),len(data),0)+packed
base,out=map(Path,sys.argv[1:3]);out.parent.mkdir(parents=True,exist_ok=True)
assert hashlib.sha256(base.read_bytes()).hexdigest()=='1d749234f7a51f855f2d8e954442c7f4e4251c3e1d6a79cd86a1362b6b6c0b4f','Use the delivered V6 base'
p=Place(base);changed={};paths=[]
for name in ['MapBuilder','CityRoads','ExpansionBuilder','MapController']:
 candidates=[s for s in p.scripts()if s['name']==name and not s['path'].startswith('ServerStorage/')]
 assert len(candidates)==1,name
 s=candidates[0];changed[s['ref']]=(R/'src'/f'{name}.lua').read_text();paths.append(s['path'])
with tempfile.TemporaryDirectory()as td:
 patched=Path(td)/'patched.rbxl';p.patch(changed,patched);q=Place(patched)
 added=[];children=list(q.instances);parents=[q.instances[r].get('parent',-1)for r in children]
 newref=max(q.instances)+1;newclass=max(q.classes)+1
 modules={'RiverLayout':'ReplicatedStorage/Shared','RiverBuilder':'ServerScriptService/Services'}
 for i,(name,parent)in enumerate(modules.items()):
  ref=newref+i;cid=newclass+i;parentref=next(r for r in q.instances if q.path(r)==parent)
  added.append(chunk(b'INST',struct.pack('<I',cid)+string('ModuleScript')+b'\0'+struct.pack('<I',1)+refs([ref])))
  for prop,value in [('Name',name),('Source',(R/'src'/f'{name}.lua').read_text())]:
   added.append(chunk(b'PROP',struct.pack('<I',cid)+string(prop)+b'\x01'+string(value)))
  children.append(ref);parents.append(parentref)
 head=bytearray(q.raw[:32]);struct.pack_into('<II',head,16,len(q.classes)+len(modules),len(children))
 prnt=chunk(b'PRNT',b'\0'+struct.pack('<I',len(children))+refs(children)+refs(parents))
 body=b''.join(c['raw']for c in q.chunks if c['tag']not in (b'PRNT',b'END\0'))
 end=next(c['raw']for c in q.chunks if c['tag']==b'END\0')
 out.write_bytes(head+body+b''.join(added)+prnt+end)
 result=Place(out)
 for ref,inst in q.instances.items():assert result.instances[ref]==inst,(ref,'existing instance changed')
 for key,prop in p.props.items():
  if key[1]!='Source':assert result.props[key]['body']==prop['body'],key
 for s in result.scripts():
  source=Path(td)/f"{s['ref']}.luau";source.write_text(s['source'])
  c=subprocess.run([os.environ.get('LUAU_COMPILE','/workspace/tooling/luau-0.698/source/luau-compile'),'--binary',str(source)],capture_output=True)
  assert c.returncode==0,(s['path'],c.stderr.decode())
 logs=R/'delivery';river=(logs/'river.log').read_text();regression=(logs/'regression.log').read_text()
 a=re.search(r'TOTAL RIVER\s+(\d+)\s+PARTS\s+(\d+)\s+LENGTH\s+([\d.]+)',river)
 b=re.search(r'TOTAL\s+(\d+)\s+DISTRICT\s+(\d+)\s+HOMES\s+(\d+)\s+(\d+)',regression)
 assert a and b and 'Traceback'not in river+regression,'Complete all tests first'
 report={'base_file':base.name,'base_sha256':hashlib.sha256(base.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'original_instances_preserved':len(p.instances),'total_instances':len(result.instances),'modified_scripts':paths,'added_modules':modules,'original_scripts_unchanged':len(p.scripts())-len(changed),'compiled_scripts':len(result.scripts()),'river_checks':int(a[1]),'regression_checks':int(b[1]),'river_and_bridge_parts_in_simulation':int(a[2]),'river_length_studs':float(a[3]),'river_length_meters':round(float(a[3])*.28,2),'water_width_at_bridge_studs':36,'water_width_at_bridge_meters':10.08,'district_lots':int(b[2]),'free_gang_homes':int(b[3]),'purchasable_gang_homes':int(b[4]),'studio_playtest':False,'bridge':'Native Roblox adaptation inspired by the supplied Bridge Road Lowpoly GLB, not a published MeshPart import.'}
 out.with_suffix('.validation.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n');print(json.dumps(report,indent=2,ensure_ascii=False))
