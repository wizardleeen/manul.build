#!/bin/sh

# ==========================================
# Manul Programming Language Installer
# ==========================================

set -e

if [ -z "$MANUL_VERSION" ]; then
    MANUL_VERSION="0.0.1-alpha"
fi

REPO_PATH="wizardleeen/manul"
SERVICE_USER="manul"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

printf "${BLUE}Starting Manul Installer (v${MANUL_VERSION})...${NC}\n"

# -----------------------------------------------------------------------------
# 0. Root/User Logic & Install Directory
# -----------------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
    IS_ROOT=1
    INSTALL_DIR="/usr/local/manul"
    printf "${YELLOW}Running as ROOT.${NC}\n"
    printf "  - Installation Type: System-wide\n"
    printf "  - Target Directory:  ${INSTALL_DIR}\n"
    printf "  - Service User:      ${SERVICE_USER}\n"
else
    IS_ROOT=0
    INSTALL_DIR="$HOME/.manul"
    printf "Running as standard user.\n"
    printf "  - Installation Type: User-local\n"
    printf "  - Target Directory:  ${INSTALL_DIR}\n"
fi

# -----------------------------------------------------------------------------
# Helper: Version Comparison
# -----------------------------------------------------------------------------
version_ge() {
    printf '%s\n%s' "$2" "$1" | sort -C -V
}

check_macos_version() {
    local MIN_MAJOR=11 # Big Sur
    local CURRENT_MAJOR
    CURRENT_MAJOR=$(sw_vers -productVersion | cut -d'.' -f1)

    if [ "$CURRENT_MAJOR" -lt "$MIN_MAJOR" ]; then
        printf "${RED}Error: macOS 11 (Big Sur) or newer is required.${NC}\n"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# 1. Detect OS & Arch
# -----------------------------------------------------------------------------
OS="$(uname -s)"
ARCH="$(uname -m)"
ASSET_NAME=""

if [ "$OS" = "Linux" ]; then
    if [ -f "/etc/alpine-release" ]; then
        if [ "$ARCH" = "x86_64" ]; then
            ASSET_NAME="manul-alpine-amd64.tar.gz"
        elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
            ASSET_NAME="manul-alpine-aarch64.tar.gz"
        else
            printf "${RED}Error: Linux architecture $ARCH is not supported yet.${NC}\n"
            exit 1
        fi
    else    
        if [ "$ARCH" = "x86_64" ]; then
            ASSET_NAME="manul-linux-amd64.tar.gz"
        elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
            ASSET_NAME="manul-linux-aarch64.tar.gz"
        else
            printf "${RED}Error: Linux architecture $ARCH is not supported yet.${NC}\n"
            exit 1
        fi
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
BASE_DOMAIN="github.com"
if ! command -v curl > /dev/null; then printf "${RED}Error: curl required.${NC}\n"; exit 1; fi

printf "Detecting region to select best mirror...\n"

is_china() {
    if [ "$REGION" = "CN" ]; then return 0; fi
    if ! curl -s --connect-timeout 2 -I https://www.google.com >/dev/null; then
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
# 2. Check Dependencies
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
if [ $(ls -1 "$EXTRACT_DIR" | wc -l) -eq 1 ]; then
    NESTED_DIR=$(ls -1 "$EXTRACT_DIR")
    if [ -d "$EXTRACT_DIR/$NESTED_DIR" ]; then
        SOURCE_DIR="$EXTRACT_DIR/$NESTED_DIR"
    fi
fi

# -----------------------------------------------------------------------------
# 4. Create Service User (Root Only)
# -----------------------------------------------------------------------------
create_service_user() {
    if [ "$OS" = "Linux" ]; then
        if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
            printf "Creating user '${SERVICE_USER}'...\n"
            # Try useradd (standard), fallback to adduser (Alpine)
            if command -v useradd >/dev/null; then
                useradd -r -s /sbin/nologin -d "$INSTALL_DIR" -M "$SERVICE_USER"
            elif command -v adduser >/dev/null; then
                adduser -S -H -D -h "$INSTALL_DIR" -s /sbin/nologin "$SERVICE_USER"
            else
                printf "${RED}Error: Could not create user. Neither 'useradd' nor 'adduser' found.${NC}\n"
                exit 1
            fi
        fi
    elif [ "$OS" = "Darwin" ]; then
        if ! dscl . -read /Users/"$SERVICE_USER" >/dev/null 2>&1; then
            printf "Creating user '${SERVICE_USER}'...\n"
            
            # Find a free UniqueID > 400
            MAX_ID=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -ug | tail -1)
            NEW_ID=$((MAX_ID + 1))
            if [ "$NEW_ID" -lt 400 ]; then NEW_ID=401; fi
            
            dscl . -create /Users/"$SERVICE_USER"
            dscl . -create /Users/"$SERVICE_USER" UserShell /usr/bin/false
            dscl . -create /Users/"$SERVICE_USER" RealName "Manul Service User"
            dscl . -create /Users/"$SERVICE_USER" UniqueID "$NEW_ID"
            dscl . -create /Users/"$SERVICE_USER" PrimaryGroupID 20  # Group 20 is 'staff'
            
            printf "User created with ID ${NEW_ID}.\n"
        fi
    fi
}

if [ "$IS_ROOT" -eq 1 ]; then
    create_service_user
fi

# -----------------------------------------------------------------------------
# 5. Install Files & Apply Permissions
# -----------------------------------------------------------------------------
printf "Installing to ${INSTALL_DIR}...\n"

# Remove previous install if exists
if [ -d "$INSTALL_DIR" ]; then rm -rf "$INSTALL_DIR"; fi

mkdir -p "$INSTALL_DIR"
cp -R "$SOURCE_DIR/"* "$INSTALL_DIR/"
rm -rf "$TEMP_DIR"

# Apply ownership if running as root
if [ "$IS_ROOT" -eq 1 ]; then
    printf "Applying permissions for user '${SERVICE_USER}'...\n"
    chown -R "${SERVICE_USER}:" "$INSTALL_DIR"
fi

# -----------------------------------------------------------------------------
# 6. Configure Service
# -----------------------------------------------------------------------------
printf "Configuring ${BLUE}manul-server${NC} as a service...\n"

if [ "$OS" = "Darwin" ]; then
    # --- macOS ---
    if [ "$IS_ROOT" -eq 1 ]; then
        LAUNCH_DIR="/Library/LaunchDaemons"
        LOG_DIR="/var/log/manul"
    else
        LAUNCH_DIR="$HOME/Library/LaunchAgents"
        LOG_DIR="$HOME/Library/Logs/Manul"
    fi
    
    mkdir -p "$LAUNCH_DIR"
    mkdir -p "$LOG_DIR"
    
    # Fix log permissions for root install
    if [ "$IS_ROOT" -eq 1 ]; then
        chown "${SERVICE_USER}:" "$LOG_DIR"
    fi

    PLIST_PATH="${LAUNCH_DIR}/com.manul.server.plist"

    # For macOS, we construct the plist. 
    # If ROOT, we add the UserName key to run as specific user.
    USER_KEY=""
    if [ "$IS_ROOT" -eq 1 ]; then
        USER_KEY="<key>UserName</key><string>${SERVICE_USER}</string>"
    fi

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
    ${USER_KEY}
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
    # --- Linux ---
    if command -v systemctl > /dev/null; then
        # --- Systemd ---
        SERVICE_USER_CONFIG=""
        SERVICE_GROUP_CONFIG=""
        CAN_START_SERVICE=1
        
        if [ "$IS_ROOT" -eq 1 ]; then
            SYSTEMD_DIR="/etc/systemd/system"
            SCTL_CMD="systemctl"
            SERVICE_USER_CONFIG="User=${SERVICE_USER}"
            SERVICE_GROUP_CONFIG="Group=${SERVICE_USER}"
        else
            SYSTEMD_DIR="$HOME/.config/systemd/user"
            export XDG_RUNTIME_DIR="/run/user/$(id -u)"
            
            if [ ! -d "$XDG_RUNTIME_DIR" ]; then
                printf "${YELLOW}Warning: manul-server service could not be started automatically because this session\n"
                printf "does not have access to the systemd user bus (common with 'su' without login).\n\n"
                printf "To enable the service, perform a full login and run:\n"
                printf "  ${CYAN}systemctl --user daemon-reload${NC}\n"
                printf "  ${CYAN}systemctl --user enable manul-server${NC}\n"
                printf "  ${CYAN}systemctl --user start manul-server${NC}\n"
                CAN_START_SERVICE=0
            else
                SCTL_CMD="systemctl --user"
            fi
        fi

        SERVICE_PATH="${SYSTEMD_DIR}/manul-server.service"
        mkdir -p "$SYSTEMD_DIR"

        cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Manul Server
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/bin/manul-server
WorkingDirectory=${INSTALL_DIR}
Restart=always
${SERVICE_USER_CONFIG}
${SERVICE_GROUP_CONFIG}

[Install]
WantedBy=default.target
EOF

        if [ "$CAN_START_SERVICE" -eq 1 ]; then
            $SCTL_CMD daemon-reload
            $SCTL_CMD enable manul-server
            $SCTL_CMD restart manul-server
        fi
    else
        printf "${YELLOW}Warning: Unknown init system. Service not configured.${NC}\n"
    fi
fi

# -----------------------------------------------------------------------------
# 7. Shell Configuration
# -----------------------------------------------------------------------------
printf "Configuring shell environment...\n"

if [ "$IS_ROOT" -eq 1 ]; then
    # =========================================================
    # SYSTEM-WIDE (ROOT) STRATEGY: SYMLINKS
    # =========================================================
    TARGET_BIN_DIR="/usr/local/bin"
    printf "System-wide install: Creating symlinks in ${TARGET_BIN_DIR}...\n"
    
    mkdir -p "$TARGET_BIN_DIR"
    
    for bin_file in "${INSTALL_DIR}/bin/"*; do
        if [ -f "$bin_file" ] && [ -x "$bin_file" ]; then
            name=$(basename "$bin_file")
            ln -sf "$bin_file" "${TARGET_BIN_DIR}/${name}"
            printf "  Linked: ${name} -> ${TARGET_BIN_DIR}/${name}\n"
        fi
    done
    printf "${GREEN}System-wide installation complete.${NC}\n"

else
    # =========================================================
    # USER-LOCAL STRATEGY: SHELL CONFIG
    # =========================================================
    mkdir -p "${INSTALL_DIR}/bin"

    # Standard env file
    ENV_SCRIPT="${INSTALL_DIR}/bin/env"
    cat > "$ENV_SCRIPT" <<EOF
#!/bin/sh
export PATH="${INSTALL_DIR}/bin:\$PATH"
EOF

    # Fish env file
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

    add_to_path() {
        local cfg="$1"
        local cmd="$2"

        if [ ! -f "$cfg" ]; then 
            mkdir -p "$(dirname "$cfg")"
            touch "$cfg"
        fi

        if grep -q "$INSTALL_DIR" "$cfg"; then
            printf "${GREEN}Checked: ${cfg} already contains Manul path.${NC}\n"
        else
            printf "Adding Manul path to ${BLUE}${cfg}${NC}...\n"
            echo "" >> "$cfg"
            echo "# Manul Programming Language" >> "$cfg"
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
    
    case ":$PATH:" in
    *":${INSTALL_DIR}/bin:"*)
        printf "You can run ${BLUE}manul${NC} immediately.\n"
        ;;
    *)
        printf "${YELLOW}Action Required:${NC} To use 'manul' in this terminal, run:\n"
        printf "\n    ${CYAN}${SOURCE_CMD}${NC}\n\n"
        ;;
    esac
fi