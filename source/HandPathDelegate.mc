using Toybox.WatchUi;

class HandPathDelegate extends WatchUi.BehaviorDelegate {

    private var _view as HandPathView;

    function initialize(view as HandPathView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // START/STOP button toggles listening
    function onSelect() as Boolean {
        if (_view.isListening()) {
            _view.stopListening();
        } else {
            _view.startListening();
        }
        return true;
    }

    // BACK button - if listening, stop. Otherwise exit app.
    function onBack() as Boolean {
        if (_view.isListening()) {
            _view.stopListening();
            return true;
        }
        return false; // Let system handle (exit app)
    }

    // UP button - reset session
    function onPreviousPage() as Boolean {
        if (_view.isListening()) {
            _view.resetSession();
            return true;
        }
        return false;
    }
}
