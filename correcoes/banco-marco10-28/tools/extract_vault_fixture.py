"""Extract only transform/size metadata from the supplied vault for geometry tests."""
import json,struct,sys
from rbxl_sources import Place
p=Place(sys.argv[1]);data=[]
def floats(body,n):
 values=[]
 for i in range(n):
  z=int.from_bytes(bytes(body[i+j*n] for j in range(4)),'big')
  values.append(struct.unpack('<f',struct.pack('<I',(z>>1)|((z&1)<<31)))[0])
 return values
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
for cid,cl in p.classes.items():
 if cl['name']!='MeshPart':continue
 n=len(cl['ids']);d=p.props[cid,'CFrame']['body'];q=0;rot=[]
 axes=[[1,0,0],[0,1,0],[0,0,1],[-1,0,0],[0,-1,0],[0,0,-1]]
 for i in range(n):
  code=d[q];q+=1
  if code:
   x,y=axes[(code-1)//6],axes[(code-1)%6];rot.append([x,y,cross(x,y)])
  else:
   r=struct.unpack_from('<9f',d,q);q+=36;rot.append([list(r[j::3]) for j in range(3)])
 pos=[floats(d[q+j*n*4:q+(j+1)*n*4],n) for j in range(3)]
 d=p.props[cid,'size']['body'];size=[floats(d[j*n*4:(j+1)*n*4],n) for j in range(3)]
 for i,ref in enumerate(cl['ids']):
  if '/BankModels/CofreBanco/' in p.path(ref):
   data.append({'name':p.instances[ref]['name'],'position':[a[i]for a in pos],'size':[a[i]for a in size],'basis':rot[i]})
print(json.dumps(data,indent=2))
