#!/bin/sh

# ==========================================
# Manul Programming Language Installer
# ==========================================

set -e

MANUL_VERSION="0.0.1"
REPO_PATH="wizardleeen/manul"
INSTALL_DIR="$HOME/.manul"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

printf "${BLUE}Starting Manul Installer (v${MANUL_VERSION})...${NC}\n"

# -----------------------------------------------------------------------------
# Helper: Version Comparison
# -----------------------------------------------------------------------------
version_ge() {
    # Returns 0 if $1 >= $2, 1 otherwise
    printf '%s\n%s' "$2" "$1" | sort -C -V
}

check_macos_version() {
    local MIN_MAJOR=11 # Big Sur
    local CURRENT_MAJOR
    
    # sw_vers -productVersion usually returns "12.3.1" etc.
    CURRENT_MAJOR=$(sw_vers -productVersion | cut -d'.' -f1)

    if [ "$CURRENT_MAJOR" -lt "$MIN_MAJOR" ]; then
        printf "${RED}Error: macOS 11 (Big Sur) or newer is required.${NC}\n"
        printf "Detected macOS major version: ${CURRENT_MAJOR}\n"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# 1. Detect OS & Arch with Compatibility Checks
# -----------------------------------------------------------------------------
OS="$(uname -s)"
ARCH="$(uname -m)"
ASSET_NAME=""

if [ "$OS" = "Linux" ]; then
    if [ "$ARCH" = "x86_64" ]; then
        ASSET_NAME="manul-linux-amd64.tar.gz"
    elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        ASSET_NAME="manul-linux-aarch64.tar.gz"
    else
        printf "${RED}Error: Linux architecture $ARCH is not supported yet.${NC}\n"
        exit 1
    fi
elif [ "$OS" = "Darwin" ]; then
    check_macos_version
    
    if [ "$ARCH" = "arm64" ]; then
        ASSET_NAME="manul-macos-aarch64.tar.gz"
    elif [ "$ARCH" = "x86_64" ]; then
        ASSET_NAME="manul-macos-amd64.tar.gz"
    else
        printf "${RED}Error: macOS architecture $ARCH is not supported.${NC}\n"
        exit 1
    fi
else
    printf "${RED}Error: OS $OS is not supported.${NC}\n"
    exit 1
fi

# -----------------------------------------------------------------------------
# 1.5. Detect Region
# -----------------------------------------------------------------------------
# Default to GitHub
BASE_DOMAIN="github.com"

# Check dependencies
if ! command -v curl > /dev/null; then printf "${RED}Error: curl required.${NC}\n"; exit 1; fi

printf "Detecting region to select best mirror...\n"

is_china() {
    # 1. Allow manual override via environment variable (e.g., REGION=CN ./install.sh)
    if [ "$REGION" = "CN" ]; then
        return 0
    fi

    # 2. Network Connectivity Check (The "Google vs Baidu" test)
    # Try to connect to Google (Short timeout). If fails, check Baidu.
    # -I: Fetch headers only (fast)
    # --connect-timeout 2: Wait max 2 seconds
    if ! curl -s --connect-timeout 2 -I https://www.google.com >/dev/null; then
        # Google failed, check Baidu to confirm internet works and we are in CN
        if curl -s --connect-timeout 2 -I https://www.baidu.com >/dev/null; then
            return 0
        fi
    fi

    return 1
}

if is_china; then
    printf "${YELLOW}China region detected. Switching to Gitee mirror.${NC}\n"
    BASE_DOMAIN="gitee.com"
else
    printf "Using default mirror (${BASE_DOMAIN}).\n"
fi

DOWNLOAD_URL="https://${BASE_DOMAIN}/${REPO_PATH}/releases/download/${MANUL_VERSION}/${ASSET_NAME}"

# -----------------------------------------------------------------------------
# 2. Check Other Dependencies
# -----------------------------------------------------------------------------
if ! command -v tar > /dev/null; then printf "${RED}Error: tar required.${NC}\n"; exit 1; fi

# -----------------------------------------------------------------------------
# 3. Download & Extract
# -----------------------------------------------------------------------------
TEMP_DIR=$(mktemp -d)
ARCHIVE_FILE="${TEMP_DIR}/${ASSET_NAME}"
EXTRACT_DIR="${TEMP_DIR}/extract"

printf "Downloading from ${BLUE}${BASE_DOMAIN}${NC}: ${ASSET_NAME}...\n"
curl -L --fail --progress-bar "$DOWNLOAD_URL" -o "$ARCHIVE_FILE"

printf "Extracting files...\n"
mkdir -p "$EXTRACT_DIR"

tar -xzf "$ARCHIVE_FILE" -C "$EXTRACT_DIR"

SOURCE_DIR="$EXTRACT_DIR"
# Handle nested folder if tar contains a root folder
if [ $(ls -1 "$EXTRACT_DIR" | wc -l) -eq 1 ]; then
    NESTED_DIR=$(ls -1 "$EXTRACT_DIR")
    if [ -d "$EXTRACT_DIR/$NESTED_DIR" ]; then
        SOURCE_DIR="$EXTRACT_DIR/$NESTED_DIR"
    fi
fi

# -----------------------------------------------------------------------------
# 4. Install Files
# -----------------------------------------------------------------------------
printf "Installing to ${INSTALL_DIR}...\n"

# Remove previous install if exists
if [ -d "$INSTALL_DIR" ]; then rm -rf "$INSTALL_DIR"; fi

mkdir -p "$INSTALL_DIR"
cp -R "$SOURCE_DIR/"* "$INSTALL_DIR/"
rm -rf "$TEMP_DIR"

# -----------------------------------------------------------------------------
# 6. Configure Service
# -----------------------------------------------------------------------------
printf "Configuring ${BLUE}manul-server${NC} as a service...\n"

if [ "$OS" = "Darwin" ]; then
    # --- macOS: LaunchAgents (User specific) ---
    LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
    PLIST_PATH="${LAUNCH_AGENT_DIR}/com.manul.server.plist"
    LOG_DIR="$HOME/Library/Logs/Manul"
    mkdir -p "$LAUNCH_AGENT_DIR"
    mkdir -p "$LOG_DIR"

    cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.manul.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/bin/manul-server</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${INSTALL_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/manul-server.log</string>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/manul-server.log</string>
</dict>
</plist>
EOF
    # Reload service
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    launchctl load "$PLIST_PATH"

elif [ "$OS" = "Linux" ]; then
    # --- Linux: Detect Init System ---
    if [ -f /sbin/openrc-run ]; then
        # --- OpenRC (Alpine Linux) ---
        if [ "$(id -u)" -eq 0 ]; then
            SERVICE_PATH="/etc/init.d/manul-server"
            printf "Creating OpenRC service at ${SERVICE_PATH}...\n"

            cat > "$SERVICE_PATH" <<EOF
#!/sbin/openrc-run

name="manul-server"
description="Manul Language Server"
command="${INSTALL_DIR}/bin/manul-server"
directory="${INSTALL_DIR}"
command_background=true
pidfile="/run/manul-server.pid"
output_log="/var/log/manul-server.log"
error_log="/var/log/manul-server.log"

depend() {
    need net
}
EOF
            chmod +x "$SERVICE_PATH"
            rc-update add manul-server default
            # UPDATED: Added || true to prevent script exit on 'service already starting'
            rc-service manul-server restart || true
        else
            printf "${YELLOW}Warning: OpenRC detected (Alpine), but root is required to configure services. Skipping service setup.${NC}\n"
        fi
    
    elif command -v systemctl > /dev/null; then
        # --- Linux: systemd --user ---
        # Detect if running as root (ID 0) to determine System vs User service
        if [ "$(id -u)" -eq 0 ]; then
            SYSTEMD_DIR="/etc/systemd/system"
            SCTL_CMD="systemctl"
        else
            SYSTEMD_DIR="$HOME/.config/systemd/user"
            SCTL_CMD="systemctl --user"
        fi

        SERVICE_PATH="${SYSTEMD_DIR}/manul-server.service"
        mkdir -p "$SYSTEMD_DIR"

        cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Manul Language Server
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/bin/manul-server
WorkingDirectory=${INSTALL_DIR}
Restart=always

[Install]
WantedBy=default.target
EOF
        # Reload systemd daemon using the correct command
        $SCTL_CMD daemon-reload
        $SCTL_CMD enable manul-server
        $SCTL_CMD restart manul-server
    else
        printf "${YELLOW}Warning: systemd or OpenRC not found. Service not started automatically.${NC}\n"
    fi
fi


# -----------------------------------------------------------------------------
# 7. Shell Configuration (Environment Script)
# -----------------------------------------------------------------------------
printf "Configuring shell environment...\n"

mkdir -p "${INSTALL_DIR}/bin"

# UPDATED: Create the Standard env file
ENV_SCRIPT="${INSTALL_DIR}/bin/env"
cat > "$ENV_SCRIPT" <<EOF
#!/bin/sh
export PATH="${INSTALL_DIR}/bin:\$PATH"
EOF

# UPDATED: Create the Fish env file
ENV_SCRIPT_FISH="${INSTALL_DIR}/bin/env.fish"
cat > "$ENV_SCRIPT_FISH" <<EOF
# Manul Env for Fish
if status is-interactive
    if not contains "${INSTALL_DIR}/bin" \$PATH
        set -gx PATH "${INSTALL_DIR}/bin" \$PATH
    end
end
EOF

DETECTED_SHELL="$(basename "$SHELL")"
SHELL_CONFIG=""
SOURCE_CMD=""

# Determine config file and source command based on detected shell
case "$DETECTED_SHELL" in
    zsh)
        SHELL_CONFIG="$HOME/.zshrc"
        SOURCE_CMD="source \"${INSTALL_DIR}/bin/env\""
        ;;
    bash)
        if [ "$OS" = "Darwin" ]; then
            SHELL_CONFIG="$HOME/.bash_profile"
        else
            SHELL_CONFIG="$HOME/.bashrc"
        fi
        SOURCE_CMD="source \"${INSTALL_DIR}/bin/env\""
        ;;
    fish)
        SHELL_CONFIG="$HOME/.config/fish/config.fish"
        SOURCE_CMD="source \"${INSTALL_DIR}/bin/env.fish\""
        ;;
    *)
        # Fallback
        SHELL_CONFIG="$HOME/.profile"
        SOURCE_CMD="source \"${INSTALL_DIR}/bin/env\""
        ;;
esac

# Function to update config safely
add_to_path() {
    local cfg="$1"
    local cmd="$2"

    # Create file if it doesn't exist
    if [ ! -f "$cfg" ]; then 
        mkdir -p "$(dirname "$cfg")"
        touch "$cfg"
    fi

    # Check if PATH is already configured
    if grep -q "$INSTALL_DIR" "$cfg"; then
        printf "${GREEN}Checked: ${cfg} already contains Manul path.${NC}\n"
    else
        printf "Adding Manul path to ${BLUE}${cfg}${NC}...\n"
        echo "" >> "$cfg"
        echo "# Manul Programming Language" >> "$cfg"
        # UPDATED: Use the dynamic cmd variable instead of hardcoded string
        echo "$cmd" >> "$cfg"
    fi
}

# Apply configuration
add_to_path "$SHELL_CONFIG" "$SOURCE_CMD"

# -----------------------------------------------------------------------------
# 8. Completion & Instructions
# -----------------------------------------------------------------------------
printf "\n${GREEN}Manul installed successfully!${NC}\n"
printf "Service is running as current user: $(whoami)\n"

# Verify current session PATH
case ":$PATH:" in
    *":${INSTALL_DIR}/bin:"*)
        # Already in path (rare for fresh install unless previously set)
        printf "You can run ${BLUE}manul${NC} immediately.\n"
        ;;
    *)
        printf "${YELLOW}Action Required:${NC} To use 'manul' in this terminal, run:\n"
        printf "\n    ${CYAN}${SOURCE_CMD}${NC}\n\n"
        ;;
esac