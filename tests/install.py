#!/usr/bin/env python3
"""Exercise the optional installer with a temporary HOME and mocked shell CLI."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='keystrokes-install-test.') as temporary:
    root = Path(temporary)
    checkout = root / 'checkout'
    shutil.copytree(repo, checkout, ignore=shutil.ignore_patterns('.git'))
    (checkout / '.env').write_text('fixture must not be installed')
    home = root / 'home'
    home.mkdir()
    bin_dir = root / 'bin'
    bin_dir.mkdir()
    for name in ['omarchy', 'omarchy-shell']:
        command = bin_dir / name
        command.write_text('#!/bin/bash\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$HOME/calls"\nif [[ $* == "plugin list" ]]; then echo "markpriem.keystrokes enabled"; fi\n')
        command.chmod(0o700)
    env = dict(os.environ, HOME=str(home), PATH=str(bin_dir) + ':' + os.environ['PATH'])
    def install(*args):
        return subprocess.run(['bash', str(checkout / 'install.sh'), *args], env=env, text=True, capture_output=True, stdin=subprocess.DEVNULL)
    result = install()
    assert result.returncode == 0, result.stderr
    dest = home / '.config/omarchy/plugins/markpriem.keystrokes'
    assert (dest / 'runtime.sh').exists() and (dest / 'Capture.qml').exists()
    assert not (dest / '.env').exists() and not (dest / 'tests').exists()
    (dest / 'keep-me').write_text('existing file')
    (dest / '.git').mkdir()
    (dest / '.git/fixture').write_text('git metadata')
    assert install().returncode != 0
    assert (dest / 'keep-me').read_text() == 'existing file'
    result = install('--replace')
    assert result.returncode == 0, result.stderr
    assert not (dest / 'keep-me').exists()
    assert (dest / '.git/fixture').read_text() == 'git metadata'
    # Simulate an interrupted in-place replacement, then verify documented
    # recovery by rerunning the same validated payload and preserving Git.
    interrupted = bin_dir / 'rsync'
    interrupted.write_text('#!/bin/bash\ndestination=${@: -1}\nprintf interrupted > "$destination/Config.js"\nexit 23\n')
    interrupted.chmod(0o700)
    assert install('--replace').returncode == 23
    assert (dest / 'Config.js').read_text() == 'interrupted'
    assert (dest / '.git/fixture').read_text() == 'git metadata'
    interrupted.unlink()
    assert install('--replace').returncode == 0
    assert (dest / 'Config.js').read_bytes() == (checkout / 'Config.js').read_bytes()
    before = (dest / 'manifest.json').read_bytes()
    (checkout / 'manifest.json').write_text('{}')
    assert install('--replace').returncode != 0
    assert (dest / 'manifest.json').read_bytes() == before
    assert 'plugin enable' not in (home / 'calls').read_text(), 'existing placement changed'
    assert not (home / '.config/hypr').exists()
print('PASS: optional installer allowlist, consent, prevalidation and Git preservation')
