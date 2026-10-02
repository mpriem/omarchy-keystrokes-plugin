# Capture protocol 5

Transport is private tmpfs with a 12-character ASCII alphanumeric session token. The token identifies ownership and rejects stale sessions; it is not authentication against other code running as the same user. Each snapshot is exactly 2048 ASCII bytes, padded with spaces:

```
keystrokes-v5 TOKEN STATE GENERATION SEQUENCE
b OPTIONAL SHORTCUT
p CODE MODS 0
```

States are `waiting`, `on`, `sudo`, and `polkit`. Only `on` can carry events. There are at most 32 event lines, with XKB code 9–255 and modifier bits 0–15. The reserved repeat field remains `0`. The optional shortcut contains up to 128 printable ASCII characters. Generation is 0–2147483647; sequence is 1–2147483647. Producer capture stops at counter exhaustion and needs explicit restart with a fresh session; counters never wrap within a session.

The consumer ignores invalid/stale frames and clears history when generation changes. It writes `TOKEN SEQUENCE\n` to the existing private ACK file only while the current session is requested and healthy. The producer requires an ACK before enabling bindings. Only a matching new sequence renews the one-second lease. Off, pause, error, policy change and consumer destruction stop acknowledgement. Pause always needs explicit resumption.

Two pre-created mode-0600 snapshot inodes rotate through events/spare/retired. The consumer retries a transient rename gap after 20 ms. Producer ACK polling runs every 100 ms and idle publication at 200 ms; consumer freshness expires at 1500 ms. Events older than one second are discarded. Queue overload intentionally drops the oldest event; visible history is separately bounded to 1–10 strokes. No event spawns a subprocess.

Lua filters before queueing using Hyprland window class. The UI additionally hides based on Wayland app ID. Those identifiers and checks are intentionally separate. Lua serialization and frame decoding live in CaptureProtocol.js; keycaps and pause copy live in KeyLabels.js. tests/capture.lua writes a synthetic real-producer fixture that tests/protocol.js decodes.
