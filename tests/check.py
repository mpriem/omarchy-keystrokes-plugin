#!/usr/bin/env python3
"""One entry point; desktop dependencies are explicit and never silently skipped."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

repo = Path(__file__).resolve().parent.parent
os.chdir(repo)
parser = argparse.ArgumentParser()
parser.add_argument('--portable', action='store_true')
args = parser.parse_args()
def run(*command):
    subprocess.run(command, check=True)
run('bash', '-n', 'runtime.sh', 'install.sh')
run('luac', '-p', 'hypr/keystrokes.lua')
run(sys.executable, 'tests/run.py', *(['--portable'] if args.portable else []))
if args.portable:
    print('SKIP: installer and full QML composition (--portable)')
else:
    for dependency in ['qs', 'rsync', 'omarchy-plugin-validate']:
        assert shutil.which(dependency), f'missing desktop dependency: {dependency}; use --portable to skip explicitly'
    run(sys.executable, 'tests/install.py')
    for mode in ['shared', 'fallback', 'fallback-fail', 'fallback-timeout', 'entry-lifecycle']:
        run(sys.executable, 'tests/ui.py', mode)
print('PASS: all requested test tiers')
