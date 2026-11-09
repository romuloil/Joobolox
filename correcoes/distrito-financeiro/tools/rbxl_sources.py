"""Read and patch only Source properties in a binary Roblox place.

All untouched chunks are copied byte-for-byte; all instance IDs and parents stay
unchanged. Supports uncompressed or Zstandard chunks used by the supplied place.
"""
from pathlib import Path
import struct, zstandard, json

def u32(data,p): return struct.unpack_from('<I',data,p)[0],p+4

def string(data,p):
 n,p=u32(data,p); assert p+n<=len(data)
 return data[p:p+n],p+n

def refs(data,n):
 assert len(data)==n*4
 values=[];last=0
 for i in range(n):
  z=int.from_bytes(bytes(data[i+j*n] for j in range(4)),'big')
  last+=(z>>1)^-(z&1);values.append(last)
 return values

class Place:
 def __init__(self,path):
  self.raw=Path(path).read_bytes();assert self.raw[:14]==b'<roblox!\x89\xff\r\n\x1a\n'
  self.chunks=[];self.classes={};self.instances={};self.props={};pos=32
  while pos<len(self.raw):
   tag,comp,size,res=struct.unpack_from('<4sIII',self.raw,pos)
   payload=self.raw[pos+16:pos+16+(comp or size)]
   data=zstandard.ZstdDecompressor().decompress(payload,max_output_size=size) if comp else payload
   assert len(data)==size
   self.chunks.append({'tag':tag,'data':data,'raw':self.raw[pos:pos+16+len(payload)]})
   pos+=16+len(payload)
  assert pos==len(self.raw)
  for ci,c in enumerate(self.chunks):
   data=c['data']
   if c['tag']==b'INST':
    id,p=u32(data,0);name,p=string(data,p);service=data[p];n,p=u32(data,p+1)
    ids=refs(data[p:p+n*4],n)
    self.classes[id]={'name':name.decode(),'ids':ids}
    for ref in ids:self.instances[ref]={'class':name.decode(),'ref':ref,'name':name.decode()}
   elif c['tag']==b'PROP':
    id,p=u32(data,0);name,p=string(data,p);kind=data[p];body=data[p+1:]
    self.props[id,name.decode()]={'chunk':ci,'prefix':data[:p+1],'kind':kind,'body':body}
   elif c['tag']==b'PRNT':
    assert data[0]==0;n,p=u32(data,1)
    children=refs(data[p:p+4*n],n);parents=refs(data[p+4*n:],n)
    for child,parent in zip(children,parents):self.instances[child]['parent']=parent
  for (id,name),prop in self.props.items():
   ids=self.classes[id]['ids']
   if name in ('Name','Source'):
    assert prop['kind']==1,(self.classes[id]['name'],name,prop['kind'])
    values=[];p=0
    for ref in ids:
     value,p=string(prop['body'],p);values.append(value)
     self.instances[ref][name.lower()]=value.decode('utf-8')
    assert p==len(prop['body']);prop['values']=values
   elif name=='Disabled' and prop['kind']==2:
    for ref,value in zip(ids,prop['body']):self.instances[ref]['disabled']=bool(value)
 def path(self,ref):
  parts=[];seen=set()
  while ref!=-1:
   assert ref not in seen;seen.add(ref);i=self.instances[ref];parts.append(i['name']);ref=i.get('parent',-1)
  return '/'.join(reversed(parts))
 def scripts(self):
  return [dict(i,path=self.path(i['ref'])) for i in self.instances.values() if 'source' in i]
 def patch(self,changes,output):
  modified={}
  for (id,name),prop in self.props.items():
   if name!='Source':continue
   values=[];changed=False
   for ref,old in zip(self.classes[id]['ids'],prop['values']):
    new=changes.get(ref,old.decode()).encode();changed|=new!=old;values.append(struct.pack('<I',len(new))+new)
   if changed:
    data=prop['prefix']+b''.join(values);packed=zstandard.ZstdCompressor(level=9).compress(data)
    modified[prop['chunk']]=struct.pack('<4sIII',b'PROP',len(packed),len(data),0)+packed
  Path(output).parent.mkdir(parents=True,exist_ok=True)
  Path(output).write_bytes(self.raw[:32]+b''.join(modified.get(i,c['raw']) for i,c in enumerate(self.chunks)))
  result=Place(output)
  assert len(result.chunks)==len(self.chunks)
  for i,c in enumerate(self.chunks):
   if i not in modified: assert c['raw']==result.chunks[i]['raw']
  for ref,inst in self.instances.items():
   expected=dict(inst)
   if ref in changes:expected['source']=changes[ref]
   assert result.instances[ref]==expected,(ref,inst['name'])
  return len(modified)

if __name__=='__main__':
 import argparse
 p=argparse.ArgumentParser();p.add_argument('place');p.add_argument('output');a=p.parse_args()
 place=Place(a.place);root=Path(a.output);root.mkdir(parents=True,exist_ok=True)
 manifest=[]
 for i in place.scripts():
  suffix='.server.lua' if i['class']=='Script' else '.client.lua' if i['class']=='LocalScript' else '.lua'
  file=f"{i['ref']:04d}_{i['name']}{suffix}"; (root/file).write_text(i['source'])
  manifest.append({k:v for k,v in i.items() if k!='source'}|{'file':file})
 (root/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
 print(json.dumps({'instances':len(place.instances),'scripts':len(manifest),'bank':[m for m in manifest if any(w in m['path'].lower() for w in ['bank','banco','heist','assalto'])]},ensure_ascii=False,indent=2))
