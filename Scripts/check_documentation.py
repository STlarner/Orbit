#!/usr/bin/env python3
"""Check documentation coverage for Orbit's source-declared iOS APIs."""

import argparse
import json
from pathlib import Path
from urllib.parse import unquote, urlparse


def check(graph_root, source_root):
    source_root = source_root.resolve()
    symbols = {}
    found_module = False
    for path in graph_root.glob("**/arm64-apple-ios-simulator/*.symbols.json"):
        graph = json.loads(path.read_text())
        if graph["module"]["name"] != "Orbit":
            continue
        found_module = True
        for symbol in graph["symbols"]:
            identifier = symbol["identifier"]["precise"]
            if symbol.get("accessLevel") not in {"public", "open"}:
                continue
            if "::SYNTHESIZED::" in identifier:
                continue
            uri = urlparse(symbol.get("location", {}).get("uri", ""))
            if uri.scheme != "file":
                continue
            source = Path(unquote(uri.path)).resolve()
            if source.is_relative_to(source_root):
                symbols[identifier] = (symbol, source)

    if not found_module or not symbols:
        raise SystemExit("Orbit's source-declared iOS symbol graph is missing")

    missing = []
    for symbol, source in symbols.values():
        comment = symbol.get("docComment", {}).get("lines", [])
        if not any(line.get("text", "").strip() for line in comment):
            line = symbol["location"]["position"]["line"] + 1
            name = ".".join(symbol["pathComponents"])
            missing.append(f"{source}:{line}: undocumented public API: {name}")
    for message in sorted(missing):
        print(message)
    print(f"Documented public API: {len(symbols) - len(missing)}/{len(symbols)}")
    if missing:
        raise SystemExit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("graph_root", type=Path)
    args = parser.parse_args()
    check(args.graph_root, Path(__file__).resolve().parents[1] / "Sources")
