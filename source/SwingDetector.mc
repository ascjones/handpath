using Toybox.Math;

// Swing phase states
enum {
    PHASE_IDLE,
    PHASE_BACKSWING,
    PHASE_TOP,
    PHASE_DOWNSWING,
    PHASE_COMPLETE
}

// Implements an IDDX-like metric (Initial Downswing Direction).
// Measures the horizontal direction of hand movement during the
// first ~4 inches of the downswing, from a down-the-line perspective.
//
// Approach:
// 1. Use gravity vector at the top of backswing to define "vertical"
// 2. Double-integrate acceleration over the brief initial downswing
//    window to estimate hand displacement
// 3. Project displacement onto the horizontal plane (perpendicular
//    to gravity) to get the IDDX angle
//
// Watch orientation assumptions (lead wrist, watch face up at address):
//   At the top of backswing, the watch is rotated ~90° from address.
//   We don't assume fixed axes — we use gravity to find "down" and
//   derive the horizontal plane dynamically.

class SwingDetector {

    var phase as Number = PHASE_IDLE;

    // --- Thresholds (milli-G) ---
    // Dynamic acceleration (total minus gravity) to detect swing start
    private var _motionStartThreshold as Number = 600;
    // Deceleration at the top — dynamic accel drops near zero
    private var _topThreshold as Number = 400;
    // Acceleration pickup signals downswing has started
    private var _downswingStartThreshold as Number = 700;
    // Impact spike
    private var _impactThreshold as Number = 5000;
    // Cooldown threshold before next swing
    private var _cooldownThreshold as Number = 500;

    // Minimum backswing duration in samples (at 25Hz) to filter out false triggers
    private var _minBackswingSamples as Number = 10; // 0.4s

    // --- Smoothing ---
    private var _magHistory as Array<Number> = [];
    private var _historySize as Number = 4;

    // --- State tracking ---
    private var _backswingSampleCount as Number = 0;

    // Gravity vector estimated at the top (average of quiet samples)
    private var _gravityVec as Array<Float>?;
    // Samples collected at the top for gravity estimation
    private var _topSamples as Array<Array<Number> > = [];
    private var _topSampleTarget as Number = 4;

    // Downswing integration state
    // Velocity accumulated from acceleration (milli-G * sample_periods)
    private var _velX as Float = 0.0f;
    private var _velY as Float = 0.0f;
    private var _velZ as Float = 0.0f;
    // Displacement accumulated from velocity
    private var _dispX as Float = 0.0f;
    private var _dispY as Float = 0.0f;
    private var _dispZ as Float = 0.0f;
    private var _downswingSampleCount as Number = 0;
    // At 25Hz, ~4 inches of travel in early downswing ≈ 4-6 samples
    // (hands accelerate from ~0 to ~15 mph in first 100-200ms)
    private var _downswingSampleTarget as Number = 5;

    // --- Results ---
    var iddxDeg as Float = 0.0f;
    var swingCount as Number = 0;

    function initialize() {
    }

    // Process a batch of accelerometer samples (x/y/z arrays in milli-G).
    // Returns true if a swing measurement just completed.
    function processBatch(x as Array<Number>, y as Array<Number>, z as Array<Number>) as Boolean {
        var completed = false;

        for (var i = 0; i < x.size(); i++) {
            var sx = x[i];
            var sy = y[i];
            var sz = z[i];

            // Compute dynamic acceleration (subtract gravity estimate if available)
            var dynMag = _dynamicMagnitude(sx, sy, sz);
            var smoothed = _updateSmoothed(dynMag);

            switch (phase) {
                case PHASE_IDLE:
                    // Continuously update resting gravity estimate
                    _updateRestingGravity(sx, sy, sz);
                    if (smoothed > _motionStartThreshold) {
                        phase = PHASE_BACKSWING;
                        _backswingSampleCount = 0;
                        _topSamples = [];
                    }
                    break;

                case PHASE_BACKSWING:
                    _backswingSampleCount++;
                    // Wait for deceleration at top, but only after minimum backswing duration
                    if (_backswingSampleCount > _minBackswingSamples && smoothed < _topThreshold) {
                        phase = PHASE_TOP;
                        _topSamples = [];
                    }
                    break;

                case PHASE_TOP:
                    // Collect samples at the top to get a fresh gravity reading.
                    // At the top the hands are nearly stationary, so the
                    // accelerometer reads mostly gravity in its current orientation.
                    _topSamples.add([sx, sy, sz]);

                    if (_topSamples.size() >= _topSampleTarget) {
                        _gravityVec = _averageVector(_topSamples);
                    }

                    if (smoothed > _downswingStartThreshold && _gravityVec != null) {
                        // Transition to downswing — begin integrating
                        phase = PHASE_DOWNSWING;
                        _velX = 0.0f;
                        _velY = 0.0f;
                        _velZ = 0.0f;
                        _dispX = 0.0f;
                        _dispY = 0.0f;
                        _dispZ = 0.0f;
                        _downswingSampleCount = 0;
                    }
                    break;

                case PHASE_DOWNSWING:
                    completed = _integrateDownswingSample(sx, sy, sz, smoothed);
                    break;

                case PHASE_COMPLETE:
                    if (smoothed < _cooldownThreshold) {
                        phase = PHASE_IDLE;
                        _magHistory = [];
                    }
                    break;
            }
        }

        return completed;
    }

    // Integrate one downswing sample and check if we have enough data.
    // Returns true when IDDX computation is done.
    private function _integrateDownswingSample(sx as Number, sy as Number, sz as Number, smoothed as Number) as Boolean {
        var grav = _gravityVec as Array<Float>;

        // Linear acceleration = measured - gravity
        var ax = sx.toFloat() - grav[0];
        var ay = sy.toFloat() - grav[1];
        var az = sz.toFloat() - grav[2];

        // Trapezoidal integration: velocity += accel, displacement += velocity
        // (units: milli-G * sample_periods; we only need direction, not absolute distance)
        _velX += ax;
        _velY += ay;
        _velZ += az;
        _dispX += _velX;
        _dispY += _velY;
        _dispZ += _velZ;

        _downswingSampleCount++;

        if (_downswingSampleCount >= _downswingSampleTarget || smoothed > _impactThreshold) {
            _computeIddx();
            phase = PHASE_COMPLETE;
            return true;
        }
        return false;
    }

    // Compute IDDX: the angle of the hand displacement projected onto
    // the horizontal plane.
    //
    // Convention (matching Dewiz):
    //   0° = hands move straight toward the target (neutral)
    //   Positive = hands move outward (toward the ball / target line)
    //   Negative = hands move too far inside (stuck)
    //
    // Target range: +5° to +15°
    private function _computeIddx() as Void {
        var grav = _gravityVec;
        if (grav == null) {
            iddxDeg = 0.0f;
            return;
        }

        var gx = grav[0];
        var gy = grav[1];
        var gz = grav[2];

        // Normalize gravity vector
        var gMag = Math.sqrt(gx * gx + gy * gy + gz * gz).toFloat();
        if (gMag < 100.0f) {
            iddxDeg = 0.0f;
            return;
        }
        var gnx = gx / gMag;
        var gny = gy / gMag;
        var gnz = gz / gMag;

        // Project displacement onto horizontal plane by removing the
        // component along gravity
        var dot = _dispX * gnx + _dispY * gny + _dispZ * gnz;
        var hx = _dispX - dot * gnx;
        var hy = _dispY - dot * gny;
        var hz = _dispZ - dot * gnz;

        var hMag = Math.sqrt(hx * hx + hy * hy + hz * hz).toFloat();
        if (hMag < 0.001f) {
            iddxDeg = 0.0f;
            swingCount++;
            return;
        }

        // We need a reference direction in the horizontal plane to measure
        // the angle from. We use the "forward" direction which is
        // perpendicular to both gravity and the watch's primary axis.
        //
        // On the lead wrist at the top, the watch Y axis (along forearm)
        // is roughly pointing along the target line. We construct a
        // horizontal reference by taking cross(gravity, Y_axis) to get
        // a horizontal "outward" direction, then cross(outward, gravity)
        // to get horizontal "forward" (toward target).
        //
        // Y_axis in watch frame = [0, 1, 0]
        var outX = gnz * 0.0f - gny * 0.0f;  // This simplifies...
        // Better: use the Y component of the watch frame directly
        // cross(grav_normalized, [0,1,0]):
        var crossX = gny * 0.0f - gnz * 1.0f; // = -gnz
        var crossY = gnz * 0.0f - gnx * 0.0f; // = 0
        var crossZ = gnx * 1.0f - gny * 0.0f; // = gnx

        // That gives us a horizontal "outward" vector: [-gnz, 0, gnx]
        // Normalize it
        var cMag = Math.sqrt(crossX * crossX + crossZ * crossZ).toFloat();
        if (cMag < 0.001f) {
            // Gravity is along Y — degenerate case, use X/Z plane directly
            iddxDeg = Math.toDegrees(Math.atan2(hz, hx)).toFloat();
            swingCount++;
            return;
        }
        var refOutX = crossX / cMag;
        var refOutY = crossY / cMag;
        var refOutZ = crossZ / cMag;

        // Forward direction = cross(outward, gravity_normalized)
        var fwdX = refOutY * gnz - refOutZ * gny;
        var fwdY = refOutZ * gnx - refOutX * gnz;
        var fwdZ = refOutX * gny - refOutY * gnx;

        // Decompose horizontal displacement into forward and outward components
        var fwdComponent = hx * fwdX + hy * fwdY + hz * fwdZ;
        var outComponent = hx * refOutX + hy * refOutY + hz * refOutZ;

        // IDDX angle: positive = outward (toward target line), negative = inside
        iddxDeg = Math.toDegrees(Math.atan2(outComponent, fwdComponent)).toFloat();

        swingCount++;
    }

    // Estimate dynamic acceleration magnitude by subtracting gravity
    private function _dynamicMagnitude(x as Number, y as Number, z as Number) as Number {
        if (_gravityVec != null) {
            var grav = _gravityVec as Array<Float>;
            var dx = x.toFloat() - grav[0];
            var dy = y.toFloat() - grav[1];
            var dz = z.toFloat() - grav[2];
            return Math.sqrt(dx * dx + dy * dy + dz * dz).toNumber();
        }
        // Before we have a gravity estimate, use total magnitude minus 1G
        var mag = Math.sqrt(
            (x.toFloat() * x) + (y.toFloat() * y) + (z.toFloat() * z)
        ).toNumber();
        var result = mag - 1000;
        if (result < 0) { result = -result; }
        return result;
    }

    // Track resting gravity while idle (low-pass filter)
    private var _restGravity as Array<Float> = [0.0f, 0.0f, 1000.0f];
    private var _restAlpha as Float = 0.1f;

    private function _updateRestingGravity(x as Number, y as Number, z as Number) as Void {
        _restGravity[0] = _restGravity[0] * (1.0f - _restAlpha) + x.toFloat() * _restAlpha;
        _restGravity[1] = _restGravity[1] * (1.0f - _restAlpha) + y.toFloat() * _restAlpha;
        _restGravity[2] = _restGravity[2] * (1.0f - _restAlpha) + z.toFloat() * _restAlpha;
        _gravityVec = _restGravity;
    }

    private function _updateSmoothed(mag as Number) as Number {
        _magHistory.add(mag);
        if (_magHistory.size() > _historySize) {
            _magHistory = _magHistory.slice(1, null) as Array<Number>;
        }
        var sum = 0;
        for (var i = 0; i < _magHistory.size(); i++) {
            sum += _magHistory[i];
        }
        return sum / _magHistory.size();
    }

    private function _averageVector(samples as Array<Array<Number> >) as Array<Float> {
        var sx = 0.0f;
        var sy = 0.0f;
        var sz = 0.0f;
        var n = samples.size();
        if (n == 0) {
            return [0.0f, 0.0f, 0.0f] as Array<Float>;
        }
        for (var i = 0; i < n; i++) {
            sx += samples[i][0];
            sy += samples[i][1];
            sz += samples[i][2];
        }
        return [sx / n, sy / n, sz / n] as Array<Float>;
    }

    function reset() as Void {
        phase = PHASE_IDLE;
        _magHistory = [];
        _topSamples = [];
        _gravityVec = null;
        _restGravity = [0.0f, 0.0f, 1000.0f];
        _velX = 0.0f;
        _velY = 0.0f;
        _velZ = 0.0f;
        _dispX = 0.0f;
        _dispY = 0.0f;
        _dispZ = 0.0f;
        _downswingSampleCount = 0;
        _backswingSampleCount = 0;
        iddxDeg = 0.0f;
        swingCount = 0;
    }
}
