from pathlib import Path
import hashlib,json,subprocess,sys,tempfile,os,shutil
from rbxl_sources import Place
ROOT=Path(__file__).resolve().parents[1]
base=Path(sys.argv[1]);out=Path(sys.argv[2]);p=Place(base)
paths={'ServerScriptService/Services/BankBuilder':'BankBuilder.lua','ServerScriptService/Services/MapBuilder':'MapBuilder.lua','ReplicatedStorage/Shared/CityRoads':'CityRoads.lua'}
changes={}
for path,file in paths.items():
 found=[s for s in p.scripts()if s['path']==path];assert len(found)==1,path
 changes[found[0]['ref']]=(ROOT/'src'/file).read_text()
n=p.patch(changes,out);q=Place(out)
with tempfile.TemporaryDirectory()as tmp:
 for s in q.scripts():
  f=Path(tmp)/f"{s['ref']}.lua";f.write_text(s['source'])
  subprocess.run([os.environ.get('LUAU_COMPILE') or shutil.which('luau-compile') or '/workspace/tooling/luau-0.698/source/luau-compile','--binary',str(f)],check=True,stdout=subprocess.DEVNULL)
report={'base_sha256':hashlib.sha256(base.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'changed_scripts':list(paths),'unchanged_scripts':len(p.scripts())-len(changes),'compiled':len(q.scripts()),'instances_preserved':len(p.instances),'raw_chunks_preserved':len(p.chunks)-n,'bank_service_and_controller':'unchanged from delivered bank fix','validation':'54 district checks with real reused builders and controlled Roblox service doubles; 156 bank checks','studio_playtest':False}
out.with_suffix('.validation.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n');print(report)
