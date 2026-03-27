# STEEL.TF Installer

This repository contains the installer script for the STEEL.TF stack.
It handles cloning the necessary private repositories, configuring the environment, and deploying the Docker containers.

## 🚀 Installation

Run this command in your Unraid Terminal or SSH session:

```bash
bash <(curl -sL https://raw.githubusercontent.com/steeltf/installer/main/install.sh)
```

### Requirements

*   **Authentication**: You will need a GitHub Username and a **Personal Access Token (PAT)** with `repo` scope.
    *   *Note: If the organization enforces SAML SSO, ensure your token is explicitly authorized for the organization in GitHub settings.*
*   **Configuration**: The installer will prompt you for:
    *   Steam API Key
    *   Cloudflare API Token & Account ID
    *   Domain Name

### CLI Tool Usage (Optional)
You can install this script as a command-line tool named `tf` to easily update your stack later.

```bash
curl -sL https://raw.githubusercontent.com/steeltf/installer/main/install.sh > /usr/local/bin/tf
chmod +x /usr/local/bin/tf
```

Now you can run this command to pull the latest changes and rebuild:
```bash
tf update
```
The `update` command will also automatically update the `tf` tool itself if a new version is available.