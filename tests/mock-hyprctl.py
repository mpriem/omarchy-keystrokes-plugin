#!/usr/bin/env python3
"""Isolated QML fixture; never contacts Hyprland or captures real input."""
import os
from pathlib import Path
import re
import subprocess
import sys
import time

runtime = Path(os.environ['XDG_RUNTIME_DIR'])
mode = os.environ.get('TEST_MODE', '')
shortcut = 'SUPER + SHIFT + J' if mode == 'custom' else '' if mode == 'unbound' else 'SUPER + SHIFT + K'
if sys.argv[1] == 'produce':
    token = sys.argv[2]
    pause_reason = sys.argv[3]
    folder = runtime / ('omarchy-keystrokes.' + token)
    sequence = 0
    deadline = time.monotonic() + 10
    while folder.exists() and time.monotonic() < deadline:
        if sequence:
            try:
                ack = (folder / 'ack').read_text()
            except FileNotFoundError:
                break
            if ack != f'{token} {sequence}\n':
                time.sleep(.005)
                continue
        sequence += 1
        if os.environ.get('TEST_MODE') == 'stalled' and sequence > 4:
            break
        state = 'waiting' if sequence == 1 else 'on'
        if pause_reason and sequence >= 3:
            state = pause_reason
        binding = 'b ' + shortcut if shortcut else 'b'
        data = f'keystrokes-v5 {token} {state} 0 {sequence}\n{binding}\n'
        if state == 'on':
            data += 'p 38 1 0\n' * (3 if mode == 'batch' else 1)
        try:
            with (folder / 'spare').open('r+') as f:
                f.write(data.ljust(2048))
            if mode == 'ack-fail': (folder / 'ack').chmod(0o400)
            (folder / 'events').rename(folder / 'retired')
            if mode == 'watch-retry': time.sleep(.05)
            (folder / 'spare').rename(folder / 'events')
            (folder / 'retired').rename(folder / 'spare')
        except FileNotFoundError:
            break
        time.sleep(.02)
    sys.exit(0)

with (runtime / 'hyprctl-calls').open('a') as f:
    f.write(sys.argv[1] + '\n')
code = sys.argv[2]
if 'Keystrokes.start(' in code:
    if mode == 'start-timeout': time.sleep(4)
    if mode in ['cancel-start', 'restart', 'config-start', 'late']: time.sleep(.15)
    token = re.search(r'Keystrokes.start\(\[\[\n([A-Za-z0-9]{12})\]\]', code)[1]
    reason = 'sudo' if mode in ['custom', 'unbound', 'entry-lifecycle'] else mode
    marker = runtime / ('pause-once-' + mode)
    if reason not in ['sudo', 'polkit'] or marker.exists():
        reason = ''
    else:
        marker.touch()
    subprocess.Popen([sys.executable, __file__, 'produce', token, reason], stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print('keystrokes-v5 waiting')
elif 'Keystrokes.shortcut' in code:
    print('ALT + F10' if mode == 'reload' and 'set(false)' not in code else shortcut)
else:
    if mode == 'cleanup-fail':
        for directory in runtime.glob('omarchy-keystrokes.*'): (directory / 'extra').touch()
    if mode == 'stop-timeout': time.sleep(4)
    if mode == 'stop-fail': sys.exit(1)
    print('keystrokes-v5 off')
