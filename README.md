# Raspberry Pi OS Lite Setup

A configuration script that takes a fresh Raspberry Pi OS Lite (64-bit) installation to a fully configured development server.

## Prerequisites

- Raspberry Pi with 64-bit OS Lite installed
- SSH access enabled
- Internet connectivity
- At least 2GB free disk space

## Usage

### Basic

```bash
curl -sL https://raw.githubusercontent.com/MannyPeterson/setup/master/setup.sh | sudo bash
```

### With Custom Hostname

```bash
curl -sL https://raw.githubusercontent.com/MannyPeterson/setup/master/setup.sh | sudo bash -s -- --hostname mypi
```

## What Gets Configured

| Category | Configuration |
|----------|---------------|
| **System** | Locale (en_US.UTF-8), Timezone (America/Chicago), GPU memory (16MB) |
| **Packages** | build-essential, cmake, make, gh, jq, vim, git, tree, openjdk-21-jdk-headless, powerline |
| **SSH** | Key-only authentication, root login disabled, empty passwords disabled |
| **Security** | Sudo requires password |
| **Interfaces** | SSH enabled; SPI, I2C, Serial, 1-Wire, Remote GPIO disabled |
| **Docker** | Installed and configured, user added to docker group |
| **Gradle** | Latest version installed to ~/gradle |
| **Claude Code** | Installed via official installer |
| **PostgreSQL** | Docker container created and started |
| **Shell** | Powerline prompt, PATH configured for ~/bin and ~/gradle/bin |

## Post-Installation

After the script completes:

1. **Log out and back in** for group changes to take effect
2. **Reboot** to apply GPU memory and kernel changes
3. Run `sm list` to see available services

## Service Manager

The script installs a service manager (`sm`) for controlling services:

```bash
sm postgres start    # Start PostgreSQL container
sm postgres stop     # Stop PostgreSQL container
sm postgres status   # Check if running
sm postgres info     # Show connection details
sm postgres psql     # Connect via psql client
sm gradle status     # Check Gradle daemon status
sm list              # List all services
sm help              # Show help
```

## Notes

- Script is idempotent - safe to run multiple times
- Designed for headless operation (no GUI dependencies)
- Wired Ethernet assumed (WiFi country set to US to avoid warnings)
