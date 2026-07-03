# HandPath Improvement Plan

## Current state (as of commit d393ed7)

A working Connect IQ watch app that estimates **IDDX** (Initial Downswing
Direction, à la Dewiz): the horizontal angle of hand travel over the first
~4 inches of the downswing. Target range +5° to +15°.

- `SwingDetector.mc` — 5-phase state machine (IDLE → BACKSWING → TOP →
  DOWNSWING → COMPLETE) driven by smoothed dynamic-acceleration magnitude
  thresholds on 25 Hz accelerometer batches. Gravity is estimated at the top
  of the backswing, linear acceleration is double-integrated over 5 samples
  (~200 ms) in the *watch body frame*, projected onto the horizontal plane,
  and the angle is measured against a "forward" reference derived from
  cross(gravity, watch-Y-axis).
- `HandPathView.mc` — live UI: phase dot, big color-coded IDDX readout,
  feedback text, session average, history dots, live G meter, vibration.
- Builds clean under SDK 9.2.0 at strict typecheck (`-l 3`), device-independent
  target. No device profiles installed yet, so no simulator/sideload builds.

## Known defects in the current model

Ordered by severity.

### D1. Stale-gravity race (correctness bug, quick fix)
`PHASE_TOP` transitions to `PHASE_DOWNSWING` when `smoothed >
_downswingStartThreshold && _gravityVec != null`. But `_gravityVec` is
*always* non-null after any idle time (the resting-gravity filter assigns
it), so the downswing can start before `_topSamples` reaches its target of 4.
When that happens, IDDX is computed against the **address-orientation**
gravity vector — the watch has rotated ~90° since then, so the horizontal
plane is wrong by up to 90° and the output is garbage.
**Fix:** require `_topSamples.size() >= _topSampleTarget` in the transition,
or track a `_topGravityValid` flag.

### D2. Body-frame integration ignores wrist rotation (fundamental)
Acceleration samples are integrated in the rotating watch frame. During the
transition the forearm/wrist rotates tens of degrees within the 200 ms
integration window, so summed body-frame samples do not represent a
displacement vector in any fixed frame. This is the dominant error source.
**Fix:** enable the gyroscope stream, integrate angular velocity into an
orientation (quaternion) relative to the top-of-backswing frame, rotate each
accel sample into that fixed frame before subtracting gravity and
integrating. (`Sensor.registerSensorDataListener` supports
`:gyroscope => {:enabled => true}`; `GyroscopeData` delivers x/y/z in deg/s.)

### D3. Arbitrary target-line reference (fundamental)
The 0° reference assumes the watch Y axis (along the forearm) points down the
target line at the top. That varies with anatomy, grip, watch position, and
swing length — easily ±20°, which is larger than the entire IDDX target
window. **Fix:** establish the target line at *address* (a calibration
moment when orientation is known and repeatable), then carry it to the top
via gyro orientation tracking through the backswing. Optionally an explicit
one-time calibration screen.

### D4. No phase timeouts (robustness)
An aborted swing leaves the machine stuck in BACKSWING or TOP; the next
motion (walking, a waggle) then gets "measured" as a downswing.
**Fix:** timeout every non-idle phase (e.g. BACKSWING > 3 s, TOP > 1.5 s,
DOWNSWING > 0.5 s → reset to IDLE).

### D5. 25 Hz sampling is coarse for a 100–200 ms event
5 samples cover the whole measurement window; one sample of jitter is 20% of
the signal. Devices in the manifest support higher rates.
**Fix:** query `getMaxSampleRateForSensorType(:accelerometer)` and request
100 Hz where available, falling back to 25 Hz; scale all sample-count
thresholds by the actual rate. Also switch the integration stop condition
from "5 samples" to "estimated displacement ≈ 4 in" using real units
(mG → m/s², dt = 1/rate).

### D6. Minor issues
- `_gravityVec = _restGravity` aliases the arrays — later in-place updates of
  one mutate the other. Copy instead.
- The "trapezoidal integration" comment describes rectangular (Euler)
  integration.
- Gravity subtraction during BACKSWING uses the address-orientation estimate
  while the watch rotates, so the "dynamic magnitude" used for phase
  thresholds conflates rotation with motion (works, but thresholds are
  fragile because of it).
- No handedness setting: a left-handed golfer (or trail-wrist wearer) gets a
  sign-flipped IDDX.

## Improvement plan

### Phase 0 — Tooling (enables everything else)
1. Install device profiles via the Connect IQ SDK Manager
   (`~/.local/share/garmin-connectiq-tools/bin/sdkmanager`, needs Garmin
   login) so `-d fenix7` etc. work → simulator runs and sideloadable builds.
2. Add `build.sh` (or a Makefile): debug/release/device-matrix builds with
   the strict typecheck flag; document sideload path (copy `.prg` to
   `GARMIN/Apps` over USB).
3. Add `Toybox.Test` unit-test scaffolding (`monkeyc -t`) so detector logic
   can be exercised with canned sample arrays in the simulator.

### Phase 1 — Data capture & offline harness (highest leverage)
Real recorded swings are the prerequisite for every algorithm improvement.
1. Add a **record mode** to the app: dump raw accel(+gyro) batches for each
   detected swing (plus pre/post context) using `SensorLogging.SensorLogger`
   into FIT files, or serialize to `Application.Storage` for export.
2. Build a small **Python harness**: parse the logs, port the detector 1:1,
   replay recorded swings, plot phase transitions and integrated paths.
   Tune in Python, then mirror changes back into Monkey C.
3. Collect a labeled dataset: range session with slow-mo down-the-line phone
   video as ground truth (and/or a Dewiz/HackMotion for comparison). Tag
   each swing: real IDDX-ish direction, club, full/partial swing, plus
   negatives (practice swings, waggles, walking, club twirls).

### Phase 2 — Algorithm v2: orientation-aware IDDX
1. Fix **D1** (top-gravity guard) and **D4** (timeouts) immediately — small,
   independent of the rest.
2. Enable the gyroscope stream; raise sampling to the device max (**D5**).
3. Track orientation with a quaternion integrated from gyro angular velocity,
   zeroed at the top of the backswing; rotate accel samples into that fixed
   frame before gravity subtraction and integration (**D2**).
4. Detect the top from the **gyro signal** (angular-velocity reversal /
   minimum) instead of accel-magnitude dips — a far more distinctive marker
   of transition than "dynamic accel got quiet".
5. Integrate until ~4 inches of estimated displacement in real units rather
   than a fixed sample count.
6. Validate against the Phase 1 dataset; report repeatability (std-dev of
   IDDX across similar swings) before/after.

### Phase 3 — Calibration & personalization
1. Settings: handedness, watch on lead/trail wrist (sign conventions),
   target IDDX range.
2. Address-based target-line calibration: capture orientation during the
   still moment at address, carry it through the backswing via the gyro
   quaternion so the 0° reference at the top is the *actual* target line
   (**D3**). Fall back to the current Y-axis heuristic when calibration is
   unavailable.
3. Persist settings and session history with `Application.Storage`.

### Phase 4 — Validation & tuning
1. Range protocol: N swings per club × several sessions; compare app IDDX to
   video ground truth; measure bias, variance, and false-trigger rate.
2. Tune phase thresholds per the labeled negatives (practice swings must not
   count, or be counted separately).
3. Decide honest accuracy claims (this drives whether the display should be
   a number, a 3-bucket "inside / slot / outside", or a trend arrow).

### Phase 5 — Product polish (after the number is trustworthy)
- Session summary screen, per-club tracking, trend over sessions.
- Audio/vibe feedback profiles (immediate "in the slot" buzz patterns).
- Touch support for Venu-class devices (current delegate is button-only).
- Optional ActivityRecording/FIT developer fields so swings land in Garmin
  Connect.
- Store listing (beta) once validated.

## Suggested order of work
1. Phase 0.1–0.2 (device profiles + build script) — minutes-to-hours.
2. D1 + D4 quick fixes with unit tests — small, immediate correctness win.
3. Phase 1 record mode + Python harness — the unlock for everything else.
4. Phase 2 orientation-aware rewrite, tuned against real data.
5. Phases 3–5 in order.
