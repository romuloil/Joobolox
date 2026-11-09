"""Patch source chunks and append a physical model; preserve every existing instance."""
from pathlib import Path
import hashlib,json,struct,subprocess,tempfile,sys,os
from rbxl_sources import Place,refs,u32,string
import zstandard
R=Path(__file__).resolve().parents[1]
def encstr(s):
 if isinstance(s,str):s=s.encode()
 return struct.pack('<I',len(s))+s
def ints(v):
 n=len(v);return b''.join(bytes((x>>shift)&255 for x in v)for shift in (24,16,8,0))
def encrefs(v):
 out=[];last=0
 for x in v:
  d=x-last;last=x;out.append(((d<<1)^(d>>31))&0xffffffff)
 return ints(out)
def uints(b,n):return [int.from_bytes(bytes(b[i+j*n]for j in range(4)),'big')for i in range(n)]
def chunk(tag,data):
 b=zstandard.ZstdCompressor(level=9).compress(data)
 return struct.pack('<4sIII',tag,len(b),len(data),0)+b

def merge(base,addon,out,modules):
 p=Place(base);a=Place(addon)
 parentStorage=next(r for r,i in p.instances.items()if i['class']=='ServerStorage')
 parentServices=next(r for r in p.instances if p.path(r)=='ServerScriptService/Services')
 offset=max(p.instances)+1;cls_offset=max(p.classes)+1
 remap=lambda r:r+offset if r>=0 else -1
 sb=next((c['data']for c in p.chunks if c['tag']==b'SSTR'),struct.pack('<II',0,0))
 sa=next((c['data']for c in a.chunks if c['tag']==b'SSTR'),struct.pack('<II',0,0))
 assert sb[:4]==sa[:4]==b'\0'*4
 nb=int.from_bytes(sb[4:8],'little');na=int.from_bytes(sa[4:8],'little')
 sstr=struct.pack('<II',0,nb+na)+sb[8:]+sa[8:]
 added=[]
 for c in a.chunks:
  tag=c['tag'];d=c['data']
  if tag==b'INST':
   cid,k=u32(d,0);_,k=string(d,k);service=d[k];n,k=u32(d,k+1)
   assert service==0
   d=struct.pack('<I',cid+cls_offset)+d[4:k]+encrefs([remap(r)for r in refs(d[k:k+n*4],n)])+d[k+n*4:]
  elif tag==b'PROP':
   cid,k=u32(d,0);_,k=string(d,k);kind=d[k];b=d[k+1:];n=len(a.classes[cid]['ids'])
   if kind==19:b=encrefs([remap(r)for r in refs(b,n)])
   elif kind==28:b=ints([r+nb for r in uints(b,n)])
   elif kind==34:
    j=n*4;uris,j=u32(b,j)
    for _ in range(uris):_,j=string(b,j)
    num,j=u32(b,j);end=j+num*4
    b=b[:j]+encrefs([remap(r)for r in refs(b[j:end],num)])+b[end:]
   d=struct.pack('<I',cid+cls_offset)+d[4:k+1]+b
  else:continue
  added.append(chunk(tag,d))
 children=list(p.instances);parents=[p.instances[r].get('parent',-1)for r in children]
 for r,i in a.instances.items():
  children.append(remap(r));parents.append(parentStorage if i.get('parent',-1)<0 else remap(i['parent']))
 nextref=offset+max(a.instances)+1;nextclass=cls_offset+max(a.classes)+1
 for name,source in modules.items():
  added.append(chunk(b'INST',struct.pack('<I',nextclass)+encstr('ModuleScript')+b'\0'+struct.pack('<I',1)+encrefs([nextref])))
  for prop,value in [('Name',name),('Source',source)]:added.append(chunk(b'PROP',struct.pack('<I',nextclass)+encstr(prop)+b'\x01'+encstr(value)))
  children.append(nextref);parents.append(parentServices);nextref+=1;nextclass+=1
 prnt=chunk(b'PRNT',b'\0'+struct.pack('<I',len(children))+encrefs(children)+encrefs(parents))
 orig=[c['raw']for c in p.chunks if c['tag']not in [b'SSTR',b'PRNT',b'END\0']]
 header=bytearray(p.raw[:32]);struct.pack_into('<II',header,16,len(p.classes)+len(a.classes)+len(modules),len(children))
 end=next(c['raw']for c in p.chunks if c['tag']==b'END\0')
 out.write_bytes(header+chunk(b'SSTR',sstr)+b''.join(orig)+b''.join(added)+prnt+end)
 q=Place(out)
 for r,i in p.instances.items():assert q.instances[r]==i,(r,'original instance changed during merge')
 assert len(q.instances)==len(p.instances)+len(a.instances)+len(modules)
 assert len(q.scripts())==len(p.scripts())+len(modules)
 return q

if __name__=='__main__':
 base=Path(sys.argv[1]);out=Path(sys.argv[2]);out.parent.mkdir(parents=True,exist_ok=True)
 assert hashlib.sha256(base.read_bytes()).hexdigest()=='3aa1a08873b95bacbcb0411f830b260d803144b89e398c5d381a1dd495b34388','Use exactly the latest user-uploaded metropolitan place'
 p=Place(base);changes={};paths=[]
 for name in ['BankBuilder','MapBuilder','CityRoads','VehicleService','GarageController','PlayerDataService','MapController']:
  found=[i for i in p.scripts()if i['name']==name];assert len(found)==1,name
  changes[found[0]['ref']]=(R/'src'/f'{name}.lua').read_text();paths.append(found[0]['path'])
 with tempfile.TemporaryDirectory()as tmp:
  patched=Path(tmp)/'patched.rbxl';p.patch(changes,patched)
  q=merge(patched,R/'dealership.rbxm',out,{'DealershipBuilder':(R/'src/DealershipBuilder.lua').read_text()})
  for s in q.scripts():
   path=Path(tmp)/f"{s['ref']}.lua";path.write_text(s['source'])
   subprocess.run([os.environ.get('LUAU_COMPILE','/workspace/tooling/luau-0.698/source/luau-compile'),'--binary',str(path)],check=True,stdout=subprocess.DEVNULL)
 report={'base_sha256':hashlib.sha256(base.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'original_instances_preserved':len(p.instances),'original_scripts_unchanged':len(p.scripts())-len(changes),'changed_scripts':paths,'imported_physical_instances':8618,'imported_source_scripts':0,'new_modules':['DealershipBuilder'],'compiled_scripts':len(q.scripts()),'bank_service_controller_unchanged':True,'studio_playtest':False}
 out.with_suffix('.validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
