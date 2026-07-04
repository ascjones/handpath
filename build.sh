#!/bin/sh
# Build / simulate HandPath.
#
#   ./build.sh [device]        build bin/HandPath-<device>.prg (default: marq2)
#   ./build.sh sim [device]    build, start the simulator if needed, deploy
#
# Requires the Connect IQ SDK, a developer key, and the device profile for
# the target (installed via the SDK Manager).
set -eu

# SDK: $CIQ_SDK, else the SDK Manager's active SDK, else a legacy local path.
CFG="$HOME/.Garmin/ConnectIQ/current-sdk.cfg"
if [ -n "${CIQ_SDK:-}" ]; then SDK="$CIQ_SDK"
elif [ -r "$CFG" ]; then SDK="$(cat "$CFG")"
else SDK="$HOME/.local/share/garmin-connectiq-sdk/9.2.0"
fi
KEY="${CIQ_KEY:-$HOME/.Garmin/ConnectIQ/developer_key.der}"
# Ubuntu 24.04 dropped webkit2gtk-4.0, which the simulator links; jammy's
# libs are extracted here (see garmin-connectiq-tools/bin/sdkmanager-run).
COMPAT="$HOME/.local/share/garmin-connectiq-tools/libcompat/extracted/usr/lib/x86_64-linux-gnu"

cmd=build
if [ "${1:-}" = "sim" ]; then
    cmd=sim
    shift
fi
device="${1:-marq2}"
prg="bin/HandPath-$device.prg"

"$SDK/bin/monkeyc" -o "$prg" -f monkey.jungle -d "$device" -y "$KEY" -w -l 3
echo "Built $prg"

if [ "$cmd" = "sim" ]; then
    if ! pgrep -x simulator > /dev/null; then
        LD_LIBRARY_PATH="$COMPAT${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
            "$SDK/bin/connectiq" &
        sleep 5
    fi
    exec "$SDK/bin/monkeydo" "$prg" "$device"
fi
