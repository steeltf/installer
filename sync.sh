#!/bin/bash
echo "================================================"
echo "   STEEL.TF | Code Sync & Build"
echo "================================================"

INSTALL_DIR="/opt/steel.tf"
CONFIG_FILE="$INSTALL_DIR/.install_config"

if [ -f "/etc/unraid-version" ]; then
    INSTALL_DIR="/mnt/user/appdata/steel.tf"
    CONFIG_FILE="$INSTALL_DIR/.install_config"
fi

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "❌ Error: .install_config not found. Run the original install.sh first."
    exit 1
fi

if [ -z "$GH_USER" ] || [ -z "$GH_TOKEN" ]; then
    echo "❌ Error: GitHub credentials missing. Run install.sh to re-authenticate."
    exit 1
fi

cd "$INSTALL_DIR" || exit 1
REPOS=("api" "frontend" "parser" "unraid")
BASE_URL="github.com/steeltf"

for repo in "${REPOS[@]}"; do
    if [ -d "$repo" ]; then
        echo "🔄 Syncing $repo..."
        cd "$repo"
        git remote set-url origin "https://${GH_USER}:${GH_TOKEN}@${BASE_URL}/${repo}.git"
        git fetch origin
        git checkout "${TARGET_VERSION:-main}"
        git pull origin "${TARGET_VERSION:-main}"
        git submodule update --init --recursive
        cd ..
    fi
done

echo "🔨 Building new Docker image natively on the host..."
# We run the build command here so Portainer doesn't have to!
docker build --network host -t steeltf-local:latest -f unraid/Dockerfile .

echo "------------------------------------------------"
echo "✅ Build complete! Head over to Portainer and restart your Steel-App stack."