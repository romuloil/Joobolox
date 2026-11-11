from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon,Rectangle
R=Path(__file__).resolve().parents[1]
rows=[]
for line in (R/'delivery/geometry.log').read_text().splitlines():
 a=line.split('\t')
 if a[0]=='PARCEL': rows.append((a[1],*map(float,a[2:])))
fig,axes=plt.subplots(1,3,figsize=(17,6),facecolor='#182229')
settings={'CDA':(560,380,'Nebulosa • encosta curva',1),'TDE':(560,440,'Lua Negra • becos compactos',-1),'CDS':(520,460,'Horizonte Solar • crista',1)}
for ax,(g,(w,d,title,side)) in zip(axes,settings.items()):
 ax.set_facecolor('#384039');ax.add_patch(Rectangle((-w/2,-d/2),w,d,color='#5d574d'))
 for row in rows:
  if row[0]!=g:continue
  _,x,y,z,ww,dd,f,nx,nz=row
  right=np.array([-nz,nx]);look=np.array([nx,nz]);pos=np.array([x,z])
  pts=[pos+right*a*ww/2+look*b*dd/2 for a,b in [(-1,-1),(1,-1),(1,1),(-1,1)]]
  ax.add_patch(Polygon(pts,facecolor=plt.cm.YlOrBr(.25+.6*y/170),edgecolor='#f1d2a2',linewidth=.4))
 view=(w/2-29)*(1 if g=='CDA' else -1)
 vz=side*(d/2-30)
 ax.plot(view,vz,'*',color='#66e8ff',markersize=14)
 target={'CDA':(w/2+60,d/2+35),'TDE':(-w/2-50,-d/2-35),'CDS':(-w/2-50,d/2+35)}[g]
 ax.annotate('Cidade',target,color='#66e8ff',fontsize=9,ha='center')
 ax.annotate('',target,(view,vz),arrowprops={'color':'#66e8ff','arrowstyle':'->','lw':2})
 ax.set_title(title,color='white',fontsize=12,pad=15);ax.set_aspect('equal');ax.set_xlim(-w/2-70,w/2+70);ax.set_ylim(d/2+65,-d/2-65);ax.axis('off')
fig.suptitle('Distribuição das casas e direção dos mirantes • estudo geométrico V6',color='white',fontsize=16)
fig.text(.5,.04,'Prévia técnica da distribuição; não é uma captura do Roblox Studio. Casas à venda e detalhes de fachada omitidos neste desenho.',ha='center',color='#c5cbd0',fontsize=10)
fig.tight_layout(rect=(0,.08,1,.93));fig.savefig(R/'delivery/PLANTA_COMUNIDADES.png',dpi=130);plt.close(fig)
