# Deploying and accuracy testing

## Deploy to the watch (MARQ 2)

1. `./build.sh` — produces `bin/HandPath-marq2.prg`.
2. Plug the watch in over USB; it mounts as an MTP device.
3. Copy the `.prg` to `Internal Storage/GARMIN/Apps/` — via the file
   manager, or:
   ```sh
   cp bin/HandPath-marq2.prg /run/user/1000/gvfs/mtp*/Internal*/GARMIN/Apps/
   ```
4. Eject and unplug. HandPath appears at the bottom of the apps list
   (START button → scroll down).

Each iteration is build → copy → unplug. No re-pairing or app store.

## Accuracy testing against deWiz

The deWiz is the ground-truth reference: wear it and the watch on the lead
wrist simultaneously and compare IDDX numbers per swing.

### Setup

- Watch in its normal spot, deWiz beside it. Keep placement identical
  across sessions and note it once in the CSV — placement shifts readings.
- Before the first session, make sure known correctness bugs (PLAN.md D1,
  D4) are fixed — otherwise the dataset contains unexplainable outliers.

### Session protocol (~20–30 min)

- One club per session block (start with 7-iron), 20+ full swings.
- After each swing: the watch shows its IDDX on screen, the deWiz app shows
  its number. Record the pair.
- Deliberately mix in 5–10 practice swings/waggles and walk around between
  balls; log whether the watch correctly ignored them. The false-trigger
  rate matters as much as accuracy.
- Later sessions: driver and a wedge — swing length changes the
  top-of-backswing geometry, where the model is most likely to drift.

### Recording

CSV per session, columns per `data/TEMPLATE.csv`:

```
swing,club,swing_type,watch_iddx,dewiz_iddx,notes
```

`swing_type`: `full` | `partial` | `practice` | `none` (non-swing motion).
Leave a reading blank when that device recorded nothing.

On the range, either fill a Google Sheet on the phone, or faster: voice
memo ("five, watch twelve, deWiz nine") and transcribe at home into
`data/YYYY-MM-DD-<club>.csv`.

### Analysis

```sh
python3 scripts/compare.py data/2026-07-05-7i.csv
```

Reports bias, scatter (sd), MAE, and correlation per club, plus
missed-swing / false-trigger counts and the worst disagreements.

### Interpreting the numbers

- **Consistent bias** (e.g. always +10° off), high correlation → the
  arbitrary target-line reference (PLAN.md D3). The physics works; fix is
  address calibration.
- **High scatter** (sd > ~5°, low correlation) → body-frame integration
  error (D2). Prioritize the gyro-based orientation rewrite.
- **Missed swings / false triggers** → phase-threshold tuning.

Each session closes the loop: range → `compare.py` → fix the dominant
error source → rebuild → next session.
