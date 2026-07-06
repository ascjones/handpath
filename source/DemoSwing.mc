import Toybox.Lang;
import Toybox.Math;

// Scripted accelerometer batches that walk SwingDetector through a full
// swing — the simulator can't generate real motion, so this is how UI
// changes get exercised locally (press DOWN in the sim). Debug builds only.
//
// Emits four 1-second batches (25 samples each), shaped to the detector's
// thresholds:
//   1. quiet at address        -> arms the detector (READY + buzz)
//   2. takeaway ramp + burst   -> BACKSWING
//   3. quiet top + hard burst  -> TOP (fresh gravity) then DOWNSWING
//   4. last burst sample, then quiet -> COMPLETE, cooldown, re-arm
//
// The downswing burst direction is chosen so the computed IDDX lands near
// the requested angle (within a few degrees — the burst samples that leak
// into the top-gravity average shift it slightly).
(:debug)
class DemoSwing {

    // Address-orientation gravity (matches the detector's initial estimate)
    private const _G_REST_Z = 1000;
    // Top-of-backswing gravity: rotated a little, but within the detector's
    // top threshold when compared against the address estimate
    private const _G_TOP_X = 200;
    private const _G_TOP_Z = 950;

    private var _step as Number = 0;
    private var _angleDeg as Float;

    // Demo swings cycle through a spread of results: slot / over the top /
    // slightly inside / slot / stuck
    function initialize(count as Number) {
        var angles = [8.0f, 22.0f, -3.0f, 12.0f, -14.0f] as Array<Float>;
        _angleDeg = angles[count % angles.size()];
    }

    // Next 1-second batch as [x, y, z] sample arrays, null when finished.
    function nextBatch() as Array< Array<Number> >? {
        _step++;
        switch (_step) {
            case 1: return _quietBatch();
            case 2: return _takeawayBatch();
            case 3: return _topAndDownswingBatch();
            case 4: return _finishBatch();
        }
        return null;
    }

    private function _quietSample(i as Number) as Array<Number> {
        var j = (i * 7) % 11 - 5; // small deterministic jitter
        return [j, -j, _G_REST_Z + j];
    }

    // Dynamic magnitude ~800 mG relative to the address gravity estimate
    private function _backswingSample() as Array<Number> {
        return [566, 566, _G_REST_Z];
    }

    // Near-stationary at the top, watch slightly rotated
    private function _topSample() as Array<Number> {
        return [_G_TOP_X, 0, _G_TOP_Z];
    }

    // Hard acceleration out of the top: forward plus an outward component
    // sized to produce the requested IDDX angle
    private function _downswingSample() as Array<Number> {
        // Horizontal frame derived from the top gravity [200, 0, 950]:
        // fwd = [0, 1, 0], out = [-0.978, 0, 0.206]
        var t = 1500.0f * Math.tan(Math.toRadians(_angleDeg)).toFloat();
        return [
            (_G_TOP_X - 0.978f * t).toNumber(),
            1500,
            (_G_TOP_Z + 0.206f * t).toNumber()
        ];
    }

    private function _quietBatch() as Array< Array<Number> > {
        var x = [] as Array<Number>;
        var y = [] as Array<Number>;
        var z = [] as Array<Number>;
        for (var i = 0; i < 25; i++) {
            _push(x, y, z, _quietSample(i));
        }
        return [x, y, z];
    }

    private function _takeawayBatch() as Array< Array<Number> > {
        var x = [] as Array<Number>;
        var y = [] as Array<Number>;
        var z = [] as Array<Number>;
        // Still at address
        for (var i = 0; i < 6; i++) {
            _push(x, y, z, _quietSample(i));
        }
        // Takeaway ramps through the 250-600 band (the armed latch holds)
        _push(x, y, z, [212, 212, _G_REST_Z]);
        _push(x, y, z, [318, 318, _G_REST_Z]);
        _push(x, y, z, [389, 389, _G_REST_Z]);
        // Full backswing motion
        for (var i = 9; i < 25; i++) {
            _push(x, y, z, _backswingSample());
        }
        return [x, y, z];
    }

    private function _topAndDownswingBatch() as Array< Array<Number> > {
        var x = [] as Array<Number>;
        var y = [] as Array<Number>;
        var z = [] as Array<Number>;
        // Backswing finishes
        for (var i = 0; i < 4; i++) {
            _push(x, y, z, _backswingSample());
        }
        // Quiet at the top: detector enters TOP and samples fresh gravity
        for (var i = 4; i < 19; i++) {
            _push(x, y, z, _topSample());
        }
        // Downswing burst: transition fires, integration begins
        for (var i = 19; i < 25; i++) {
            _push(x, y, z, _downswingSample());
        }
        return [x, y, z];
    }

    private function _finishBatch() as Array< Array<Number> > {
        var x = [] as Array<Number>;
        var y = [] as Array<Number>;
        var z = [] as Array<Number>;
        // Final integration sample completes the measurement
        _push(x, y, z, _downswingSample());
        // Follow-through settles; cooldown, then re-arm
        for (var i = 1; i < 25; i++) {
            _push(x, y, z, _quietSample(i));
        }
        return [x, y, z];
    }

    private function _push(x as Array<Number>, y as Array<Number>, z as Array<Number>, s as Array<Number>) as Void {
        x.add(s[0]);
        y.add(s[1]);
        z.add(s[2]);
    }
}
