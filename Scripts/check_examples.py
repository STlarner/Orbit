#!/usr/bin/env python3
"""Compile Swift examples from Orbit's README, API comments and DocC guides."""

import argparse
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
IMPORTS = "import Foundation\nimport SwiftUI\nimport Orbit\n"


def examples():
    paths = [ROOT / "README.md"] + sorted((ROOT / "Sources").rglob("*.swift"))
    paths += sorted((ROOT / "Sources").rglob("*.docc/*.md"))
    for path in paths:
        text = path.read_text()
        if path.suffix == ".swift":
            text = "\n".join(
                re.sub(r"^\s*/// ?", "", line)
                for line in text.splitlines()
                if line.lstrip().startswith("///")
            )
        tokens = re.finditer(
            r"<!--\s*swift-example:\s*(?P<start>[\w-]+)\s*-->"
            r"|(?P<end><!--\s*/swift-example\s*-->)"
            r"|```swift\n(?P<code>.*?)```",
            text, re.DOTALL,
        )
        group = None
        parts = []
        index = 0
        for token in tokens:
            if token.group("start"):
                if group is not None:
                    raise SystemExit(f"Nested Swift example group: {path}")
                group = token.group("start")
                parts = []
            elif token.group("end"):
                if group is None or not parts:
                    raise SystemExit(f"Unmatched or empty Swift example group: {path}")
                index += 1
                yield path, f"{index} ({group})", "\n\n".join(parts)
                group = None
            else:
                code = token.group("code")
                if not code.strip():
                    raise SystemExit(f"Empty Swift example: {path}")
                if group is not None:
                    parts.append(code)
                else:
                    index += 1
                    yield path, index, code
        if group is not None:
            raise SystemExit(f"Unclosed Swift example group: {path}: {group}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--documentation-build", type=Path, default=ROOT / ".build/documentation"
    )
    args = parser.parse_args()
    products = args.documentation_build.resolve() / (
        "derived-data/Build/Products/Debug-iphonesimulator"
    )
    if not (products / "Orbit.swiftmodule").is_dir():
        raise SystemExit("Build documentation before checking iOS examples")
    sdk = subprocess.check_output(
        ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True
    ).strip()
    count = 0
    with tempfile.TemporaryDirectory(
        prefix="examples-", dir=args.documentation_build.resolve()
    ) as directory:
        temp = Path(directory)
        for path, index, code in examples():
            print(f"Checking {path.relative_to(ROOT)} example {index}", flush=True)
            if code.lstrip().startswith(".package("):
                temp.joinpath("Package.swift").write_text(
                    "// swift-tools-version: 6.2\nimport PackageDescription\n"
                    'let package = Package(name: "Example", dependencies: [\n'
                    + code + "], targets: [])\n"
                )
                subprocess.run(
                    ["swift", "package", "--package-path", str(temp), "dump-package"],
                    check=True, stdout=subprocess.DEVNULL,
                )
            else:
                command = [
                    "xcrun", "swiftc", "-c", "-swift-version", "6", "-warnings-as-errors",
                    "-D", "DEBUG",
                    "-target", "arm64-apple-ios17.0-simulator", "-sdk", sdk,
                    "-I", str(products), "-module-name", "OrbitDocumentationExample",
                    "-o", str(temp / "Example.o"), "-",
                ]
                if "@main" in code:
                    command.insert(2, "-parse-as-library")
                subprocess.run(command, input=IMPORTS + code, text=True, check=True)
            count += 1
        demo = ROOT / "Examples/OrbitDemo.swift"
        print(f"Checking {demo.relative_to(ROOT)}", flush=True)
        subprocess.run([
            "xcrun", "swiftc", "-c", "-parse-as-library", "-swift-version", "6",
            "-warnings-as-errors",
            "-target", "arm64-apple-ios17.0-simulator", "-sdk", sdk, "-I", str(products),
            "-module-name", "OrbitDemoExample", "-o", str(temp / "Demo.o"), str(demo),
        ], check=True)
    if count == 0:
        raise SystemExit("No Swift documentation examples found")
    print(f"Compiled {count} documentation examples and the demo for iOS in Swift 6")


if __name__ == "__main__":
    main()
