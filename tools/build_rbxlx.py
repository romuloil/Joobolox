#!/usr/bin/env python3
"""Build a Roblox XML place from the repository's script tree (Python 3 only)."""
from __future__ import annotations

import argparse
from pathlib import Path
import xml.etree.ElementTree as ET


SERVICES = {"ReplicatedStorage", "ServerScriptService", "StarterPlayer"}
SPECIAL_CONTAINERS = {"StarterPlayerScripts": "StarterPlayerScripts"}


def script_type(path: Path) -> tuple[str, str]:
    for suffix, kind in ((".server.lua", "Script"), (".client.lua", "LocalScript"), (".lua", "ModuleScript")):
        if path.name.endswith(suffix):
            return path.name[:-len(suffix)], kind
    raise ValueError(f"Unknown script extension: {path}")


def build(source: Path, output: Path) -> int:
    if not source.is_dir():
        raise ValueError(f"Source directory does not exist: {source}")
    root = ET.Element("roblox", version="4")
    counter = 0
    count = 0

    def item(parent: ET.Element, kind: str, name: str) -> ET.Element:
        nonlocal counter
        counter += 1
        result = ET.SubElement(parent, "Item", {"class": kind, "referent": f"RBX{counter:032X}"})
        props = ET.SubElement(result, "Properties")
        ET.SubElement(props, "string", name="Name").text = name
        return result

    def add_directory(directory: Path, parent: ET.Element, top: bool = False) -> None:
        nonlocal count
        names: set[str] = set()
        for path in sorted(directory.iterdir()):
            if path.is_dir():
                if top and path.name not in SERVICES:
                    raise ValueError(f"Unsupported root service: {path.name}")
                name = path.name
                kind = name if top else SPECIAL_CONTAINERS.get(name, "Folder")
                node = item(parent, kind, name)
                add_directory(path, node)
            elif path.suffix == ".lua":
                name, kind = script_type(path)
                node = item(parent, kind, name)
                ET.SubElement(node.find("Properties"), "ProtectedString", name="Source").text = path.read_text(encoding="utf-8")
                count += 1
            else:
                continue
            if name in names:
                raise ValueError(f"Duplicate Roblox name in {directory}: {name}")
            names.add(name)

    add_directory(source, root, top=True)
    if not count:
        raise ValueError("No scripts found")
    output.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(root).write(output, encoding="utf-8", xml_declaration=True)
    # Validate serialized content, including source escaping, against the actual files.
    serialized = ET.parse(output).getroot()
    found = [p.text or "" for p in serialized.findall(".//ProtectedString[@name='Source']")]
    expected = [p.read_text(encoding="utf-8") for p in source.rglob("*.lua")]
    if sorted(found) != sorted(expected):
        raise RuntimeError("Serialized sources differ from source files")
    return count


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", nargs="?", type=Path, default=Path("src"))
    parser.add_argument("output", nargs="?", type=Path, default=Path("dist/LittleLife_Marco5_4.rbxlx"))
    args = parser.parse_args()
    count = build(args.source, args.output)
    print(f"Built {args.output}: {count} scripts, source round-trip verified.")
