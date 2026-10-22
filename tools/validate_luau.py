#!/usr/bin/env python3
"""Compile game scripts and run headless logic tests using official Luau tools.

Roblox Studio is still required to validate rendering, physics and replication.
The compiler/runner are supplied on PATH or through --luau-dir; no installers or
external downloads run as part of validation.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def luau_string(value: str) -> str:
    equals = "="
    while "]" + equals + "]" in value:
        equals += "="
    return "[" + equals + "[" + value + "]" + equals + "]"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau-dir", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    compiler = str(args.luau_dir / "luau-compile") if args.luau_dir else shutil.which("luau-compile")
    runner = str(args.luau_dir / "luau") if args.luau_dir else shutil.which("luau")
    if not compiler or not runner:
        parser.error("Install official Luau CLI/compiler or supply --luau-dir")

    scripts = sorted(root.joinpath("src").rglob("*.lua"))
    if not scripts:
        raise RuntimeError("No game scripts discovered")
    failures = []
    for script in scripts:
        result = subprocess.run([compiler, "--binary", str(script)], capture_output=True)
        if result.returncode:
            failures.append(script)
            sys.stderr.write(result.stderr.decode(errors="replace"))
    print(f"Luau compile: {len(scripts) - len(failures)}/{len(scripts)} game scripts passed")
    if failures:
        return 1
    for name in ["prison_rules_spec.luau", "police_rules_spec.luau", "work_role_rules_spec.luau", "taxi_rules_spec.luau", "prison_activity_rules_spec.luau"]:
        test = root / "tests" / name
        if not test.exists():
            continue
        result = subprocess.run([runner, str(test)], cwd=root)
        if result.returncode:
            return result.returncode
    mock = root / "tests/roblox_geometry_mock.luau"
    fixture = root / "tests/service_fixture.luau"
    specs = [
        ("prison_service_spec.luau", [mock, root / "src/ReplicatedStorage/Shared/PrisonRules.lua", root / "src/ServerScriptService/Services/PrisonService.lua"]),
        ("prison_outfit_spec.luau", [mock, fixture, root / "src/ServerScriptService/Services/PrisonOutfitService.lua"]),
        ("prison_activity_service_spec.luau", [mock, fixture, root / "src/ReplicatedStorage/Shared/PrisonActivityConfig.lua", root / "src/ReplicatedStorage/Shared/PrisonActivityRules.lua", root / "src/ServerScriptService/Services/PrisonActivityService.lua"]),
        ("police_service_spec.luau", [mock, root / "src/ReplicatedStorage/Shared/PoliceConfig.lua", root / "src/ReplicatedStorage/Shared/PoliceRules.lua", root / "src/ServerScriptService/Services/PoliceService.lua"]),
        ("work_role_service_spec.luau", [mock, fixture, root / "src/ReplicatedStorage/Shared/WorkRoleConfig.lua", root / "src/ReplicatedStorage/Shared/WorkRoleRules.lua", root / "src/ServerScriptService/Services/WorkRoleService.lua"]),
        ("vehicle_service_spec.luau", [mock, fixture, root / "src/ReplicatedStorage/Shared/GameConfig.lua", root / "src/ServerScriptService/Services/CarBuilder.lua", root / "src/ServerScriptService/Services/VehicleService.lua"]),
        ("taxi_service_spec.luau", [mock, fixture, root / "src/ReplicatedStorage/Shared/TaxiConfig.lua", root / "src/ReplicatedStorage/Shared/TaxiRules.lua", root / "src/ServerScriptService/Services/TaxiService.lua"]),
    ]
    for name, sources in specs:
        spec = root / "tests" / name
        if not spec.exists():
            continue
        if not all(path.exists() for path in sources):
            raise RuntimeError(f"Missing implementation source for {name}")
        program = "local spec = (function()\n" + spec.read_text() + "\nend)()\n"
        program += "spec(" + ",\n".join(luau_string(path.read_text()) for path in sources) + ")\n"
        with tempfile.TemporaryDirectory(prefix="littlelife-test-") as directory:
            target = Path(directory) / name
            target.write_text(program)
            result = subprocess.run([runner, str(target)], cwd=root)
            if result.returncode:
                return result.returncode
    geometry = root / "tests" / "validate_geometry.py"
    if geometry.exists():
        result = subprocess.run([sys.executable, str(geometry), "--luau", runner], cwd=root)
        if result.returncode:
            return result.returncode
    npc = root / "tests" / "validate_street_npcs.py"
    result = subprocess.run([sys.executable, str(npc), "--luau", runner], cwd=root)
    if result.returncode:
        return result.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
