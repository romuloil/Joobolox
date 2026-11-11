from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon,Rectangle
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
R=Path(__file__).resolve().parents[1]
points=[];parts=[]
for line in (R/'delivery/river.log').read_text().splitlines():
 a=line.split('\t')
 if a[0]=='RIVER':points.append(list(map(float,a[1:])))
 if a[0]=='PART':parts.append((a[1],list(map(float,a[2:]))))
r=np.array(points)
fig,ax=plt.subplots(figsize=(7,9),facecolor='#17252c');ax.set_facecolor('#43593c')
ax.add_patch(Rectangle((-1800,3446),4700,414,color='#b4a579'))
ax.add_patch(Rectangle((-1800,3860),4700,400,color='#286b89'))
for i in range(len(r)-1):
 x,z,w=r[i];xx,zz,ww=r[i+1]
 ax.add_patch(Polygon([(x-w/2-20,z),(xx-ww/2-20,zz),(xx+ww/2+20,zz),(x+w/2+20,z)],color='#8b9471'))
 ax.add_patch(Polygon([(x-w/2,z),(xx-ww/2,zz),(xx+ww/2,zz),(x+w/2,z)],color='#3d9bb4'))
ax.plot([-1700,1800],[3400,3400],color='#b3b4ab',lw=6)
ax.plot([1800,2770],[3400,3400],color='#b3b4ab',lw=3)
ax.plot([2040,2400],[3400,3400],color='#eb604c',lw=6)
ax.annotate('Ponte da Foz\nágua: ≈20 m',xy=(2220,3400),xytext=(1250,3610),color='white',arrowprops={'arrowstyle':'->','color':'white'},ha='center')
ax.text(2350,2180,'Rio da Enseada\n≈793 m',color='white',fontsize=11)
ax.text(500,3300,'Orla existente',color='white',fontsize=11)
ax.text(900,4010,'Mar',color='white',fontsize=15)
ax.set_xlim(800,2900);ax.set_ylim(4200,1220);ax.set_aspect('equal');ax.axis('off')
fig.suptitle('Rio e travessia • implantação V8',color='white',fontsize=15)
fig.text(.5,.02,'Planta técnica. Não é captura do Roblox Studio.',ha='center',color='#d3dad9',fontsize=9)
fig.tight_layout(rect=(0,.04,1,.95));fig.savefig(R/'delivery/PLANTA_RIO_PONTE.png',dpi=140);plt.close(fig)
fig=plt.figure(figsize=(13,8),facecolor='#dfe9ed');ax=fig.add_subplot(111,projection='3d');ax.set_facecolor('#dfe9ed')
xs=np.arange(1960,2490,4);zs=np.arange(3280,3544,4);xx,zz=np.meshgrid(xs,zs)
cx=np.interp(zz,r[:,1],r[:,0]);w=np.interp(zz,r[:,1],r[:,2]);d=np.abs(xx-cx);rad=w/2
surface=np.where(d<rad*.58,-16,np.where(d<rad,-16+10*(d-rad*.58)/(rad*.42),np.minimum(0,-6+6*(d-rad)/18)))
colors=np.zeros((*surface.shape,4));colors[:]=[.41,.51,.34,1];colors[surface<-2]=[.52,.49,.36,1]
polys=[];facecolors=[]
for i in range(len(zs)-1):
 for j in range(len(xs)-1):
  ids=[(i,j),(i,j+1),(i+1,j+1),(i+1,j)]
  polys.append([(xx[a,b],zz[a,b],surface[a,b])for a,b in ids]);facecolors.append(colors[i,j,:3])
  if all(d[a,b]<rad[a,b]for a,b in ids):
   polys.append([(xx[a,b],zz[a,b],-6)for a,b in ids]);facecolors.append([.24,.58,.65])
faces_idx=[[0,1,3,2],[4,5,7,6],[0,1,5,4],[2,3,7,6],[0,2,6,4],[1,3,7,5]]
for name,a in parts:
 size=np.array(a[:3]);pos=np.array(a[3:6]);right=np.array(a[6:9]);up=np.array(a[9:12]);look=np.array(a[12:15]);color=a[15:18]
 if pos[0]<1960 or pos[0]>2490 or pos[2]<3280 or pos[2]>3544:continue
 corners=np.array([pos+right*i*size[0]/2+up*j*size[1]/2+look*k*size[2]/2 for i in [-1,1]for j in [-1,1]for k in [-1,1]])[:,[0,2,1]]
 polys.extend([corners[f]for f in faces_idx]);facecolors.extend([color]*len(faces_idx))
ax.add_collection3d(Poly3DCollection(polys,facecolors=facecolors,linewidths=0,zsort='average'))
ax.set_xlim(1960,2490);ax.set_ylim(3280,3544);ax.set_zlim(-18,62);ax.set_box_aspect((530,264,80));ax.view_init(27,-63);ax.set_axis_off()
fig.suptitle('Ponte da Foz • geometria construída',fontsize=16,color='#243941')
fig.text(.5,.04,'Prévia técnica a partir das peças geradas; terreno aproximado. Não é renderização no Roblox Studio.',ha='center',fontsize=10,color='#243941')
fig.tight_layout(rect=(0,.05,1,.94));fig.savefig(R/'delivery/GEOMETRIA_PONTE.png',dpi=130);plt.close(fig)
