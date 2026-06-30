import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class HandPathApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new HandPathView();
        var delegate = new HandPathDelegate(view);
        return [view, delegate];
    }
}
