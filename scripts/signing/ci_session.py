#!/usr/bin/env python3
"""Publish a public one-use recipient, then wait for its encrypted envelope."""
import base64
import json
import os
from pathlib import Path
import subprocess
import time

repo = "dr-askar/raff-app"
branch = "raff-signing-transfer"
session = os.environ["GITHUB_RUN_ID"]
directory = Path(os.environ["RUNNER_TEMP"]) / "raff-sign"
path = f"session-{session}/recipient.json"
body = dict(message="[publish-only] Publish one-use signing recipient",
            branch=branch, content=base64.b64encode((directory / "recipient.json").read_bytes()).decode())
result = subprocess.run(["gh", "api", f"repos/{repo}/contents/{path}", "--method", "PUT",
                         "--input", "-"], input=json.dumps(body), capture_output=True, text=True)
if result.returncode:
    raise SystemExit("Could not publish public signing recipient")
print("Public recipient ready for session", session, flush=True)
deadline = time.monotonic() + 1200
while time.monotonic() < deadline:
    result = subprocess.run(["gh", "api", f"repos/{repo}/contents/session-{session}/request.json?ref={branch}",
                             "-H", "Accept: application/vnd.github.raw+json"],
                            capture_output=True, text=True)
    if result.returncode == 0:
        value = json.loads(result.stdout)
        if value.get("context", {}).get("session") != session:
            raise SystemExit("Wrong signing session")
        (directory / "request.json").write_text(json.dumps(value))
        print("Encrypted signing envelope received.", flush=True)
        break
    time.sleep(2)
else:
    raise SystemExit("Signing envelope timed out; temporary recipient will be destroyed")
