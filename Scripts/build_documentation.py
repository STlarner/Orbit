#!/usr/bin/env python3
"""Build Orbit's DocC reference and stage its GitHub Pages site."""

import argparse
import html
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile

from check_documentation import check


ROOT = Path(__file__).resolve().parents[1]
MARKER = ".orbit-documentation-generated"


def run(*arguments):
    command = [str(argument) for argument in arguments]
    print("+ " + shlex.join(command), flush=True)
    subprocess.run(command, cwd=ROOT, check=True)


def redirect(path, destination):
    escaped = html.escape(destination, quote=True)
    path.write_text(
        '<!doctype html><html lang="en"><meta charset="utf-8">'
        '<title>Orbit API reference</title>'
        f'<meta http-equiv="refresh" content="0;url={escaped}">'
        f'<a href="{escaped}">Open the Orbit API reference</a></html>\n'
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".build/documentation")
    parser.add_argument("--hosting-base-path", default="Orbit/api")
    parser.add_argument("--ref-label", default="main")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    names = ("Orbit.doccarchive", "site")
    for name in names:
        destination = output / name
        if destination.exists() and (
            destination.is_symlink() or not (destination / MARKER).is_file()
        ):
            raise SystemExit(
                f"Refusing to replace unrecognized output: {destination}. "
                "Choose a fresh --output directory."
            )

    commit = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
    ).strip()
    derived = output / "derived-data"
    flags = shlex.join([
        "--warnings-as-errors", "--experimental-documentation-coverage",
        "--checkout-path", str(ROOT), "--source-service", "github",
        "--source-service-base-url",
        f"https://github.com/STlarner/Orbit/blob/{commit}",
    ])
    run(
        "xcodebuild", "-quiet", "docbuild", "-scheme", "Orbit",
        "-configuration", "Debug", "-destination",
        "generic/platform=iOS Simulator", "-derivedDataPath", derived,
        "CODE_SIGNING_ALLOWED=NO", "DOCC_EXTRACT_EXTENSION_SYMBOLS=YES",
        f"DOCC_HOSTING_BASE_PATH={args.hosting_base_path}",
        f"OTHER_DOCC_FLAGS={flags}",
    )
    check(derived, ROOT / "Sources")
    product = derived / "Build/Products/Debug-iphonesimulator/Orbit.doccarchive"
    if not product.is_dir():
        raise SystemExit(f"Missing documentation archive: {product}")

    with tempfile.TemporaryDirectory(prefix="docc-stage-", dir=output) as temp:
        staging = Path(temp)
        archive = staging / "Orbit.doccarchive"
        shutil.copytree(product, archive)
        site = staging / "site"
        site.mkdir()
        api = site / "api"
        run(
            "xcrun", "docc", "process-archive", "transform-for-static-hosting",
            archive, "--output-path", api,
            "--hosting-base-path", args.hosting_base_path,
        )
        for page in (
            "documentation/orbit/index.html",
            "documentation/orbit/usageguide/index.html",
        ):
            if not (api / page).is_file():
                raise SystemExit(f"Missing static documentation page: {page}")
        redirect(api / "index.html", "documentation/orbit/")
        ref = html.escape(args.ref_label)
        site.joinpath("index.html").write_text(
            '<!doctype html><html lang="en"><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>Orbit documentation</title><main>'
            '<h1>Orbit documentation</h1>'
            f'<p>Generated from <strong>{ref}</strong>. '
            'The reference follows this branch rather than a release tag.</p>'
            '<p><a href="api/">API reference and usage guide</a></p>'
            f'<p>Source: <a href="https://github.com/STlarner/Orbit/tree/{commit}">'
            f'{commit[:12]}</a></p></main></html>\n'
        )
        site.joinpath(".nojekyll").touch()
        site.joinpath("build.json").write_text(json.dumps({
            "ref": args.ref_label, "commit": commit,
        }) + "\n")
        for name in names:
            staging.joinpath(name, MARKER).touch()
            destination = output / name
            if destination.exists():
                destination.rename(staging / f"previous-{name}")
            staging.joinpath(name).rename(destination)
    print(f"Documentation site: {output / 'site'}")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
