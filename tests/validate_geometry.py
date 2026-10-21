#!/usr/bin/env python3
"""Run actual map builders against geometry-only Roblox value/Instance doubles.

No rendering, humanoid movement, assets or network are emulated. Random uses a
repeatable test generator, not the proprietary Roblox generator.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile


def literal(text):
    boundary = '===='
    while ']' + boundary + ']' in text:
        boundary += '='
    return '[' + boundary + '[' + '\n' + text + '\n]' + boundary + ']'


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--luau', default='/workspace/tooling/luau-0.698/source/luau')
    args = parser.parse_args()
    mock = (root / 'tests/roblox_geometry_mock.luau').read_text()
    spec = (root / 'tests/geometry_spec.luau').read_text()
    code = 'local mock = (function()\n' + mock + '\nend)()\n'
    for name, category in [('GameConfig', 'Shared'), ('CivicConfig', 'Shared'), ('PrisonBuilder', 'Services'), ('CivicBuilder', 'Services'), ('MapBuilder', 'Services')]:
        branch = 'ReplicatedStorage/Shared' if category == 'Shared' else 'ServerScriptService/Services'
        source = (root / 'src' / branch / (name + '.lua')).read_text()
        code += f'local {name} = mock.load("{name}", {literal(source)}, {str(category == "Services").lower()})\n'
    code += 'MapBuilder.build()\n'
    code += 'local spec = (function()\n' + spec + '\nend)()\n'
    code += 'spec(mock,GameConfig,CivicConfig,CivicBuilder)\n'
    with tempfile.TemporaryDirectory(prefix='littlelife-geometry-') as temp:
        test = Path(temp) / 'geometry.luau'
        test.write_text(code)
        return subprocess.run([args.luau, str(test)], cwd=root).returncode


if __name__ == '__main__':
    raise SystemExit(main())
