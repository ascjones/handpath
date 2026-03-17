using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Sensor;
using Toybox.Timer;
using Toybox.Math;

class HandPathView extends WatchUi.View {

    private var _detector as SwingDetector;
    private var _listening as Boolean = false;
    private var _statusText as String = "Press START\nto begin";

    // History of recent IDDX readings
    private var _iddxHistory as Array<Float> = [];
    private var _maxHistory as Number = 10;

    // Live accel display
    private var _liveMag as Number = 0;

    function initialize() {
        View.initialize();
        _detector = new SwingDetector();
    }

    function onLayout(dc as Dc) as Void {
    }

    function onShow() as Void {
    }

    function onHide() as Void {
        stopListening();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        if (!_listening) {
            _drawIdleScreen(dc, cx, w, h);
            return;
        }

        _drawActiveScreen(dc, cx, w, h);
    }

    private function _drawIdleScreen(dc as Dc, cx as Number, w as Number, h as Number) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h / 2 - 40, Graphics.FONT_SMALL, "IDDX", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h / 2 - 10, Graphics.FONT_XTINY, "Initial Downswing", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h / 2 + 8, Graphics.FONT_XTINY, "Direction", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h / 2 + 40, Graphics.FONT_XTINY, _statusText, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function _drawActiveScreen(dc as Dc, cx as Number, w as Number, h as Number) as Void {
        var y = 22;

        // Phase indicator with colored dot
        var phaseColor = _phaseColor();
        dc.setColor(phaseColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - 40, y + 7, 4);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_XTINY, _phaseLabel(), Graphics.TEXT_JUSTIFY_CENTER);
        y += 22;

        // Swing count
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_XTINY,
            "Swing " + _detector.swingCount,
            Graphics.TEXT_JUSTIFY_CENTER);
        y += 25;

        if (_detector.swingCount > 0) {
            _drawIddxResult(dc, cx, w, h, y);
        } else {
            _drawWaiting(dc, cx, y);
        }

        // G-force meter at bottom
        _drawGMeter(dc, cx, w, h);
    }

    private function _drawIddxResult(dc as Dc, cx as Number, w as Number, h as Number, y as Number) as Void {
        var iddx = _detector.iddxDeg;
        var color = _iddxColor(iddx);

        // Sign prefix
        var sign = "";
        if (iddx > 0.0f) { sign = "+"; }

        // Big IDDX number
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_NUMBER_HOT,
            sign + iddx.format("%.0f") + "°",
            Graphics.TEXT_JUSTIFY_CENTER);
        y += 55;

        // Label
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_XTINY, "IDDX", Graphics.TEXT_JUSTIFY_CENTER);
        y += 18;

        // Feedback text
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_XTINY, _iddxFeedback(iddx), Graphics.TEXT_JUSTIFY_CENTER);
        y += 22;

        // Session average
        if (_iddxHistory.size() > 1) {
            var avg = _sessionAverage();
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            var avgSign = "";
            if (avg > 0.0f) { avgSign = "+"; }
            dc.drawText(cx, y, Graphics.FONT_XTINY,
                "Avg: " + avgSign + avg.format("%.1f") + "°",
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Mini history bar across the bottom third
        _drawHistoryDots(dc, cx, w, h);
    }

    private function _drawWaiting(dc as Dc, cx as Number, y as Number) as Void {
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y + 15, Graphics.FONT_SMALL, "READY", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y + 45, Graphics.FONT_XTINY, "Take a swing", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y + 65, Graphics.FONT_XTINY, "Target: +5° to +15°", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Draw small dots for recent IDDX values, color-coded
    private function _drawHistoryDots(dc as Dc, cx as Number, w as Number, h as Number) as Void {
        var count = _iddxHistory.size();
        if (count < 2) { return; }

        var dotY = h - 35;
        var maxDots = 8;
        var start = 0;
        if (count > maxDots) { start = count - maxDots; }
        var numDots = count - start;
        var spacing = 18;
        var startX = cx - ((numDots - 1) * spacing / 2);

        for (var i = start; i < count; i++) {
            var val = _iddxHistory[i] as Float;
            var dotColor = _iddxColor(val);
            dc.setColor(dotColor, Graphics.COLOR_TRANSPARENT);

            var dx = startX + (i - start) * spacing;
            // Current swing = larger dot
            if (i == count - 1) {
                dc.fillCircle(dx, dotY, 5);
            } else {
                dc.fillCircle(dx, dotY, 3);
            }
        }
    }

    private function _drawGMeter(dc as Dc, cx as Number, w as Number, h as Number) as Void {
        var barY = h - 14;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, barY, Graphics.FONT_XTINY,
            (_liveMag / 1000.0).format("%.1f") + "G",
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    function startListening() as Void {
        if (_listening) { return; }

        var options = {
            :period => 1,
            :accelerometer => {
                :enabled => true,
                :sampleRate => 25
            }
        };

        try {
            Sensor.registerSensorDataListener(method(:onSensorData), options);
            _listening = true;
            _statusText = "Listening...";
        } catch (e) {
            _statusText = "Sensor error";
        }

        WatchUi.requestUpdate();
    }

    function stopListening() as Void {
        if (!_listening) { return; }

        try {
            Sensor.unregisterSensorDataListener();
        } catch (e) {
        }
        _listening = false;
        _statusText = "Press START\nto begin";
        WatchUi.requestUpdate();
    }

    function isListening() as Boolean {
        return _listening;
    }

    function resetSession() as Void {
        _detector.reset();
        _iddxHistory = [];
        WatchUi.requestUpdate();
    }

    // Sensor data callback - receives batches of 25 samples (1 second)
    function onSensorData(sensorData as Sensor.SensorData) as Void {
        var accelData = sensorData.accelerometerData;
        if (accelData == null) { return; }

        var x = accelData.x;
        var y = accelData.y;
        var z = accelData.z;
        if (x == null || y == null || z == null) { return; }
        if (x.size() == 0) { return; }

        // Update live G display
        var last = x.size() - 1;
        var lx = (x[last] as Number).toFloat();
        var ly = (y[last] as Number).toFloat();
        var lz = (z[last] as Number).toFloat();
        _liveMag = Math.sqrt(lx * lx + ly * ly + lz * lz).toNumber();

        // Feed to detector
        var completed = _detector.processBatch(
            x as Array<Number>,
            y as Array<Number>,
            z as Array<Number>
        );

        if (completed) {
            _iddxHistory.add(_detector.iddxDeg);
            if (_iddxHistory.size() > _maxHistory) {
                _iddxHistory = _iddxHistory.slice(1, null) as Array<Float>;
            }

            // Vibrate to notify
            if (Toybox.Attention has :vibrate) {
                var vibeData = [new Toybox.Attention.VibeProfile(50, 200)];
                Toybox.Attention.vibrate(vibeData);
            }
        }

        WatchUi.requestUpdate();
    }

    private function _sessionAverage() as Float {
        var sum = 0.0f;
        for (var i = 0; i < _iddxHistory.size(); i++) {
            sum += _iddxHistory[i];
        }
        return sum / _iddxHistory.size();
    }

    private function _phaseLabel() as String {
        switch (_detector.phase) {
            case PHASE_IDLE: return "WAITING";
            case PHASE_BACKSWING: return "BACKSWING";
            case PHASE_TOP: return "TRANSITION";
            case PHASE_DOWNSWING: return "DOWNSWING";
            case PHASE_COMPLETE: return "MEASURED";
        }
        return "";
    }

    private function _phaseColor() as Number {
        switch (_detector.phase) {
            case PHASE_IDLE: return Graphics.COLOR_DK_GRAY;
            case PHASE_BACKSWING: return Graphics.COLOR_YELLOW;
            case PHASE_TOP: return Graphics.COLOR_ORANGE;
            case PHASE_DOWNSWING: return Graphics.COLOR_BLUE;
            case PHASE_COMPLETE: return Graphics.COLOR_GREEN;
        }
        return Graphics.COLOR_DK_GRAY;
    }

    // Color code the IDDX value per Dewiz target ranges
    private function _iddxColor(iddx as Float) as Number {
        // Target: +5° to +15°
        if (iddx >= 5.0f && iddx <= 15.0f) {
            return Graphics.COLOR_GREEN;
        }
        // Acceptable: 0° to +5° or +15° to +20°
        if (iddx >= 0.0f && iddx <= 20.0f) {
            return Graphics.COLOR_YELLOW;
        }
        // Out of range
        return Graphics.COLOR_RED;
    }

    private function _iddxFeedback(iddx as Float) as String {
        if (iddx >= 5.0f && iddx <= 15.0f) {
            return "In the slot";
        } else if (iddx > 20.0f) {
            return "Over the top";
        } else if (iddx > 15.0f) {
            return "Slightly out";
        } else if (iddx >= 0.0f) {
            return "Slightly inside";
        } else if (iddx >= -10.0f) {
            return "Too inside / stuck";
        } else {
            return "Way too inside";
        }
    }
}
