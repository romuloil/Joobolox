from pathlib import Path
import subprocess,sys,tempfile,os
R=Path(__file__).resolve().parents[1]
B=R.parent/'bank-fix/tests'
if not B.exists(): B=R.parent/'banco-marco10-28/tests'
def lit(s):return '[====['+s+']====]'
files={p.stem:p for p in (R/'src').glob('*.lua')}
files.update(mock=B/'roblox_geometry_mock.luau',fixture=B/'service_fixture.luau')
header='local SOURCES={'+','.join('[ '+lit(k)+' ]='+lit(p.read_text()) for k,p in files.items())+'}\n'
with tempfile.NamedTemporaryFile(mode='w',suffix='.luau',delete=False)as f:
 f.write(header+(R/'tests'/(sys.argv[1] if len(sys.argv)>1 else 'geometry.luau')).read_text());name=f.name
try:subprocess.run([os.environ.get('LUAU','/workspace/tooling/luau-0.698/source/luau'),name],check=True)
finally:os.unlink(name)
