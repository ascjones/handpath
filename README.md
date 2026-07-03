# HandPath

A Garmin Connect IQ watch app that measures **IDDX** (Initial Downswing
Direction) — the horizontal angle of your hands' travel over the first ~4
inches of the golf downswing, in the spirit of deWiz. Target range: +5° to
+15° (down the line, slightly from the inside).

The watch's accelerometer drives a swing-phase state machine (idle →
backswing → top → downswing); linear acceleration through the transition is
double-integrated and projected onto the horizontal plane to get the
direction of initial hand travel.

**Status: early prototype.** The current model has known accuracy
limitations; see [PLAN.md](PLAN.md) for defects and the improvement roadmap
(gyro-based orientation tracking, address calibration, real-data validation).

## Build

Requires the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/),
a developer key, and device profiles installed via the SDK Manager.

```sh
./build.sh              # build bin/HandPath-marq2.prg
./build.sh fenix7       # build for another device
./build.sh sim          # build + run in the simulator
```

Sideload: copy the `.prg` to `GARMIN/Apps/` on the watch over USB.

## Use

- **START** — begin/stop listening for swings
- **UP** — reset session
- **BACK** — stop and exit

Take a swing; the watch vibrates and shows the measured IDDX, color-coded
against the target range, with a running session average and history.
