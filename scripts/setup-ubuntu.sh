#!/bin/sh
# Set up the Garmin Connect IQ build/tooling environment on Ubuntu 24.04.
# Idempotent — safe to re-run. Uses sudo for apt and one webkit symlink.
#
# After running: launch the SDK Manager (~/.local/share/garmin-connectiq-tools/
# bin/sdkmanager-run), log in with a Garmin account, download the latest SDK
# (set it as the active SDK) and the device profiles you build for (at least
# "MARQ (Gen 2)"). Then ./build.sh works.
set -eu

TOOLS="$HOME/.local/share/garmin-connectiq-tools"
COMPAT="$TOOLS/libcompat"
LIBDIR="$COMPAT/extracted/usr/lib/x86_64-linux-gnu"

echo "==> apt packages (java for the compiler, tools for this script)"
sudo apt-get install -y --no-install-recommends \
    default-jre curl unzip openssl

echo "==> Connect IQ SDK Manager"
mkdir -p "$TOOLS/bin"
if [ ! -x "$TOOLS/bin/sdkmanager" ]; then
    curl -fL -o "$TOOLS/sdkmanager.zip" \
        "https://developer.garmin.com/downloads/connect-iq/sdk-manager/connectiq-sdk-manager-linux.zip"
    unzip -oq "$TOOLS/sdkmanager.zip" -d "$TOOLS"
    rm "$TOOLS/sdkmanager.zip"
fi

# Ubuntu 24.04 dropped webkit2gtk-4.0 (libsoup2), which Garmin's sdkmanager
# and simulator link against. Extract jammy's genuine 4.0 libs locally —
# symlinking to webkit 4.1 does NOT work (libsoup2/libsoup3 clash).
echo "==> webkit2gtk-4.0 compat libs from jammy"
mkdir -p "$COMPAT/extracted"
fetch_deb() {
    # $1 = pool dir URL, $2 = filename regex (latest matching build is used)
    deb=$(curl -fs "$1/" | grep -oE "$2" | sort -uV | tail -1)
    [ -n "$deb" ] || { echo "no deb matching $2 at $1" >&2; exit 1; }
    echo "    $deb"
    [ -f "$COMPAT/$deb" ] || curl -fsL -o "$COMPAT/$deb" "$1/$deb"
    dpkg-deb -x "$COMPAT/$deb" "$COMPAT/extracted"
}
WEBKIT_POOL="http://security.ubuntu.com/ubuntu/pool/main/w/webkit2gtk"
fetch_deb "$WEBKIT_POOL" 'libwebkit2gtk-4\.0-37_[^"]*22\.04[^"]*_amd64\.deb'
fetch_deb "$WEBKIT_POOL" 'libjavascriptcoregtk-4\.0-18_[^"]*22\.04[^"]*_amd64\.deb'
fetch_deb "http://archive.ubuntu.com/ubuntu/pool/main/i/icu" 'libicu70_[^"]*ubuntu[^"]*_amd64\.deb'
fetch_deb "http://archive.ubuntu.com/ubuntu/pool/main/w/woff2" 'libwoff1_1\.0\.2-1build[^"]*_amd64\.deb'

echo "==> sdkmanager-run wrapper"
cat > "$TOOLS/bin/sdkmanager-run" <<EOF
#!/bin/sh
# Ubuntu 24.04 dropped webkit2gtk-4.0 (libsoup2), which Garmin's sdkmanager
# needs. Jammy's webkit 4.0 libs are extracted under libcompat/.
# WebKit's helper processes are found via a symlink at
# /usr/lib/x86_64-linux-gnu/webkit2gtk-4.0 (created by setup-ubuntu.sh).
COMPAT="$LIBDIR"
export LD_LIBRARY_PATH="\$COMPAT:\${LD_LIBRARY_PATH:-}"
exec "$TOOLS/bin/sdkmanager" "\$@"
EOF
chmod +x "$TOOLS/bin/sdkmanager-run"

# WebKit hardcodes the helper-process path (WebKitNetworkProcess etc.) and
# ignores WEBKIT_EXEC_PATH in release builds; a symlink is the only clean fix.
# The path is unowned by any noble package, and trivially reversible.
if [ ! -e /usr/lib/x86_64-linux-gnu/webkit2gtk-4.0 ]; then
    echo "==> webkit helper-process symlink (sudo)"
    sudo ln -s "$LIBDIR/webkit2gtk-4.0" /usr/lib/x86_64-linux-gnu/webkit2gtk-4.0
fi

echo "==> developer key"
KEYDIR="$HOME/.Garmin/ConnectIQ"
if [ ! -f "$KEYDIR/developer_key.der" ]; then
    echo "    NOTE: generating a NEW key. To keep the same app-signing"
    echo "    identity across machines, instead copy an existing"
    echo "    ~/.Garmin/ConnectIQ/developer_key.der here and re-run."
    mkdir -p "$KEYDIR"
    openssl genrsa -out "$KEYDIR/developer_key.pem" 4096
    openssl pkcs8 -topk8 -inform PEM -outform DER -nocrypt \
        -in "$KEYDIR/developer_key.pem" -out "$KEYDIR/developer_key.der"
fi

cat <<EOF

Done. Remaining manual steps (need a Garmin login, GUI only):
  1. $TOOLS/bin/sdkmanager-run
  2. Log in; download the latest SDK and set it as the active SDK.
  3. In Devices, download "MARQ (Gen 2)" (and any other build targets).
Then, from the repo: ./build.sh
EOF
