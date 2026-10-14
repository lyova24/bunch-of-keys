#!/usr/bin/env python3
"""Create disposable screenshot data through the real bundled vault service."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "target/docs-demo"
APP = ROOT / "target/macos" / os.uname().machine / "Keepy.app"
PASSWORD = "documentation-demo-password"


def main():
    # Refuse existing directories, including symlinks: never overwrite a vault.
    DATA.mkdir(parents=True, exist_ok=False)
    environment = dict(os.environ, KEEPY_DATA_DIR=str(DATA))
    with subprocess.Popen([str(APP / "Contents/MacOS/keepy-core")], env=environment,
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True) as core:
        sequence = 0

        def request(command, **arguments):
            nonlocal sequence
            sequence += 1
            core.stdin.write(json.dumps(dict(id=sequence, command=command, **arguments)) + "\n")
            core.stdin.flush()
            reply = json.loads(core.stdout.readline())
            if "error" in reply:
                raise RuntimeError(reply["error"])
            return reply["result"]

        request("create_vault", name="Documentation Demo", password=PASSWORD)
        request("update_settings", settings=dict(autostart=False, appearance="light",
                liquid_glass=False, auto_lock_seconds=3600, clipboard_clear_seconds=30))
        with tempfile.TemporaryDirectory(dir=ROOT / "target", prefix="docs-key-") as temporary:
            key = Path(temporary) / "demo"
            subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N",
                            "documentation-key-passphrase", "-C", "documentation-demo", "-f", str(key)], check=True)
            vault = request("add_ssh_key", name="Demo SSH Key", private_key=key.read_text())
        key_id = vault["ssh_keys"][0]["id"]
        vault = request("add_group", name="Work", tags=["blue"])
        group_id = vault["nodes"][0]["id"]
        vault = request("add_group", parent_id=group_id, name="Infrastructure", tags=["green"])
        nested_id = vault["nodes"][0]["children"][0]["id"]
        request("add_entry", parent_id=nested_id, name="Demo server", tags=["green", "blue"], fields=[
            dict(label="Username", kind="text", value="demo-user", masked=False),
            dict(label="Password", kind="secret", value="synthetic-password", masked=True),
            dict(label="Console", kind="url", value="https://example.com", masked=False),
            dict(label="SSH", kind="ssh", value="", masked=False,
                 ssh=dict(user="demo", address="server.example.invalid", port=22, key_id=key_id)),
        ])
        request("add_entry", parent_id=group_id, name="Demo account", tags=["purple"], fields=[
            dict(label="Email", kind="text", value="demo@example.com", masked=False),
            dict(label="Password", kind="secret", value="synthetic-account-password", masked=True),
        ])
        request("add_group", name="Personal", tags=["orange"])
        request("lock_vault")
        core.stdin.close()
        core.wait(timeout=5)
    print(f"Created disposable demo vault at {DATA}")
    print(f"Unlock password: {PASSWORD}")
    print("SSH passphrase: documentation-key-passphrase (cancel the connection prompt)")


if __name__ == "__main__":
    main()
