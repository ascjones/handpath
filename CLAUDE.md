# HandPath — agent notes

Garmin Connect IQ watch app (Monkey C) measuring golf downswing direction
(IDDX). Read PLAN.md first: it documents known algorithm defects and the
improvement roadmap — don't rediscover them.

## Build & run

- `./build.sh [device]` — strict-typecheck (`-l 3`) build; default device
  `marq2` (the dev's watch, MARQ Golfer Gen 2).
- `./build.sh sim [device]` — build + deploy to the simulator.
- SDK at `~/.local/share/garmin-connectiq-sdk/9.2.0`, developer key at
  `~/.Garmin/ConnectIQ/developer_key.der` (override: `CIQ_SDK`, `CIQ_KEY`).
- Ubuntu 24.04 quirk: the simulator and SDK Manager need webkit2gtk-4.0
  compat libs via `LD_LIBRARY_PATH` (build.sh handles it; see
  `~/.local/share/garmin-connectiq-tools/bin/sdkmanager-run`).
- Device profiles are installed per-device via the SDK Manager GUI (needs
  Garmin login — only the user can do this). Missing profile ⇒
  "Invalid device id" from monkeyc.

## Code layout

- `source/SwingDetector.mc` — swing-phase state machine + IDDX computation.
  All the algorithm complexity lives here. Thresholds are in milli-G.
- `source/HandPathView.mc` — UI + sensor listener (25 Hz accel batches).
- `source/HandPathDelegate.mc` — buttons: START toggle, UP reset, BACK exit.
- `manifest.xml` — supported devices; add new ones here *and* download their
  profile before building with `-d`.

## Conventions

- Keep builds clean at `-w -l 3` (warnings + strictest typecheck).
- Simulator can't generate swing motion; algorithm changes need on-wrist
  testing or (planned, PLAN.md Phase 1) replay of recorded sensor data.
