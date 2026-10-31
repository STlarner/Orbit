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
        for index, code in enumerate(
            re.findall(r"```swift\n(.*?)```", text, re.DOTALL), start=1
        ):
            if not code.strip():
                raise SystemExit(f"Empty Swift example: {path}:{index}")
            yield path, index, code


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
