# Validation

Run `python3 tests/check.py` from a checkout. No test installs into the real home, calls the live compositor, or captures real input. Runtime tests require tmpfs TMPDIR (the tested Omarchy host uses tmpfs /tmp). Home/runtime/cache directories are isolated and Hyprland/control commands are mocked.

`TMPDIR=/dev/shm python3 tests/check.py --portable` runs Lua policy/I/O, JavaScript config/protocol/history, shell syntax and private-file checks without desktop prerequisites. Skipped tiers are printed explicitly.

The desktop tier additionally needs Quickshell, Qt Quick, rsync, jq, the actual `omarchy-plugin-validate`, and Omarchy shell Ui/Commons at `/usr/share/omarchy/shell` (override `OMARCHY_SHELL_DIR`). Tested environment: Omarchy 4.0.4-1, Hyprland 0.56.2-2, Quickshell 0.3.1-1, Qt 6.11.2, Lua 5.5.1-1, Node 24.21.0, Python 3.14.7, rsync 3.5.0. The tests use only Lua features compatible with 5.4.

The capture harness requires zero subprocess exit, a completion marker, and no script errors or binding loops. The composition harness stages exactly the installer allowlist and checks local imports. It uses actual host UI components, but temporary test copies substitute FloatingWindow for native layer-shell windows because offscreen Qt has no PanelWindow backend. It cannot establish native input masks, IPC-server availability, focus/lock ordering, or screenshot equivalence. Known offscreen socket/mask messages are tolerated; script errors are not.

The entry lifecycle test uses a synthetic producer to check the panel entry's `open()`, `close()`, and `opened` contract, including repeated summon/hide, a visible pause prompt, reopening, and transport cleanup.

Before release, run a native desktop smoke test with synthetic, nonsecret input: toggle via keyboard/panel/IPC, cancel startup, test both display orders and repeated strokes, every placement/size, focused/all/disconnected monitors and hotplug, privacy/focus clear, click-through strokes, clickable sudo pause and explicit resume, actual polkit mapping, lock/unlock, and failed configuration/save recovery. Record host versions and screenshots. This refactor has not performed that live-desktop test.

Status measurement: with three widgets for 3.3 seconds, the IPC fallback launches 12 status processes; the shared-engine path launches zero. Shared state changes propagate immediately, and separately hosted widgets retain the existing one-second polling interval with a two-second deadline. This measures process count only, not CPU, memory or end-to-end display latency; no lease, retention or event transport thresholds were tuned.
