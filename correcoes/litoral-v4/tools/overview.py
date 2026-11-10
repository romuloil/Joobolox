from pathlib import Path
import re
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
R=Path(__file__).resolve().parents[1]
s=(R/'src/CityRoads.lua').read_text().split('CityRoads.Coast = {')[1].split('Beaches =')[0]
pts=[tuple(map(float,m))for m in re.findall(r'Vector3.new\(([-\d.]+),0,([-\d.]+)\)',s)]
fig,ax=plt.subplots(figsize=(9,12));fig.patch.set_facecolor('#edf3ec');ax.set_facecolor('#a6bb8a')
ax.add_patch(Rectangle((220,2880),2000,2800,color='#358ba4'))
ax.plot([0,0],[2700,2840],color='#525d60',lw=9)
ax.plot([p[0]for p in pts],[p[1]for p in pts],color='#525d60',lw=9)
ax.plot([p[0]for p in pts],[p[1]for p in pts],color='#d9d4a3',lw=.8,ls='--')
for i,(z,x,name)in enumerate([(3300,0,'Praia das Conchas'),(3900,0,'Enseada das Cores'),(4500,100,'Praia do Farol')]):
 ax.add_patch(Rectangle((220,z-200),220,400,color='#e7d49c'))
 ax.plot([x,180],[z,z],color='#525d60',lw=4)
 ax.add_patch(Rectangle((142,z-115),64,90,color='#888a7f'))
 ax.add_patch(Rectangle((196,z-165),24,330,color='#ad835d'))
 for j in range(6):
  ux=330 if j%2 else 275;uz=z-120+(j//2)*90
  ax.scatter(ux,uz,s=34,c=['#f46e6e','#f4c951','#52bdc9','#9c72be','#66ac6e','#eaa365'][j],edgecolors='white',linewidths=1)
 ax.text(490,z,name,fontsize=12,color='white',weight='bold',va='center')
for z in[3000,3500,4000,4500,5000,5450]:ax.add_patch(plt.Circle((-380,z),100,color='#809775'))
ax.scatter(120,5300,s=70,c='#626c67');ax.plot([200,200],[5260,5340],lw=3,c='#efab40')
ax.annotate('Acesso à ponte futura\n(ponte ainda não construída)',xy=(200,5300),xytext=(490,5350),color='white',fontsize=11,arrowprops={'arrowstyle':'->','color':'white'})
ax.text(-620,2800,'Ligação com a LK-102\ne a cidade',fontsize=11,weight='bold')
ax.text(1200,4120,'MAR',fontsize=22,color='#c9e7ec',ha='center',rotation=90)
ax.set_xlim(-720,1900);ax.set_ylim(5740,2680);ax.set_aspect('equal');ax.set_xticks([]);ax.set_yticks([])
ax.set_title('COSTA DO SOL\nPlanta de implantação • não é captura do Roblox Studio',fontsize=15,pad=18)
fig.savefig(R/'delivery/PLANTA_LITORAL.png',dpi=140,bbox_inches='tight')
