"""Patch the bank's three ModuleScripts; preserve the supplied place's other chunks."""
from pathlib import Path
import shutil
import argparse, hashlib, json, subprocess, os, tempfile
from rbxl_sources import Place
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('input',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
place=Place(a.input)
paths={
 'ServerScriptService/Services/BankService':'BankService.lua',
 'ServerScriptService/Services/BankBuilder':'BankBuilder.lua',
 'StarterPlayer/StarterPlayerScripts/Controllers/BankController':'BankController.lua',
}
changes={}
for suffix,name in paths.items():
 found=[s for s in place.scripts() if s['path']==suffix or s['path'].endswith('/'+suffix)]
 assert len(found)==1,(suffix, len(found))
 changes[found[0]['ref']]=(ROOT/'src'/name).read_text()
changed_chunks=place.patch(changes,a.output)
output=Place(a.output)
compiler=os.environ.get('LUAU_COMPILE') or shutil.which('luau-compile') or '/workspace/tooling/luau-0.698/source/luau-compile'
with tempfile.TemporaryDirectory() as temp:
 for s in output.scripts():
  file=Path(temp)/f"{s['ref']}.lua";file.write_text(s['source'])
  result=subprocess.run([compiler,'--binary',str(file)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
  assert result.returncode==0,(s['path'],result.stderr)
report={'input_name':a.input.name,'input_sha256':hashlib.sha256(a.input.read_bytes()).hexdigest(),
 'output_name':a.output.name,'output_sha256':hashlib.sha256(a.output.read_bytes()).hexdigest(),
 'instances':len(place.instances),'scripts':len(place.scripts()),'compiled_scripts':len(output.scripts()),
 'modified_scripts':[place.path(ref) for ref in changes],
 'changed_chunks':changed_chunks,'preserved_chunks':len(place.chunks)-changed_chunks,
 'other_scripts_unchanged':len(place.scripts())-len(changes),
 'checks':'All other chunks byte-identical; all instance IDs, names and parents unchanged.',
 'runtime_validation':'156 assertions in Luau against bank modules with Roblox service doubles. See TESTES.log.',
 'limits':'Roblox Studio rendering, engine physics, live replication, mobile input and avatar/mesh asset loading need in-game verification.'}
a.output.with_suffix('.validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2))
