# STEEL.TF Installer & Sync Utilities

⚠️ **ARCHITECTURE UPDATE (2026):** We now use a Portainer-first architecture. These scripts only synchronize private GitHub repositories. Container deployment and Cloudflare Zero Trust tunnel routing are handled independently via Portainer.

## 🚀 Initial Installation
Run this to bootstrap the environment and generate secure credentials:
`bash <(curl -sL https://raw.githubusercontent.com/steeltf/installer/main/install.sh)`

## 🔄 Routine Updates
When a new update drops, run the sync script to pull the code:
`bash <(curl -sL https://raw.githubusercontent.com/steeltf/installer/main/sync.sh)`
Then, go to your `Steel-App` stack in Portainer, toggle **"Re-pull image and redeploy"**, and click **Update the stack**.