#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

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
    echo "[prime] paru not found. Installing..."
    sudo pacman -S --noconfirm paru
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
PRIME_PACMAN_DEPS="brightnessctl playerctl pamixer grim lm_sensors hyprlock wtype mpv-mpris"
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
mkdir -p ~/.config/systemd/user
cp prime-daemon.service ~/.config/systemd/user/
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

SHELL_RC="$HOME/.zshrc"
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

PRIME_APP_DIR="$HOME/Projects/prime/prime_app"
FLUTTER_PACKAGES="http shared_preferences google_fonts file_picker path_provider local_auth flutter_secure_storage"

if [ -d "$PRIME_APP_DIR" ]; then
    echo ""
    echo "[prime-app] Ensuring Flutter package dependencies are present..."
    (cd "$PRIME_APP_DIR" && flutter pub add $FLUTTER_PACKAGES && flutter pub get)
    echo "[prime-app] Flutter packages OK: $FLUTTER_PACKAGES"
else
    echo ""
    echo "[prime-app] $PRIME_APP_DIR not found yet — skipping package install."
    echo "[prime-app] After running 'flutter create' there, re-run this script to install: $FLUTTER_PACKAGES"
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
