# STEEL.TF Installer & Sync Utilities

Portainer remains the container management UI. The installer and Unraid build
script synchronize source, back up the SQLite database, build the image, and
redeploy the app. Automatic updates run that flow from a self-hosted GitHub
Actions runner on the Docker host.

## 🚀 Initial Installation
Run this to bootstrap the environment and generate secure credentials:
`bash <(curl -sL https://raw.githubusercontent.com/steeltf/installer/main/install.sh)`

## 🔄 Manual Updates
If automatic deployment is not configured, run the sync script to pull the code:
`bash <(curl -sL https://raw.githubusercontent.com/steeltf/installer/main/sync.sh)`
Then, go to your `Steel-App` stack in Portainer, toggle **"Re-pull image and redeploy"**, and click **Update the stack**.

For automatic deployments, configure the `steel-tf-deploy` organization
self-hosted GitHub Actions runner on the Docker host and set the organization
Actions variable `STEELTF_INSTALL_DIR` to the installation directory. Deploy
workflows run after pushes or merged pull requests to `main`; Dependabot
changes therefore deploy after merge. The workflow uses the installer to sync
and build the stack, and the build script backs up the live SQLite database
before pulling the Node.js base image. Backups older than 30 days are removed
after a new backup succeeds.

## 👥 Credits & Ownership
- **Owner & Developer:** Emiel ([☁]Emiel)
- **Early Contributors:** snacks (limited early contributions to the API and demo parser)
