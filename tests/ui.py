#!/usr/bin/env python3
"""Load installed payload with actual host Ui/Commons in an isolated home."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import sys

repo = Path(__file__).resolve().parent.parent
mode = sys.argv[1] if len(sys.argv) > 1 else 'shared'
host = Path(os.environ.get('OMARCHY_SHELL_DIR', '/usr/share/omarchy/shell'))
assert (host / 'Ui').is_dir(), 'UI tier requires OMARCHY_SHELL_DIR with host Ui and Commons'
with tempfile.TemporaryDirectory(prefix='keystrokes-ui.') as temporary:
    root = Path(temporary)
    for name in ['Ui', 'Commons']:
        shutil.copytree(host / name, root / name)
    # Use the installer allowlist, with no extra checkout modules available.
    script = (repo / 'install.sh').read_text()
    payload = script.split('cp -a --parents -- ', 1)[1].split('"$stage/"', 1)[0].replace('\\\n', ' ').split()
    plugin = root / 'plugin'; plugin.mkdir()
    for name in payload:
        target = plugin / name; target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(repo / name, target)
    for file in plugin.glob('*'):
        if file.suffix not in ['.qml', '.js']: continue
        for local in re.findall(r'(?:import|\.import) "([^\"]+)"', file.read_text()):
            assert (file.parent / local).exists(), f'missing staged import: {local}'
    # Offscreen Qt has no layer-shell backend. Substitute only the window
    # platform adapter in these temporary copies; actual controls and plugin
    # model/persistence/rendering declarations remain exercised. Native mask,
    # focus and compositor behavior still require the documented smoke test.
    adapter = """FloatingWindow {
      property int exclusionMode
      property string testNamespace
      property int testLayer
      property int testKeyboardFocus
      implicitWidth: 1280
      implicitHeight: 720
"""
    for folder in [root / 'Ui', plugin]:
        for file in folder.glob('*.qml'):
            contents = file.read_text()
            if 'PanelWindow {' in contents:
                contents = re.sub(r'anchors\s*\{\s*top: true;?\s*bottom: true;?\s*left: true;?\s*right: true;?\s*\}', '', contents)
                file.write_text(contents.replace('PanelWindow {', adapter).replace('WlrLayershell.namespace', 'testNamespace').replace('WlrLayershell.layer', 'testLayer').replace('WlrLayershell.keyboardFocus', 'testKeyboardFocus'))
    shutil.copyfile(repo / ('tests/entry.qml' if mode == 'entry-lifecycle' else 'tests/ui.qml'), plugin / 'ui.qml')
    # Root shell must import QtQuick for Loader, and qs resolves from root.
    (root / 'shell.qml').write_text('import QtQuick\nimport Quickshell\nimport "plugin"\nShellRoot { Loader { source: "plugin/ui.qml" } }\n')
    bin_dir = root / 'bin'; bin_dir.mkdir()
    for command in ['hyprctl', 'omarchy-shell']:
        target = bin_dir / command
        target.write_text("#!/usr/bin/python3\nimport os, time, sys\nfrom pathlib import Path\n"
            "with (Path(os.environ['HOME']) / 'calls').open('a') as f: f.write(Path(sys.argv[0]).name + ' ' + ' '.join(sys.argv[1:]) + '\\n')\n"
            "if Path(sys.argv[0]).name == 'omarchy-shell':\n"
            "    if os.environ['TEST_MODE'] == 'fallback-timeout': time.sleep(4)\n"
            "    if os.environ['TEST_MODE'] == 'fallback-fail': sys.exit(1)\n"
            "print('{\"enabled\":false,\"requested\":false,\"error\":\"\",\"shortcut\":\"\"}')\n")
        target.chmod(0o700)
    if mode == 'entry-lifecycle':
        shutil.copyfile(repo / 'tests/mock-hyprctl.py', bin_dir / 'hyprctl')
    env = dict(os.environ, TEST_MODE=mode, HOME=temporary, XDG_RUNTIME_DIR=temporary,
               XDG_CONFIG_HOME=str(root/'config'), XDG_CACHE_HOME=str(root/'cache'),
               PATH=str(bin_dir)+':'+os.environ['PATH'], QT_QPA_PLATFORM='offscreen',
               QT_QPA_PLATFORMTHEME='generic', QT_STYLE_OVERRIDE='Fusion', QT_QUICK_BACKEND='software',
               DISPLAY='', WAYLAND_DISPLAY='', HYPRLAND_INSTANCE_SIGNATURE='isolated-test',
               DBUS_SESSION_BUS_ADDRESS='unix:path=/nonexistent')
    try:
        result = subprocess.run(['qs','--no-color','-p',str(root/'shell.qml')], env=env, text=True,capture_output=True,timeout=10)
    except subprocess.TimeoutExpired as exc:
        print(exc.stdout, exc.stderr)
        raise
    output = result.stdout + result.stderr
    print(output)
    assert result.returncode == 0 and 'PASS: QML full' in output, output
    assert not any(s in output for s in ['ReferenceError:', 'TypeError:', 'Error: ', 'Binding loop detected', 'Failed to load configuration']), output

    calls = (root / 'calls').read_text().splitlines() if (root / 'calls').exists() else []
    status_calls = sum(line == 'omarchy-shell markpriem.keystrokes state' for line in calls)
    if mode == 'shared': assert status_calls == 0, calls
    elif mode == 'fallback': assert 9 <= status_calls <= 15, calls
    if mode == 'entry-lifecycle':
        assert not list(root.glob('omarchy-keystrokes.*')), 'session files retained after close'
    else:
        print(f'MEASURE: {mode}: {status_calls} status subprocesses / 3 widgets / 3.3 seconds')
