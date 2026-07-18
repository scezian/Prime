#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# sudo_auth_guard_marker: authenticate sudo explicitly, up front, before any
# scripted logic runs. Downstream steps use `if ! sudo <cmd>` guards where a
# failed *command* and a failed *authentication* both look like "false" —
# under a pam_faillock lockout this silently misreads every step as "not
# needed yet" and cascades through the whole script without actually doing
# anything privileged, instead of stopping. Caching a valid ticket here
# up front (and failing loudly if that's not possible) avoids that ambiguity
# for the rest of the run.
echo "[prime] Checking sudo access..."
if ! sudo -v; then
    echo "[prime] ERROR: sudo authentication failed."
    echo "[prime] If you were just locked out (pam_faillock), wait ~10 minutes and re-run this script."
    echo "[prime]   Check lockout status with: faillock --user \$USER"
    exit 1
fi
echo "[prime] sudo OK."

# ============================================================
# Part 1: Prime daemon dependencies
# ============================================================

echo "[prime] Checking for Tailscale..."
if ! command -v tailscale &>/dev/null; then
    echo "[prime] Tailscale not found. Installing..."
    curl -fsSL https://tailscale.com/install.sh | sh
fi

if ! tailscale ip -4 &>/dev/null; then
    echo "[prime] Tailscale installed but not logged in. Starting login..."
    echo "[prime] Open the URL below in a browser and log into your tailnet."
    sudo tailscale up

    if ! tailscale ip -4 &>/dev/null; then
        echo "[prime] Still not connected after login attempt. Re-run this script once you're logged in."
        exit 1
    fi
fi

echo "[prime] Tailscale OK: $(tailscale ip -4)"

echo "[prime] Checking for paru..."
if ! python -c "import shutil,sys; sys.exit(0 if shutil.which('paru') else 1)"; then
    echo "[prime] paru not found. Building from AUR..."
    sudo pacman -S --needed --noconfirm base-devel git
    TMP_PARU=$(mktemp -d)
    git clone https://aur.archlinux.org/paru.git "$TMP_PARU"
    (cd "$TMP_PARU" && makepkg -si --noconfirm)
    rm -rf "$TMP_PARU"
fi
echo "[prime] paru OK: $(which paru)"

echo "[prime] Checking passwordless pacman sudoers rule..."
SUDOERS_FILE="/etc/sudoers.d/prime-pacman"
if ! sudo test -f "$SUDOERS_FILE"; then
    echo "[prime] Setting up passwordless pacman for package installs..."
    TMP_SUDOERS=$(mktemp)
    echo "$USER ALL=(root) NOPASSWD: /usr/bin/pacman" > "$TMP_SUDOERS"

    if sudo visudo -c -f "$TMP_SUDOERS" &>/dev/null; then
        sudo install -m 0440 "$TMP_SUDOERS" "$SUDOERS_FILE"
        echo "[prime] Sudoers rule installed."
    else
        echo "[prime] Generated sudoers rule failed validation, skipping. Add it manually with:"
        echo "[prime]   sudo visudo -f $SUDOERS_FILE"
    fi
    rm -f "$TMP_SUDOERS"
fi

if sudo -n pacman --version &>/dev/null; then
    echo "[prime] Passwordless pacman OK."
else
    echo "[prime] WARNING: passwordless pacman not working. Package install/uninstall via Prime won't work until this is fixed."
fi

echo "[prime] Checking user lingering (so the daemon can start at boot without a login)..."
if [ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" != "yes" ]; then
    echo "[prime] Enabling lingering for $USER..."
    sudo loginctl enable-linger "$USER"
else
    echo "[prime] Lingering already enabled."
fi

echo "[prime] Checking firewalld rule for Tailscale..."
if command -v firewall-cmd &>/dev/null; then
    if ! sudo firewall-cmd --zone=trusted --query-interface=tailscale0 &>/dev/null; then
        echo "[prime] Assigning tailscale0 to the trusted firewalld zone..."
        sudo firewall-cmd --permanent --zone=trusted --add-interface=tailscale0
    fi
    if ! sudo firewall-cmd --zone=trusted --query-port=8420/tcp &>/dev/null; then
        echo "[prime] Opening port 8420/tcp on the trusted zone..."
        sudo firewall-cmd --permanent --zone=trusted --add-port=8420/tcp
    fi
    sudo firewall-cmd --reload &>/dev/null
    echo "[prime] Firewalld OK."
else
    echo "[prime] firewalld not found — skipping firewall setup (open port 8420/tcp manually if you use a different firewall)."
fi

echo "[prime] Checking for daemon runtime CLI tools..."
PRIME_PACMAN_DEPS="brightnessctl playerctl pamixer grim lm_sensors hyprlock wtype mpv-mpris bluez-utils networkmanager git"
MISSING_DEPS=""
for pkg in $PRIME_PACMAN_DEPS; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
        MISSING_DEPS="$MISSING_DEPS $pkg"
    fi
done
if [ -n "$MISSING_DEPS" ]; then
    echo "[prime] Installing missing packages:$MISSING_DEPS"
    sudo pacman -S --needed --noconfirm $MISSING_DEPS
else
    echo "[prime] All daemon CLI tools already installed."
fi

echo "[prime] Ensuring trash directory exists..."
mkdir -p ~/.prime-trash

echo "[prime] Setting up daemon virtualenv..."
if [ ! -d venv ]; then
    python -m venv venv
fi
./venv/bin/pip install --upgrade pip
./venv/bin/pip install -r requirements.txt

chmod +x run.sh

echo "[prime] Installing systemd user service..."
# prime_daemon_service_template_marker: WorkingDirectory/ExecStart must point at
# THIS checkout's actual path, not an assumed ~/Projects/prime location, so a
# clone anywhere else still gets a working unit file.
mkdir -p ~/.config/systemd/user
DAEMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sed -e "s|WorkingDirectory=%h/Projects/prime/prime-daemon|WorkingDirectory=$DAEMON_DIR|" \
    -e "s|ExecStart=%h/Projects/prime/prime-daemon/run.sh|ExecStart=$DAEMON_DIR/run.sh|" \
    prime-daemon.service > ~/.config/systemd/user/prime-daemon.service
systemctl --user daemon-reload
systemctl --user enable prime-daemon.service

echo "[prime] Enabling lingering (daemon starts at boot, independent of login)..."
if ! loginctl show-user "$USER" 2>/dev/null | grep -q "Linger=yes"; then
    sudo loginctl enable-linger "$USER"
fi

echo "[prime] Starting daemon..."
systemctl --user start prime-daemon.service
sleep 2

echo "[prime] Daemon setup complete."

# ============================================================
# Part 2: Prime app build dependencies (Flutter + Android SDK)
# ============================================================

echo ""
echo "[prime-app] Checking for Flutter..."
if ! command -v flutter &>/dev/null; then
    echo "[prime-app] Flutter not found. Installing flutter-bin from AUR..."
    paru -S --noconfirm flutter-bin
fi
echo "[prime-app] Flutter OK: $(which flutter)"

echo "[prime-app] Checking for Java 17+..."
if ! command -v java &>/dev/null || ! java -version 2>&1 | grep -qE '"(1[7-9]|[2-9][0-9])'; then
    echo "[prime-app] Installing jdk17-openjdk..."
    paru -S --noconfirm jdk17-openjdk
fi
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk"
echo "[prime-app] Java OK: $(java -version 2>&1 | head -1)"

# Android SDK installed to ~/Android/sdk (user-owned, avoids /opt root-permission issues
# that the AUR android-sdk packages have)
ANDROID_HOME="$HOME/Android/sdk"
CMDLINE_TOOLS_DIR="$ANDROID_HOME/cmdline-tools/latest"

echo "[prime-app] Checking for Android SDK cmdline-tools..."
if [ ! -d "$CMDLINE_TOOLS_DIR" ]; then
    echo "[prime-app] Downloading Android cmdline-tools..."
    mkdir -p "$ANDROID_HOME/cmdline-tools"
    TMP_ZIP=$(mktemp --suffix=.zip)
    curl -fsSL -o "$TMP_ZIP" "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
    TMP_EXTRACT=$(mktemp -d)
    unzip -q "$TMP_ZIP" -d "$TMP_EXTRACT"
    mv "$TMP_EXTRACT/cmdline-tools" "$CMDLINE_TOOLS_DIR"
    rm -rf "$TMP_ZIP" "$TMP_EXTRACT"
    echo "[prime-app] cmdline-tools installed to $CMDLINE_TOOLS_DIR"
fi

export ANDROID_HOME
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"

# prime_shell_rc_detect_marker
case "$SHELL" in
    */zsh) SHELL_RC="$HOME/.zshrc" ;;
    */bash) SHELL_RC="$HOME/.bashrc" ;;
    *) SHELL_RC="$HOME/.profile" ;;
esac
if ! grep -q "ANDROID_HOME" "$SHELL_RC" 2>/dev/null; then
    echo "[prime-app] Adding Android SDK env vars to $SHELL_RC..."
    cat >> "$SHELL_RC" << 'ENVEOF'

# --- Prime app / Android SDK (added by setup.sh) ---
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk"
export ANDROID_HOME="$HOME/Android/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"
ENVEOF
fi

echo "[prime-app] Accepting Android SDK licenses..."
yes | sdkmanager --licenses &>/dev/null || true

echo "[prime-app] Installing platform-tools, build-tools, and Android platform..."
sdkmanager --install "platform-tools" "platforms;android-36" "build-tools;28.0.3" &>/tmp/prime-app-sdkmanager.log || {
    echo "[prime-app] sdkmanager install had issues, check /tmp/prime-app-sdkmanager.log"
}

flutter config --android-sdk "$ANDROID_HOME" &>/dev/null

echo "[prime-app] Running flutter doctor..."
flutter doctor -v

# ============================================================
# Part 3: Prime app Flutter package dependencies
# ============================================================
# Every `flutter pub add` we've ever needed lives in this one list, so a
# fresh checkout of the app source always has everything it needs without
# hunting through past conversation history for what to add.

# prime_app_dir_autodetect_marker
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRIME_APP_DIR="$(dirname "$SCRIPT_DIR")/prime_app"
FLUTTER_PACKAGES="http shared_preferences google_fonts file_picker path_provider local_auth flutter_secure_storage"

if [ -d "$PRIME_APP_DIR" ]; then
    echo ""
    echo "[prime-app] Ensuring Flutter package dependencies are present..."
    # pub_add_guard_marker: only `pub add` packages missing from pubspec.yaml —
    # re-adding an already-present package with no version constraint can let
    # pub's resolver silently downgrade it (bit us with file_picker 11.0.2 -> 3.0.4).
    MISSING_PACKAGES=""
    for pkg in $FLUTTER_PACKAGES; do
        if ! grep -qE "^\s*${pkg}:" "$PRIME_APP_DIR/pubspec.yaml"; then
            MISSING_PACKAGES="$MISSING_PACKAGES $pkg"
        fi
    done
    if [ -n "$MISSING_PACKAGES" ]; then
        echo "[prime-app] Adding missing packages:$MISSING_PACKAGES"
        (cd "$PRIME_APP_DIR" && flutter pub add $MISSING_PACKAGES)
    else
        echo "[prime-app] All packages already declared in pubspec.yaml."
    fi
    (cd "$PRIME_APP_DIR" && flutter pub get)
    echo "[prime-app] Flutter packages OK: $FLUTTER_PACKAGES"
else
    echo ""
    echo "[prime-app] $PRIME_APP_DIR not found yet — skipping package install."
    echo "[prime-app] After running 'flutter create' there, re-run this script to install: $FLUTTER_PACKAGES"
fi

# ============================================================
# Part 4: Prime screen mirroring (wayvnc)
# ============================================================

echo ""
echo "[prime-vnc] Checking for wayvnc..."
if ! pacman -Qi wayvnc &>/dev/null; then
    echo "[prime-vnc] Installing wayvnc..."
    sudo pacman -S --needed --noconfirm wayvnc
fi
echo "[prime-vnc] wayvnc OK: $(which wayvnc)"

WAYVNC_CONFIG_DIR="$HOME/.config/wayvnc"
mkdir -p "$WAYVNC_CONFIG_DIR"

echo "[prime-vnc] Checking for TLS cert/key..."
if [ ! -f "$WAYVNC_CONFIG_DIR/cert.pem" ] || [ ! -f "$WAYVNC_CONFIG_DIR/key.pem" ]; then
    echo "[prime-vnc] Generating self-signed TLS cert..."
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$WAYVNC_CONFIG_DIR/key.pem" \
        -out "$WAYVNC_CONFIG_DIR/cert.pem" \
        -days 3650 \
        -subj "/CN=prime-vnc" &>/dev/null
    chmod 600 "$WAYVNC_CONFIG_DIR/key.pem"
    echo "[prime-vnc] TLS cert generated (valid 10 years)."
else
    echo "[prime-vnc] TLS cert already exists."
fi

echo "[prime-vnc] Checking wayvnc config..."
if [ ! -f "$WAYVNC_CONFIG_DIR/config" ] || ! grep -q "^enable_auth=true" "$WAYVNC_CONFIG_DIR/config"; then
    if [ -f "$WAYVNC_CONFIG_DIR/config" ]; then
        echo "[prime-vnc] WARNING: existing config has auth disabled or is otherwise non-conformant. Regenerating with auth enabled."
    fi
    echo "[prime-vnc] Writing wayvnc config..."
    TAILSCALE_IP="$(tailscale ip -4)"
    VNC_PASSWORD="$(head -c 18 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 20)"
    cat > "$WAYVNC_CONFIG_DIR/config" << EOF
address=$TAILSCALE_IP
port=5900
enable_auth=true
username=prime
password=$VNC_PASSWORD
private_key_file=$WAYVNC_CONFIG_DIR/key.pem
certificate_file=$WAYVNC_CONFIG_DIR/cert.pem
EOF
    chmod 600 "$WAYVNC_CONFIG_DIR/config"
    echo "[prime-vnc] Config written. VNC username: prime  password: $VNC_PASSWORD"
    echo "[prime-vnc] (Also saved in $WAYVNC_CONFIG_DIR/config if you need it again.)"
else
    echo "[prime-vnc] Config already exists, leaving as-is."
fi

echo "[prime-vnc] Installing systemd user service..."
cp prime-vnc.service "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable prime-vnc.service
systemctl --user restart prime-vnc.service
sleep 1
if systemctl --user is-active --quiet prime-vnc.service; then
    echo "[prime-vnc] wayvnc running on $(tailscale ip -4):5900"
else
    echo "[prime-vnc] WARNING: wayvnc failed to start. Check: journalctl --user -u prime-vnc.service -n 30"
fi

# ============================================================
# Part 5: Prime screen mirroring for mobile (wayvnc, no TLS)
# ============================================================
echo ""
echo "[prime-vnc-mobile] Checking wayvnc mobile config..."
if [ ! -f "$WAYVNC_CONFIG_DIR/config-mobile" ] || grep -q "^enable_auth=true" "$WAYVNC_CONFIG_DIR/config-mobile"; then
    if [ -f "$WAYVNC_CONFIG_DIR/config-mobile" ]; then
        echo "[prime-vnc-mobile] WARNING: existing config-mobile has auth enabled or is otherwise non-conformant. Regenerating (mobile RFB relies on Tailscale-only auth, not wayvnc auth)."
    fi
    echo "[prime-vnc-mobile] Writing wayvnc mobile config..."
    TAILSCALE_IP="$(tailscale ip -4)"
    VNC_MOBILE_PASSWORD="$(head -c 18 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 20)"
    cat > "$WAYVNC_CONFIG_DIR/config-mobile" << EOF
address=$TAILSCALE_IP
port=5902
enable_auth=false
username=prime
password=$VNC_MOBILE_PASSWORD
EOF
    chmod 600 "$WAYVNC_CONFIG_DIR/config-mobile"
    echo "[prime-vnc-mobile] Config written."
else
    echo "[prime-vnc-mobile] Config already exists, leaving as-is."
fi
echo "[prime-vnc-mobile] Installing systemd user service..."
cp prime-vnc-mobile.service "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable prime-vnc-mobile.service
systemctl --user restart prime-vnc-mobile.service
sleep 1
if systemctl --user is-active --quiet prime-vnc-mobile.service; then
    echo "[prime-vnc-mobile] wayvnc mobile running on $(tailscale ip -4):5902"
else
    echo "[prime-vnc-mobile] WARNING: wayvnc mobile failed to start. Check: journalctl --user -u prime-vnc-mobile.service -n 30"
fi
# ============================================================
# Done
# ============================================================

echo ""
echo "[prime] ==================================================="
echo "[prime] Setup complete."
echo "[prime]"
echo "[prime] Daemon:"
echo "[prime]   Start:  systemctl --user start prime-daemon.service"
echo "[prime]   Logs:   journalctl --user -u prime-daemon.service -f"
if [ -f "$HOME/.config/prime/token" ]; then
    echo "[prime]   Token: $(cat "$HOME/.config/prime/token")"
else
    echo "[prime]   Could not find token file yet. Check:"
    echo "[prime]     journalctl --user -u prime-daemon.service -n 20"
fi
echo "[prime]"
echo "[prime] App build environment:"
echo "[prime]   IMPORTANT: run 'source ~/.zshrc' or open a new terminal for env vars to take effect."
echo "[prime]   To connect your phone: enable Developer Options + USB debugging on it,"
echo "[prime]   plug it in via USB, then run: flutter devices"
echo "[prime] ==================================================="
