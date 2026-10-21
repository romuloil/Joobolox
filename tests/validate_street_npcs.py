from pathlib import Path
import subprocess,tempfile,json
import argparse
root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description='Execute StreetNPCService against actual map geometry with service doubles')
parser.add_argument('--luau',default='luau')
args=parser.parse_args()
def literal(s):
 eq='===='
 while ']'+eq+']' in s:eq+='='
 return '['+eq+'[\n'+s+'\n]'+eq+']'
sources={}
for name,branch in [('GameConfig','ReplicatedStorage/Shared'),('CivicConfig','ReplicatedStorage/Shared'),('PrisonBuilder','ServerScriptService/Services'),('TaxiSiteBuilder','ServerScriptService/Services'),('CivicBuilder','ServerScriptService/Services'),('MapBuilder','ServerScriptService/Services'),('StreetNPCConfig','ReplicatedStorage/Shared'),('StreetNPCService','ServerScriptService/Services')]:
 sources[name]=(root/'src'/branch/(name+'.lua')).read_text()
program='local spec=(function()\n'+(root/'tests/street_npc_spec.luau').read_text()+'\nend)()\n'
program+='spec('+literal((root/'tests/roblox_geometry_mock.luau').read_text())+','+literal((root/'tests/service_fixture.luau').read_text())+',{\n'+',\n'.join('['+json.dumps(k)+']='+literal(v) for k,v in sources.items())+'})\n'
with tempfile.TemporaryDirectory(prefix='street-npc-tests-') as tmp:
 p=Path(tmp)/'run.luau';p.write_text(program)
 raise SystemExit(subprocess.run([args.luau,str(p)],cwd=root).returncode)
