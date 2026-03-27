#!/bin/bash

# Self-update logic for 'tf update'
if [ "$1" == "update" ]; then
    # Resolve the absolute path of the script being run.
    SCRIPT_PATH=$(readlink -f "$0")

    # Only self-update if it's an installed command (heuristic: it's in a 'bin' directory).
    if [[ "$SCRIPT_PATH" == */bin/* ]]; then
        INSTALLER_URL="https://raw.githubusercontent.com/steeltf/installer/main/install.sh"
        echo "Checking for installer updates..."
        if curl -sL "$INSTALLER_URL" -o "$SCRIPT_PATH.tmp"; then
            if ! cmp -s "$SCRIPT_PATH" "$SCRIPT_PATH.tmp"; then
                echo "Installer has an update. Applying..."
                chmod +x "$SCRIPT_PATH.tmp"
                mv "$SCRIPT_PATH.tmp" "$SCRIPT_PATH"
                echo "Relaunching update..."
                exec "$SCRIPT_PATH" "$@"
                exit
            else
                rm "$SCRIPT_PATH.tmp"
            fi
        fi
    fi
fi

# Helper to read input from TTY even if script is piped via curl
read_tty() {
    if [ -t 0 ]; then
        read "$@"
    else
        # Redirect input from the terminal if stdin is a pipe
        if [ -c /dev/tty ]; then
            read "$@" < /dev/tty
        fi
    fi
}

# STEEL.TF - Full Stack Installer for Unraid
# Usage: ./install.sh
# This script bootstraps the environment by pulling source code from private GitHub repos
# and then triggering the local build process.

# Default for generic Linux
DEFAULT_DIR="/opt/steel.tf"
INSTALLER_TYPE="Generic Linux"

# Check for Unraid
if [ -f "/etc/unraid-version" ]; then
    DEFAULT_DIR="/mnt/user/appdata/steel.tf"
    INSTALLER_TYPE="Unraid"
fi

echo "================================================"
echo "   STEEL.TF | $INSTALLER_TYPE Deployment Installer"
echo "================================================"

if [ "$1" == "restart" ]; then
    echo "🔄 Restarting containers..."
    docker restart steel-tf steel-tf-tunnel-primary steel-tf-tunnel-replica
    if [ $? -ne 0 ]; then
        echo "❌ Error: Failed to restart containers. Are they running?"
        exit 1
    fi
    echo "✅ Containers restarted."
    exit 0
fi

if [ "$1" == "backup" ]; then
    TARGET_DIR="${INSTALL_DIR:-$DEFAULT_DIR}"
    if [ ! -d "$TARGET_DIR" ]; then
        echo "❌ Error: Installation directory not found at $TARGET_DIR"
        echo "   If you installed to a custom location, run: INSTALL_DIR=/path/to/install tf backup"
        exit 1
    fi
    cd "$TARGET_DIR" || exit 1

    echo "📦 Triggering database backup..."
    # Assumes the container is named 'steel-tf' and has a 'tf' CLI tool inside.
    BACKUP_MSG=$(docker exec steel-tf tf backup-db 2>&1)
    if [ $? -ne 0 ]; then
        echo "❌ Error: Failed to trigger backup. Is the 'steel-tf' container running?"
        echo "   > $BACKUP_MSG"
        exit 1
    fi
    echo "✅ ${BACKUP_MSG}"

    echo "📦 Archiving data and settings..."
    TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
    mkdir -p backups
    ARCHIVE="backups/backup_$TIMESTAMP.tar.gz"
    
    FILES="data"
    [ -f "unraid/.env" ] && FILES="$FILES unraid/.env"
    [ -f ".install_config" ] && FILES="$FILES .install_config"

    # Archive data folder (excluding active active DB lock files), .env, and config
    tar --exclude='data/database.db' --exclude='data/database.db-shm' --exclude='data/database.db-wal' --exclude='backups' \
        -czf "$ARCHIVE" $FILES 2>/dev/null

    if [ -f "$ARCHIVE" ]; then
        echo "✅ Archive created: $TARGET_DIR/$ARCHIVE"
        # Keep last 7 days of archives and raw db dumps
        find backups -name "backup_*.tar.gz" -mtime +7 -delete
        find data -name "backup-*.db" -mtime +7 -delete
    else
        echo "❌ Error creating archive."
        exit 1
    fi
    exit 0
fi

if [ "$1" == "restore" ]; then
    TARGET_DIR="${INSTALL_DIR:-$DEFAULT_DIR}"
    if [ ! -d "$TARGET_DIR" ]; then
        echo "❌ Error: Installation directory not found at $TARGET_DIR"
        echo "   If you installed to a custom location, run: INSTALL_DIR=/path/to/install tf restore"
        exit 1
    fi
    cd "$TARGET_DIR" || exit 1

    # Check for backups dir
    if [ ! -d "backups" ] || [ -z "$(ls -A backups/*.tar.gz 2>/dev/null)" ]; then
        echo "❌ Error: No backups found in $TARGET_DIR/backups/"
        exit 1
    fi

    BACKUP_FILE="$2"

    if [ -z "$BACKUP_FILE" ]; then
        echo "📂 Available backups:"
        # Use array for reliable indexing
        files=(backups/*.tar.gz)
        for i in "${!files[@]}"; do
            echo "   [$((i+1))] ${files[$i]}"
        done
        
        read_tty -p "Select a backup number: " SELECTION
        if [[ "$SELECTION" =~ ^[0-9]+$ ]] && [ "$SELECTION" -ge 1 ] && [ "$SELECTION" -le "${#files[@]}" ]; then
            BACKUP_FILE="${files[$((SELECTION-1))]}"
        else
            echo "❌ Invalid selection."
            exit 1
        fi
    fi

    if [ ! -f "$BACKUP_FILE" ]; then
        echo "❌ Error: Backup file '$BACKUP_FILE' not found."
        exit 1
    fi

    echo ""
    echo "⚠️  WARNING: RESTORE IN PROGRESS"
    echo "   Target: $BACKUP_FILE"
    echo "   This will STOP containers and OVERWRITE your current data/ database and configuration."
    read_tty -p "   Type 'yes' to confirm: " -r
    echo ""
    if [[ ! $REPLY == "yes" ]]; then
        echo "🚫 Restore cancelled."
        exit 0
    fi

    echo "🛑 Stopping containers..."
    docker stop steel-tf steel-tf-tunnel-primary steel-tf-tunnel-replica 2>/dev/null

    echo "📦 Extracting archive..."
    # Remove existing backup dumps to ensure we identify the restored one correctly
    rm -f data/backup-*.db
    tar -xzf "$BACKUP_FILE"
    
    echo "🔄 Restoring database..."
    LATEST_DB_DUMP=$(ls -t data/backup-*.db 2>/dev/null | head -n 1)
    if [ -n "$LATEST_DB_DUMP" ]; then
        cp "$LATEST_DB_DUMP" data/database.db
        echo "✅ Database restored from $(basename "$LATEST_DB_DUMP")."
    fi

    echo "🚀 Restarting containers..."
    docker start steel-tf steel-tf-tunnel-primary steel-tf-tunnel-replica

    echo "✅ Restore complete."
    exit 0
fi

if [ "$1" == "logs" ]; then
    echo "📋 Following logs for steel-tf container... (Ctrl+C to exit)"
    docker logs -f steel-tf
    exit 0
fi

SKIP_PROMPTS=false
if [ "$1" == "update" ]; then
    SKIP_PROMPTS=true
    echo "🔄 Update mode enabled. Using defaults."
fi

# 1. Environment Check
if ! command -v git &> /dev/null; then
    if [ "$INSTALLER_TYPE" == "Unraid" ]; then
        echo "❌ Error: 'git' is required. Please install it via NerdTools or the plugin manager."
    else
        echo "❌ Error: 'git' is required. Please install it using your system's package manager (e.g., 'apt install git' or 'yum install git')."
    fi
    exit 1
fi

# Check for Docker
if ! command -v docker &> /dev/null; then
    if [ "$INSTALLER_TYPE" == "Unraid" ]; then
        echo "❌ Error: Docker is not enabled/installed. Please enable it in Unraid Settings."
        exit 1
    else
        echo "⚠️  Docker is not installed."
        read_tty -p "   Would you like to install Docker automatically? (Y/n) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo "⬇️  Installing Docker via official script..."
            if command -v curl &> /dev/null; then
                curl -fsSL https://get.docker.com | sh
            elif command -v wget &> /dev/null; then
                wget -qO- https://get.docker.com | sh
            else
                echo "❌ Error: Neither 'curl' nor 'wget' found. Cannot install Docker automatically."
                exit 1
            fi
            
            if [ $? -ne 0 ]; then
                echo "❌ Error: Docker installation failed."
                exit 1
            fi

            # Start service
            echo "🔄 Starting Docker service..."
            if command -v systemctl &> /dev/null; then
                systemctl enable --now docker
            elif command -v service &> /dev/null; then
                service docker start
            fi

            # Add user to group
            TARGET_USER=${SUDO_USER:-$USER}
            if [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ]; then
                echo "👤 Adding $TARGET_USER to 'docker' group..."
                usermod -aG docker "$TARGET_USER"
                echo "⚠️  Group membership updated. You may need to log out and back in for this to apply."
            fi
        else
            echo "❌ Error: Docker is required to proceed."
            exit 1
        fi
    fi
fi

# Verify Docker is running
if ! docker info &> /dev/null; then
    if [ "$INSTALLER_TYPE" == "Unraid" ]; then
        echo "❌ Error: Docker service is not running. Please enable it in Unraid Settings."
        exit 1
    else
        echo "⚠️  Docker service not detected or permission denied."
        echo "🔄 Attempting to start service..."
        if command -v systemctl &> /dev/null; then
            systemctl start docker
        elif command -v service &> /dev/null; then
            service docker start
        fi
        
        sleep 2
        if ! docker info &> /dev/null; then
            echo "❌ Error: Unable to communicate with Docker daemon."
            echo "   Ensure the service is running and '$USER' is in the 'docker' group."
            exit 1
        fi
    fi
fi
echo "✅ Docker is operational."

# Check for Docker Compose
if ! docker compose version &> /dev/null; then
    if [ "$INSTALLER_TYPE" == "Unraid" ]; then
        echo "❌ Error: 'docker compose' is not available. Please install the Docker Compose plugin via NerdTools or Update Unraid."
        exit 1
    else
        echo "⚠️  'docker compose' subcommand is missing."
        if [ "$SKIP_PROMPTS" = true ]; then
            echo "   Skipping Docker Compose install in update mode."
        else
            read_tty -p "   Would you like to install the Docker Compose plugin? (Y/n) " -n 1 -r
            echo ""
        fi
        
        if [[ ! $REPLY =~ ^[Nn]$ ]] && [ "$SKIP_PROMPTS" = false ]; then
            echo "⬇️  Installing Docker Compose plugin..."
            
            # Helper for sudo
            SUDO=""
            if [ "$EUID" -ne 0 ] && command -v sudo &> /dev/null; then
                SUDO="sudo"
            fi

            if command -v apt-get &> /dev/null; then
                $SUDO apt-get update && $SUDO apt-get install -y docker-compose-plugin
            elif command -v yum &> /dev/null; then
                $SUDO yum install -y docker-compose-plugin
            elif command -v dnf &> /dev/null; then
                $SUDO dnf install -y docker-compose-plugin
            else
                # Manual install to user directory as fallback
                echo "   Package manager not found. Installing to ~/.docker/cli-plugins..."
                DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
                mkdir -p $DOCKER_CONFIG/cli-plugins
                curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m) -o $DOCKER_CONFIG/cli-plugins/docker-compose
                chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
            fi

            if ! docker compose version &> /dev/null; then
                echo "❌ Error: Docker Compose installation failed."
                exit 1
            fi
        else
            echo "❌ Error: Docker Compose is required."
            exit 1
        fi
    fi
fi
echo "✅ Docker Compose is available."

# 1.5 Portainer UI Check
if [ "$INSTALLER_TYPE" != "Unraid" ]; then
    if ! docker ps | grep -q portainer; then
        echo ""
        echo "🚢 Portainer (Docker UI) not detected."
        if [ "$SKIP_PROMPTS" = false ]; then
            read_tty -p "   Would you like to install Portainer to manage your containers via Web UI? (Y/n) " -n 1 -r
            echo ""
        else
            REPLY="Y"
        fi
        
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo "⬇️  Installing Portainer..."
            docker volume create portainer_data >/dev/null 2>&1
            docker run -d -p 10.0.0.1:8000:8000 -p 10.0.0.1:9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
            echo "✅ Portainer is now running! Access it via WireGuard at: https://10.0.0.1:9443"
        fi
    fi
else
    echo ""
    echo "✅ Skipping Portainer UI installation (Unraid UI detected)."
fi

# 2. Configuration
echo "This will install/update the stack at the specified location."

if [ "$SKIP_PROMPTS" = true ]; then
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_DIR}
    echo "   Target: $INSTALL_DIR"
else
    read_tty -p "Install Directory [$DEFAULT_DIR]: " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_DIR}
fi

# Load saved credentials if available
CONFIG_FILE="$INSTALL_DIR/.install_config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

if [ "$SKIP_PROMPTS" = true ]; then
    TARGET_VERSION=${TARGET_VERSION:-main}
    echo "   Version: $TARGET_VERSION"
else
    read_tty -p "Install Version/Tag [main]: " TARGET_VERSION
    TARGET_VERSION=${TARGET_VERSION:-main}
fi

echo ""
echo "🔒 Authentication Required (Private Repos)"

# Check for saved credentials and ask to use/clear them
if [ -n "$GH_USER" ] && [ -n "$GH_TOKEN" ]; then
    echo "   ✅ Using saved credentials for user '$GH_USER'."
    if [ "$SKIP_PROMPTS" = false ]; then
        read_tty -p "   Would you like to clear these and enter new ones? (y/N) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            GH_USER=""
            GH_TOKEN=""
            rm -f "$CONFIG_FILE" 2>/dev/null
            echo "   🗑️  Cleared saved credentials."
        fi
    fi
fi

# Prompt for credentials if they are not set (either because they were never there, or were just cleared)
if [ -z "$GH_USER" ] || [ -z "$GH_TOKEN" ]; then
    echo "   Enter your GitHub Username and a Personal Access Token (PAT)."
    echo "   (PAT must have 'repo' scope. If Org uses SAML, authorize the token.)"
    read_tty -p "GitHub Username: " GH_USER
    read_tty -s -p "GitHub Token: " GH_TOKEN
    echo ""
    echo ""
fi

if [ -z "$GH_USER" ] || [ -z "$GH_TOKEN" ]; then
    echo "❌ Error: Credentials cannot be empty."
    exit 1
fi

# 3. Prepare Directory
echo "📂 Preparing directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || { echo "❌ Failed to access install directory."; exit 1; }

# 4. Clone / Update Repositories
REPOS=("api" "frontend" "parser" "unraid")
BASE_URL="github.com/steeltf"

for repo in "${REPOS[@]}"; do
    if [ -d "$repo" ]; then
        echo "🔄 Updating existing repo: $repo"
        cd "$repo"
        # Update remote URL with new credentials in case they changed, then pull
        git remote set-url origin "https://${GH_USER}:${GH_TOKEN}@${BASE_URL}/${repo}.git"
        git fetch origin
        if git checkout "$TARGET_VERSION"; then
            git pull origin "$TARGET_VERSION"
            # --- FIX: Update submodules when pulling ---
            git submodule update --init --recursive
        else
            echo "⚠️  Warning: Failed to checkout $TARGET_VERSION for $repo. Staying on current branch."
        fi
        cd ..
    else
        echo "⬇️  Cloning new repo: $repo ($TARGET_VERSION)"
        # --- FIX: Clone with --recursive to pull submodules automatically ---
        git clone --recursive -b "$TARGET_VERSION" "https://${GH_USER}:${GH_TOKEN}@${BASE_URL}/${repo}.git"
        if [ $? -ne 0 ]; then
            echo "❌ Critical Error: Failed to clone $repo (branch: $TARGET_VERSION)."
            exit 1
        fi
    fi
done

# 5. Configure Environment (.env)
echo ""
echo "📝 Configuration"
echo "   We can auto-generate the .env file for you."
echo "   Press Enter to accept [defaults] or skip."

DEFAULT_CPU_SET=""

DEFAULT_MEM_LIMIT="4G"
DEFAULT_MEM_RESERVATION="256M"

ENV_FILE="unraid/.env"
EXISTING_KEY=""

if [ -f "$ENV_FILE" ]; then
    echo "   (Loaded defaults from $ENV_FILE)"
    DEF_STEAM_KEY=$(grep "^STEAM_API_KEY=" "$ENV_FILE" | cut -d'=' -f2-)
    DEF_ADMIN_IDS=$(grep "^ADMIN_IDS=" "$ENV_FILE" | cut -d'=' -f2-)
    DEF_CF_TOKEN=$(grep "^CLOUDFLARE_API_TOKEN=" "$ENV_FILE" | cut -d'=' -f2-)
    DEF_CF_ACCOUNT=$(grep "^CLOUDFLARE_ACCOUNT_ID=" "$ENV_FILE" | cut -d'=' -f2-)
    DEF_DOMAIN=$(grep "^TUNNEL_DOMAIN=" "$ENV_FILE" | cut -d'=' -f2-)
    DEF_CPU_SET=$(grep "^CPU_SET=" "$ENV_FILE" | cut -d'=' -f2-)
    DEF_MEM_LIMIT=$(grep "^MEM_LIMIT=" "$ENV_FILE" | cut -d'=' -f2-)
    DEF_MEM_RESERVATION=$(grep "^MEM_RESERVATION=" "$ENV_FILE" | cut -d'=' -f2-)
    EXISTING_KEY=$(grep "^KEY=" "$ENV_FILE" | cut -d'=' -f2-)
fi

ask() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local input
    
    if [ "$SKIP_PROMPTS" = true ]; then
        if [ -n "$default" ]; then echo "   $prompt: $default"; fi
        eval $var_name='${default}'
        return
    fi

    if [ -n "$default" ]; then
        read_tty -p "$prompt [$default]: " input
        eval $var_name='${input:-$default}'
    else
        read_tty -p "$prompt: " input
        eval $var_name='$input'
    fi
}

ask "Steam API Key" "$DEF_STEAM_KEY" "STEAM_API_KEY"
ask "Steam Admin ID64s (comma separated)" "$DEF_ADMIN_IDS" "ADMIN_IDS"
ask "Cloudflare API Token" "$DEF_CF_TOKEN" "CLOUDFLARE_API_TOKEN"
ask "Cloudflare Account ID" "$DEF_CF_ACCOUNT" "CLOUDFLARE_ACCOUNT_ID"
ask "Tunnel Domain (e.g. steel.tf)" "$DEF_DOMAIN" "TUNNEL_DOMAIN"
ask "CPU Allocation (Leave blank for standard scheduling)" "${DEF_CPU_SET:-${CPU_SET:-$DEFAULT_CPU_SET}}" "CPU_SET"
ask "Memory Limit (e.g. 4G)" "${DEF_MEM_LIMIT:-${MEM_LIMIT:-$DEFAULT_MEM_LIMIT}}" "MEM_LIMIT"
ask "Memory Reservation (e.g. 256M)" "${DEF_MEM_RESERVATION:-${MEM_RESERVATION:-$DEFAULT_MEM_RESERVATION}}" "MEM_RESERVATION"

if [ -n "$STEAM_API_KEY" ] || [ -n "$ADMIN_IDS" ] || [ -n "$CLOUDFLARE_API_TOKEN" ] || [ -n "$CLOUDFLARE_ACCOUNT_ID" ] || [ -n "$TUNNEL_DOMAIN" ] || [ -n "$CPU_SET" ] || [ -n "$MEM_LIMIT" ] || [ -n "$MEM_RESERVATION" ]; then
    SHOULD_WRITE=true
    
    if [ -f "$ENV_FILE" ]; then
        if [ "$SKIP_PROMPTS" = false ]; then
            read_tty -p "⚠️  Update $ENV_FILE with these values? (Y/n) " -n 1 -r
            echo "" # move to a new line
        fi
        
        if [[ $REPLY =~ ^[Nn]$ ]] || [ "$SKIP_PROMPTS" = true ]; then
            SHOULD_WRITE=false
            echo "⏩ Skipping .env update."
        fi
    fi

    if [ "$SHOULD_WRITE" = true ]; then
        if [ -n "$EXISTING_KEY" ]; then
            GEN_KEY="$EXISTING_KEY"
        elif command -v openssl &> /dev/null; then
            GEN_KEY=$(openssl rand -hex 32)
        else
            GEN_KEY=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')
        fi

        if [ -z "$CPU_SET" ]; then
            ENV_CPU_SET="# CPU_SET=\"\""
        else
            ENV_CPU_SET="CPU_SET=$CPU_SET"
        fi

        cat > "$ENV_FILE" <<EOF
STEAM_API_KEY=$STEAM_API_KEY
KEY=$GEN_KEY
ADMIN_IDS=$ADMIN_IDS
CLOUDFLARE_API_TOKEN=$CLOUDFLARE_API_TOKEN
CLOUDFLARE_ACCOUNT_ID=$CLOUDFLARE_ACCOUNT_ID
TUNNEL_DOMAIN=$TUNNEL_DOMAIN
$ENV_CPU_SET
MEM_LIMIT=$MEM_LIMIT
MEM_RESERVATION=$MEM_RESERVATION
# Tunnel Protocol: http2 (default, stable) or quic (faster, requires UDP support)
# Uncomment the line below to enable QUIC
# TUNNEL_PROTOCOL=quic
# Post-Quantum Encryption (requires QUIC)
# TUNNEL_POST_QUANTUM=true
EOF
        echo "✅ Created/Updated $ENV_FILE with provided values."
    fi
fi

# Save credentials if not exists
if [ ! -f "$CONFIG_FILE" ]; then
    if [ "$SKIP_PROMPTS" = false ]; then
        read_tty -p "💾 Save GitHub credentials and resource settings for future updates? (Y/n) " -n 1 -r
        echo ""
    fi
    
    if [[ ! $REPLY =~ ^[Nn]$ ]] || [ "$SKIP_PROMPTS" = true ]; then
        echo "GH_USER=\"$GH_USER\"" > "$CONFIG_FILE"
        echo "GH_TOKEN=\"$GH_TOKEN\"" >> "$CONFIG_FILE"
        echo "TARGET_VERSION=\"$TARGET_VERSION\"" >> "$CONFIG_FILE"
        echo "CPU_SET=\"$CPU_SET\"" >> "$CONFIG_FILE"
        echo "MEM_LIMIT=\"$MEM_LIMIT\"" >> "$CONFIG_FILE"
        echo "MEM_RESERVATION=\"$MEM_RESERVATION\"" >> "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE" 2>/dev/null
        echo "✅ Settings saved to $CONFIG_FILE"
    fi
fi

# 6. Database Check
DATA_DIR="$INSTALL_DIR/data"
DB_FILE="$DATA_DIR/database.db"

if [ -d "$DATA_DIR" ] && [ ! -f "$DB_FILE" ]; then
    LATEST_BACKUP=$(ls -t "$DATA_DIR"/backup-*.db 2>/dev/null | head -n 1)
    if [ -n "$LATEST_BACKUP" ]; then
        echo ""
        echo "📦 Found database backup: $(basename "$LATEST_BACKUP")"
        if [ "$SKIP_PROMPTS" = false ]; then
            read_tty -p "   Restore this backup? (Y/n) " -n 1 -r
            echo ""
        fi
        if [[ ! $REPLY =~ ^[Nn]$ ]] && [ "$SKIP_PROMPTS" = false ]; then
            echo "🔄 Restoring database..."
            cp "$LATEST_BACKUP" "$DB_FILE"
            echo "✅ Database restored."
        fi
    fi
fi

# 7. Handoff to Build Script
echo ""
echo "✅ Source code synchronized."
echo "🚀 Launching build & run helper..."
echo "------------------------------------------------"

if [ -d "unraid" ] && [ -f "unraid/build_and_run.sh" ]; then
    cd unraid
    chmod +x build_and_run.sh
    
    # Execute the build script
    ./build_and_run.sh
    BUILD_EXIT_CODE=$?

    if [ $BUILD_EXIT_CODE -eq 0 ]; then
        echo "🧹 Pruning old Docker images..."
        docker image prune -f
    fi
    exit $BUILD_EXIT_CODE
else
    echo "❌ Error: 'unraid/build_and_run.sh' not found."
    echo "   The unraid repo may have failed to clone correctly."
    exit 1
fi