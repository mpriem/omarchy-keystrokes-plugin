#!/usr/bin/env python3
"""No live compositor calls. Uses private tmpfs directories and synthetic input."""
import os
import argparse
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import time

repo = Path(__file__).resolve().parent.parent
os.chdir(repo)
parser = argparse.ArgumentParser()
parser.add_argument('--portable', action='store_true', help='Lua, JS and runtime only; explicitly skip QML')
args = parser.parse_args()

def run(args, env, **kwargs):
    return subprocess.run(args, env=env, text=True, check=True, **kwargs)

with tempfile.TemporaryDirectory(prefix='keystrokes-test.') as temporary:
    runtime = Path(temporary)
    env = dict(os.environ, XDG_RUNTIME_DIR=temporary, KEYSTROKES_TEST='1')
    assert run(['stat', '-f', '-c', '%T', temporary], env, capture_output=True).stdout.strip() == 'tmpfs', 'Tests require tmpfs TMPDIR'
    run(['lua', 'tests/capture.lua'], env)
    run(['node', 'tests/config.js'], env)
    run(['node', 'tests/history.js'], env)
    run(['node', 'tests/protocol.js'], env)
    run(['lua', str(runtime / 'quoted.lua')], env)
    folder = Path(run(['bash', 'runtime.sh', 'create'], env, capture_output=True).stdout.strip())
    assert stat.S_IMODE(folder.stat().st_mode) == 0o700
    for child in folder.iterdir():
        assert stat.S_IMODE(child.stat().st_mode) == 0o600
    run(['bash', 'runtime.sh', 'remove', str(folder)], env)
    assert not folder.exists()
    def rejected(args, test_env=env):
        assert subprocess.run(['bash', 'runtime.sh', *args], env=test_env, capture_output=True).returncode != 0
    rejected(['create'], dict(env, XDG_RUNTIME_DIR=''))
    runtime.chmod(0o755)
    rejected(['create'])
    runtime.chmod(0o700)
    rejected(['remove', temporary])
    link = runtime / 'omarchy-keystrokes.ABCDEFGHIJKL'
    target = runtime / 'untouched'
    target.mkdir()
    (target / 'events').write_text('do not delete')
    link.symlink_to(target, target_is_directory=True)
    rejected(['remove', str(link)])
    assert (target / 'events').read_text() == 'do not delete'
    link.unlink()
    folder = Path(run(['bash', 'runtime.sh', 'create'], env, capture_output=True).stdout.strip())
    (folder / 'events').write_text('synthetic fixture'.ljust(2048))
    (folder / 'extra').touch()
    with (folder / 'events').open() as reader:
        rejected(['remove', str(folder)])
        assert reader.read() == ' ' * 2048, 'open inode not scrubbed'
    assert folder.exists() and (folder / 'extra').exists()
    (folder / 'extra').unlink()
    run(['bash', 'runtime.sh', 'remove', str(folder)], env)
    run(['bash', 'runtime.sh', 'remove', str(folder)], env)
    print('PASS: private permissions, invalid runtime rejection and symlink-safe removal', flush=True)
    if args.portable:
        print('SKIP: isolated QML tier (--portable)')
        raise SystemExit(0)
    bin_dir = runtime / 'bin'
    bin_dir.mkdir()
    shutil.copyfile('tests/mock-hyprctl.py', bin_dir / 'hyprctl')
    (bin_dir / 'hyprctl').chmod(0o700)
    harness = runtime / 'harness'
    harness.mkdir()
    for name in ['Capture.qml', 'CaptureProtocol.js', 'SettingsFile.qml', 'Config.js', 'KeyLabels.js', 'runtime.sh']:
        shutil.copyfile(repo / name, harness / name)
    shutil.copyfile('tests/shell.qml', harness / 'shell.qml')
    shutil.copyfile('tests/lifecycle.qml', harness / 'lifecycle.qml')
    shutil.copyfile('tests/settings.qml', harness / 'settings.qml')
    lifecycle_modes = ['cancel-create', 'cancel-start', 'restart', 'config-start', 'late', 'batch', 'start-timeout', 'stop-fail', 'stop-timeout', 'destroy', 'destroy-create', 'cleanup-fail', 'ack-fail', 'watch-retry']
    for mode in ['settings'] + lifecycle_modes + ['normal', 'stalled', 'sudo', 'polkit', 'custom', 'unbound', 'reload']:
        test_env = dict(env, PATH=str(bin_dir) + ':' + os.environ['PATH'], QT_QPA_PLATFORM='offscreen',
                        QT_QPA_PLATFORMTHEME='generic', QT_STYLE_OVERRIDE='Fusion', QT_QUICK_BACKEND='software',
                        DISPLAY='', DBUS_SESSION_BUS_ADDRESS='unix:path=/nonexistent', TEST_MODE=mode, XDG_CACHE_HOME=str(runtime / 'cache'), XDG_CONFIG_HOME=str(runtime / 'config'),
                        HOME=temporary, HYPRLAND_INSTANCE_SIGNATURE='isolated-test', WAYLAND_DISPLAY='invalid-test')
        result = subprocess.run(['qs', '--no-color', '-p', str(harness / ('settings.qml' if mode == 'settings' else 'lifecycle.qml' if mode in lifecycle_modes else 'shell.qml'))], env=test_env, text=True, capture_output=True, timeout=12)
        output = result.stdout + result.stderr
        assert result.returncode == 0, output
        assert not any(message in output for message in ['ReferenceError:', 'TypeError:', 'Error: ', 'Binding loop detected']), output
        assert 'PASS: QML' in output and 'FAIL:' not in output and 'Failed to load configuration' not in output, output
        print(output.strip(), flush=True)
        if mode in ['destroy', 'destroy-create', 'cleanup-fail', 'ack-fail', 'watch-retry']:
            for attempt in range(100):
                if not list(runtime.glob('omarchy-keystrokes.*')): break
                time.sleep(.05)
        assert not list(runtime.glob('omarchy-keystrokes.*')), 'session files retained'
        if mode == 'settings':
            (runtime / 'hyprctl-calls').unlink(missing_ok=True)
            continue
        calls = (runtime / 'hyprctl-calls').read_text().splitlines()
        expected = ['repl', 'repl'] if mode == 'reload' else ['repl', 'repl', 'repl'] + (['repl', 'repl'] if mode in ['sudo', 'polkit', 'custom', 'unbound'] else [])
        if mode not in lifecycle_modes: assert calls == expected, calls
        (runtime / 'hyprctl-calls').unlink()
print('All isolated security and QML integration checks passed.')
