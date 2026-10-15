"""Smoke-test the signed app, including dyld, with isolated data and no UI checks."""
import os
import pathlib
import subprocess
import sys
import tempfile
import time

app = pathlib.Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='keepy-launch-test-') as scratch:
    with open(pathlib.Path(scratch) / 'launch.log', 'w+') as log:
        child = subprocess.Popen(
            [str(app / 'Contents/MacOS/keepy'), '--hidden'],
            env={**os.environ, 'KEEPY_DATA_DIR': str(pathlib.Path(scratch) / 'data')},
            stdout=log, stderr=log,
        )
        try:
            time.sleep(2)
            if child.poll() is not None:
                log.seek(0)
                raise RuntimeError(f'Signed application failed to launch ({child.returncode}):\n{log.read()}')
            print('Signed bundle launch passed: application and Sparkle loaded successfully.')
        finally:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
