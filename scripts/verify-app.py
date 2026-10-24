#!/usr/bin/env python3
"""Check the distributed bundle, including an offline source-host handshake."""

import json
from pathlib import Path
import plistlib
import selectors
import subprocess
import sys

app = Path(sys.argv[1]).resolve()
with (app / "Contents/Info.plist").open("rb") as file:
    info = plistlib.load(file)
assert info["CFBundleName"] == "Yuin"
resources = app / "Contents/Resources"
assert (resources / "AppIcon.icns").is_file()
core = resources / "MyMusic_MusicCore.bundle"
for language in ("en", "zh-Hans"):
    assert list(core.rglob(language + ".lproj/Localizable.strings")), language

host = app / "Contents/MacOS/MusicSourceHost"
process = subprocess.Popen(
    [str(host)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL, text=True, bufsize=1,
)
try:
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ)

        def exchange(command):
            process.stdin.write(json.dumps(command) + "\n")
            process.stdin.flush()
            if not selector.select(timeout=15):
                raise RuntimeError("Packaged source host did not respond")
            reply = json.loads(process.stdout.readline())
            assert reply["id"] == command["id"] and "error" not in reply, reply
            return reply["result"]

        result = exchange({
            "id": "init", "op": "init", "meta": {},
            "script": "lx.on('request',async()=> 'https://example.invalid/packaging.mp3');"
                      "lx.send('inited',{sources:{kw:{type:'music',"
                      "actions:['musicUrl'],qualitys:['128k']}}});",
        })
        assert result["sources"]["kw"]["qualitys"] == ["128k"]
        result = exchange({
            "id": "resolve", "op": "resolve", "source": "kw",
            "action": "musicUrl", "info": {"type": "128k", "musicInfo": {}},
        })
        assert result["url"] == "https://example.invalid/packaging.mp3"
finally:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
    process.stdin.close()
    process.stdout.close()

print("Verified packaged resources and offline source-host initialization/resolution")
