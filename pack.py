import json
import os
import os.path as path
import re
from zipfile import ZipFile, ZIP_DEFLATED

with open("info.json") as f:
    info = json.load(f)

target = f"{info['name']}_{info['version']}.zip"

exclude = [
    target,  # ! important
    ".git",
    "screenshot.png",
    "README.md",
    "pack.py",
]

with ZipFile(target, "w", ZIP_DEFLATED) as z:
    d = path.dirname(path.realpath(__file__))
    for root, _, files in os.walk(d):
        for f in files:
            p = path.join(root, f)

            if all(re.match(re.escape(path.join(d, e)) + f'({re.escape(os.sep)}|$)', p) is None for e in exclude):
                z.write(p, path.relpath(p, path.join(d, "..")))
