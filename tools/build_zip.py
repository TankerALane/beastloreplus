#!/usr/bin/env python3
"""Build an install zip (dist/BeastLorePlus-<version>.zip) with the same layout as a release.

Standard library only. The zip holds one BeastLorePlus/ folder: the TOC (with @project-version@
replaced), the Lua files, Data/, Media/, Libs/ and LICENSE. Libs/ must exist locally: run
tools/install_local.ps1 once (it fills Libs/ from other installed addons).

Usage:  python tools/build_zip.py 1.0.0
"""
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "BeastLorePlus"


def main(argv):
    version = argv[0] if argv else "dev"
    if not os.path.isdir(os.path.join(ROOT, "Libs")):
        print("Libs/ is missing: run tools/install_local.ps1 first.")
        return 1
    files = [f for f in os.listdir(ROOT) if f.endswith(".lua")] + ["LICENSE"]
    for folder in ("Data", "Media", "Libs"):
        for base, _, names in os.walk(os.path.join(ROOT, folder)):
            for n in names:
                files.append(os.path.relpath(os.path.join(base, n), ROOT))
    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    out = os.path.join(ROOT, "dist", "%s-%s.zip" % (NAME, version))
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        with open(os.path.join(ROOT, NAME + ".toc"), encoding="utf-8") as fh:
            toc = fh.read().replace("@project-version@", version)
        z.writestr("%s/%s.toc" % (NAME, NAME), toc)
        for f in sorted(files):
            z.write(os.path.join(ROOT, f), "%s/%s" % (NAME, f.replace(os.sep, "/")))
    print("wrote", out, "(%d files)" % (len(files) + 1))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
