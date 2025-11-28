#!/bin/bash
#
# Raspberry Pi OS Lite Configuration Script
# Configures a fresh Raspberry Pi OS Lite (64-bit) installation
#
# Usage: curl -sL https://raw.githubusercontent.com/USER/REPO/main/setup.sh | sudo bash
#        curl -sL https://raw.githubusercontent.com/USER/REPO/main/setup.sh | sudo bash -s -- --hostname mypi
#

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

LOCALE="en_US.UTF-8"
TIMEZONE="America/Chicago"
WIFI_COUNTRY="US"
GPU_MEMORY=16
SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDnAsDLyZP/rvE1b7grIV/FytptctB7W8Z7z8SzNjiSP"

APT_PACKAGES=(
    build-essential
    cmake
    make
    gh
    rpi-connect-lite
    jq
    openjdk-21-jdk-headless
    tree
    vim
    git
    powerline
    powerline-gitstatus
    curl
    wget
    unzip
)

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

TARGET_USER="${SUDO_USER:-}"
TARGET_HOME=""
HOSTNAME_PARAM=""
TASKS_COMPLETED=0
TASKS_TOTAL=20
WARNINGS=()

# =============================================================================
# OUTPUT FUNCTIONS
# =============================================================================

log_header() {
    echo ""
    echo "============================================================================="
    echo " $1"
    echo "============================================================================="
}

log_task() {
    TASKS_COMPLETED=$((TASKS_COMPLETED + 1))
    echo ""
    echo "[$TASKS_COMPLETED/$TASKS_TOTAL] $1"
    echo "-----------------------------------------------------------------------------"
}

log_info() {
    echo "[INFO] $1"
}

log_success() {
    echo "[OK] $1"
}

log_warning() {
    echo "[WARN] $1"
    WARNINGS+=("$1")
}

log_error() {
    echo "[ERROR] $1" >&2
}

log_skip() {
    echo "[SKIP] $1 (already configured)"
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

check_idempotent() {
    # Returns 0 if action needed, 1 if already done
    local check_type="$1"
    shift

    case "$check_type" in
        file_exists)
            [[ ! -f "$1" ]]
            ;;
        file_contains)
            ! grep -qF "$2" "$1" 2>/dev/null
            ;;
        dir_exists)
            [[ ! -d "$1" ]]
            ;;
        package_installed)
            ! dpkg -l "$1" 2>/dev/null | grep -q "^ii"
            ;;
        command_exists)
            ! command -v "$1" &>/dev/null
            ;;
        user_in_group)
            ! id -nG "$1" 2>/dev/null | grep -qw "$2"
            ;;
        *)
            return 0
            ;;
    esac
}

run_as_user() {
    sudo -u "$TARGET_USER" "$@"
}

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

preflight_checks() {
    log_task "Running pre-flight checks"

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    log_success "Running as root"

    # Check for SUDO_USER
    if [[ -z "$TARGET_USER" ]]; then
        log_error "Could not determine target user. Run with sudo, not as root directly."
        exit 1
    fi
    TARGET_HOME=$(eval echo "~$TARGET_USER")
    log_success "Target user: $TARGET_USER (home: $TARGET_HOME)"

    # Check for Raspberry Pi hardware
    if [[ -f /proc/device-tree/model ]]; then
        local pi_model
        pi_model=$(cat /proc/device-tree/model | tr -d '\0')
        if [[ "$pi_model" == *"Raspberry Pi"* ]]; then
            log_success "Detected: $pi_model"
        else
            log_warning "Unexpected hardware: $pi_model"
        fi
    else
        log_warning "Could not detect Raspberry Pi hardware"
    fi

    # Check for 64-bit architecture
    local arch
    arch=$(uname -m)
    if [[ "$arch" != "aarch64" ]]; then
        log_warning "Expected 64-bit (aarch64), found: $arch"
    else
        log_success "64-bit architecture confirmed (aarch64)"
    fi

    # Check disk space (need at least 2GB free)
    local free_space
    free_space=$(df / --output=avail -B1G | tail -1 | tr -d ' ')
    if [[ "$free_space" -lt 2 ]]; then
        log_error "Insufficient disk space (need at least 2GB free, have ${free_space}GB)"
        exit 1
    fi
    log_success "Disk space: ${free_space}GB available"
}

# =============================================================================
# PARSE ARGUMENTS
# =============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --hostname)
                HOSTNAME_PARAM="$2"
                shift 2
                ;;
            --hostname=*)
                HOSTNAME_PARAM="${1#*=}"
                shift
                ;;
            -h|--help)
                echo "Usage: sudo bash setup.sh [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --hostname NAME    Set the hostname (default: keep current or 'raspberrypi')"
                echo "  -h, --help         Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# TASK: SYSTEM UPDATE
# =============================================================================

task_system_update() {
    log_task "Updating system packages"

    log_info "Running apt update..."
    apt update -y

    log_info "Running apt full-upgrade..."
    apt full-upgrade -y

    log_success "System packages updated"
}

# =============================================================================
# TASK: SET LOCALE
# =============================================================================

task_set_locale() {
    log_task "Setting locale to $LOCALE"

    local current_locale
    current_locale=$(localectl status 2>/dev/null | grep "System Locale" | cut -d= -f2 || echo "")

    if [[ "$current_locale" == "$LOCALE" ]]; then
        log_skip "Locale already set to $LOCALE"
        return
    fi

    # Generate locale
    sed -i "s/^# *$LOCALE/$LOCALE/" /etc/locale.gen
    locale-gen

    # Set locale
    update-locale LANG="$LOCALE" LC_ALL="$LOCALE"

    log_success "Locale set to $LOCALE"
}

# =============================================================================
# TASK: SET TIMEZONE
# =============================================================================

task_set_timezone() {
    log_task "Setting timezone to $TIMEZONE"

    local current_tz
    current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "")

    if [[ "$current_tz" == "$TIMEZONE" ]]; then
        log_skip "Timezone already set to $TIMEZONE"
        return
    fi

    timedatectl set-timezone "$TIMEZONE"

    log_success "Timezone set to $TIMEZONE"
}

# =============================================================================
# TASK: SET HOSTNAME
# =============================================================================

task_set_hostname() {
    log_task "Configuring hostname"

    local current_hostname
    current_hostname=$(hostname)

    if [[ -n "$HOSTNAME_PARAM" ]]; then
        # Hostname provided as parameter
        if [[ "$current_hostname" == "$HOSTNAME_PARAM" ]]; then
            log_skip "Hostname already set to $HOSTNAME_PARAM"
            return
        fi
        hostnamectl set-hostname "$HOSTNAME_PARAM"
        sed -i "s/127.0.1.1.*/127.0.1.1\t$HOSTNAME_PARAM/" /etc/hosts
        log_success "Hostname set to $HOSTNAME_PARAM"
    elif [[ "$current_hostname" == "raspberrypi" ]]; then
        # Default hostname, no parameter provided
        log_warning "Hostname is 'raspberrypi' and no --hostname parameter provided"
        log_info "Keeping default hostname 'raspberrypi'"
    else
        # Custom hostname already set
        log_skip "Hostname already configured as '$current_hostname'"
    fi
}

# =============================================================================
# TASK: SET GPU MEMORY
# =============================================================================

task_set_gpu_memory() {
    log_task "Setting GPU memory to ${GPU_MEMORY}MB (headless optimization)"

    local config_file="/boot/firmware/config.txt"

    # Check for older path
    if [[ ! -f "$config_file" ]]; then
        config_file="/boot/config.txt"
    fi

    if [[ ! -f "$config_file" ]]; then
        log_warning "Could not find config.txt"
        return
    fi

    if grep -q "^gpu_mem=$GPU_MEMORY" "$config_file"; then
        log_skip "GPU memory already set to ${GPU_MEMORY}MB"
        return
    fi

    # Remove existing gpu_mem line if present
    sed -i '/^gpu_mem=/d' "$config_file"

    # Add new setting
    echo "gpu_mem=$GPU_MEMORY" >> "$config_file"

    log_success "GPU memory set to ${GPU_MEMORY}MB"
    log_warning "Reboot required for GPU memory change to take effect"
}

# =============================================================================
# TASK: SET WIFI COUNTRY
# =============================================================================

task_set_wifi_country() {
    log_task "Setting WiFi country to $WIFI_COUNTRY"

    if command -v raspi-config &>/dev/null; then
        raspi-config nonint do_wifi_country "$WIFI_COUNTRY" 2>/dev/null || true
        log_success "WiFi country set to $WIFI_COUNTRY"
    else
        log_warning "raspi-config not found, skipping WiFi country"
    fi
}

# =============================================================================
# TASK: DISABLE PI INTERFACES
# =============================================================================

task_disable_interfaces() {
    log_task "Disabling unused Raspberry Pi interfaces"

    if ! command -v raspi-config &>/dev/null; then
        log_warning "raspi-config not found, skipping interface configuration"
        return
    fi

    # Disable SPI (0 = disable, 1 = enable for raspi-config)
    log_info "Disabling SPI..."
    raspi-config nonint do_spi 1 2>/dev/null || true

    # Disable I2C
    log_info "Disabling I2C..."
    raspi-config nonint do_i2c 1 2>/dev/null || true

    # Disable Serial Console
    log_info "Disabling Serial Console..."
    raspi-config nonint do_serial_cons 1 2>/dev/null || true

    # Disable Serial Hardware
    log_info "Disabling Serial Hardware..."
    raspi-config nonint do_serial_hw 1 2>/dev/null || true

    # Disable 1-Wire
    log_info "Disabling 1-Wire..."
    raspi-config nonint do_onewire 1 2>/dev/null || true

    # Disable Remote GPIO
    log_info "Disabling Remote GPIO..."
    raspi-config nonint do_rgpio 1 2>/dev/null || true

    # Ensure SSH is enabled (0 = enable)
    log_info "Ensuring SSH is enabled..."
    raspi-config nonint do_ssh 0 2>/dev/null || true

    log_success "Interfaces configured (SSH enabled, others disabled)"
}

# =============================================================================
# TASK: INSTALL APT PACKAGES
# =============================================================================

task_install_packages() {
    log_task "Installing apt packages"

    local packages_to_install=()

    for pkg in "${APT_PACKAGES[@]}"; do
        if check_idempotent package_installed "$pkg"; then
            packages_to_install+=("$pkg")
        else
            log_info "$pkg already installed"
        fi
    done

    if [[ ${#packages_to_install[@]} -eq 0 ]]; then
        log_skip "All packages already installed"
        return
    fi

    log_info "Installing: ${packages_to_install[*]}"
    apt install -y "${packages_to_install[@]}"

    log_success "Packages installed"
}

# =============================================================================
# TASK: CONFIGURE SSH
# =============================================================================

task_configure_ssh() {
    log_task "Configuring SSH"

    local ssh_dir="$TARGET_HOME/.ssh"
    local auth_keys="$ssh_dir/authorized_keys"
    local sshd_config="/etc/ssh/sshd_config"

    # Create .ssh directory
    if check_idempotent dir_exists "$ssh_dir"; then
        mkdir -p "$ssh_dir"
        chown "$TARGET_USER:$TARGET_USER" "$ssh_dir"
    fi
    chmod 700 "$ssh_dir"

    # Add SSH public key
    if check_idempotent file_contains "$auth_keys" "$SSH_PUBLIC_KEY"; then
        echo "$SSH_PUBLIC_KEY" >> "$auth_keys"
        log_success "SSH public key added"
    else
        log_info "SSH public key already present"
    fi
    chown "$TARGET_USER:$TARGET_USER" "$auth_keys"
    chmod 600 "$auth_keys"

    # Harden SSH configuration
    log_info "Hardening SSH configuration..."

    # Backup original if not already backed up
    if [[ ! -f "${sshd_config}.original" ]]; then
        cp "$sshd_config" "${sshd_config}.original"
    fi

    # Disable root login
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$sshd_config"
    if ! grep -q "^PermitRootLogin" "$sshd_config"; then
        echo "PermitRootLogin no" >> "$sshd_config"
    fi

    # Disable password authentication
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"
    if ! grep -q "^PasswordAuthentication" "$sshd_config"; then
        echo "PasswordAuthentication no" >> "$sshd_config"
    fi

    # Disable empty passwords
    sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$sshd_config"
    if ! grep -q "^PermitEmptyPasswords" "$sshd_config"; then
        echo "PermitEmptyPasswords no" >> "$sshd_config"
    fi

    # Restart SSH service
    systemctl restart sshd

    log_success "SSH configured and hardened"
}

# =============================================================================
# TASK: CONFIGURE SUDO
# =============================================================================

task_configure_sudo() {
    log_task "Configuring sudo to require password"

    local sudoers_dir="/etc/sudoers.d"
    local nopasswd_file="$sudoers_dir/010_pi-nopasswd"
    local nopasswd_file2="$sudoers_dir/010_${TARGET_USER}-nopasswd"

    # Remove nopasswd files if they exist
    if [[ -f "$nopasswd_file" ]]; then
        rm -f "$nopasswd_file"
        log_info "Removed $nopasswd_file"
    fi

    if [[ -f "$nopasswd_file2" ]]; then
        rm -f "$nopasswd_file2"
        log_info "Removed $nopasswd_file2"
    fi

    # Check for any other nopasswd configurations
    for f in "$sudoers_dir"/*nopasswd*; do
        if [[ -f "$f" ]]; then
            rm -f "$f"
            log_info "Removed $f"
        fi
    done

    log_success "Sudo configured to require password"
}

# =============================================================================
# TASK: CONFIGURE BASHRC
# =============================================================================

task_configure_bashrc() {
    log_task "Configuring .bashrc"

    local bashrc="$TARGET_HOME/.bashrc"
    local marker="# === Raspberry Pi Setup Script Additions ==="

    if grep -qF "$marker" "$bashrc" 2>/dev/null; then
        log_skip ".bashrc already configured"
        return
    fi

    cat >> "$bashrc" << 'BASHRC_EOF'

# === Raspberry Pi Setup Script Additions ===
if [ -f /usr/share/powerline/bindings/bash/powerline.sh ]; then
  source /usr/share/powerline/bindings/bash/powerline.sh
fi
export GRADLE_HOME=$HOME/gradle
export PATH=$PATH:$HOME/gradle/bin:$HOME/bin:$HOME/.local/bin
# === End Raspberry Pi Setup Script Additions ===
BASHRC_EOF

    chown "$TARGET_USER:$TARGET_USER" "$bashrc"

    log_success ".bashrc configured"
}

# =============================================================================
# TASK: INSTALL GITCONFIG
# =============================================================================

task_install_gitconfig() {
    log_task "Installing .gitconfig"

    local gitconfig="$TARGET_HOME/.gitconfig"

    if [[ -f "$gitconfig" ]]; then
        log_skip ".gitconfig already exists"
        return
    fi

    cat > "$gitconfig" << 'GITCONFIG_EOF'
[user]
	name = Manny Peterson
	email = 12462046+MannyPeterson@users.noreply.github.com
[core]
	eol = lf
[init]
	defaultBranch = master
[pull]
	rebase = false
[credential "https://github.com"]
	helper =
	helper = !/usr/bin/gh auth git-credential
GITCONFIG_EOF

    chown "$TARGET_USER:$TARGET_USER" "$gitconfig"

    log_success ".gitconfig installed"
}

# =============================================================================
# TASK: INSTALL SERVICE MANAGER
# =============================================================================

task_install_service_manager() {
    log_task "Installing Service Manager (sm)"

    local bin_dir="$TARGET_HOME/bin"
    local sm_script="$bin_dir/sm"

    # Create bin directory
    if check_idempotent dir_exists "$bin_dir"; then
        mkdir -p "$bin_dir"
        chown "$TARGET_USER:$TARGET_USER" "$bin_dir"
    fi

    # Write the service manager script
    cat > "$sm_script" << 'SM_EOF'
#!/bin/bash
#
# Service Manager Script
# Easily start, stop, and check status of various services
#
# Usage: sm [--verbose] <service> <action>
#        sm list
#        sm help
#

set -euo pipefail

# =============================================================================
# GLOBAL CONFIGURATION
# =============================================================================

VERBOSE=false
POSTGRES_PASSWORD="changeme"
POSTGRES_CONTAINER="postgres"
GRADLE_HOME="$HOME/gradle"

# Service registry (associative arrays)
declare -A SERVICE_DISPLAY_NAMES
declare -A SERVICE_START_CMDS
declare -A SERVICE_STOP_CMDS
declare -A SERVICE_STATUS_CMDS
declare -A SERVICE_INFO_FUNCS
declare -A SERVICE_CUSTOM_FUNCS

# =============================================================================
# STANDARDIZED OUTPUT FUNCTIONS
# =============================================================================

log_action() {
    echo "⟳ $1..."
}

log_success() {
    echo "✓ $1"
}

log_error() {
    echo "✗ $1" >&2
}

log_status_running() {
    echo "● $1: running"
}

log_status_stopped() {
    echo "○ $1: stopped"
}

log_status_not_found() {
    echo "○ $1: not found"
}

indent_output() {
    sed 's/^/  /'
}

# =============================================================================
# COMMAND EXECUTION WITH STANDARDIZED OUTPUT
# =============================================================================

execute_command() {
    local action=$1
    local service=$2
    local cmd=$3

    if [[ "$VERBOSE" == "true" ]]; then
        # Verbose mode: show all output
        eval "$cmd"
        return $?
    else
        # Normal mode: capture and suppress output
        local output
        if output=$(eval "$cmd" 2>&1); then
            return 0
        else
            # On error, show the captured output (if any)
            if [[ -n "$output" ]]; then
                echo "$output" | indent_output
            fi
            return 1
        fi
    fi
}

# =============================================================================
# SERVICE REGISTRATION HELPER
# =============================================================================

register_service() {
    local name=$1
    local display_name=$2
    shift 2

    SERVICE_DISPLAY_NAMES[$name]=$display_name

    # Parse remaining arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            start_cmd=*)
                SERVICE_START_CMDS[$name]="${1#*=}"
                ;;
            stop_cmd=*)
                SERVICE_STOP_CMDS[$name]="${1#*=}"
                ;;
            status_cmd=*)
                SERVICE_STATUS_CMDS[$name]="${1#*=}"
                ;;
            info_func=*)
                SERVICE_INFO_FUNCS[$name]="${1#*=}"
                ;;
            custom_func=*)
                SERVICE_CUSTOM_FUNCS[$name]="${1#*=}"
                ;;
        esac
        shift
    done
}

# =============================================================================
# SERVICE DEFINITIONS
# Add new services using register_service() - it's that simple!
# =============================================================================

# Custom function for PostgreSQL info
_postgres_info() {
    echo "Connection Details:"
    echo "  Host: localhost"
    echo "  Port: 5432"
    echo "  User: postgres"
    echo "  Password: $POSTGRES_PASSWORD"
    echo "  Database: postgres"
    echo ""
    echo "Connection String:"
    echo "  postgresql://postgres:${POSTGRES_PASSWORD}@localhost:5432/postgres"
}

# Custom function for PostgreSQL psql
_postgres_psql() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${POSTGRES_CONTAINER}$" 2>/dev/null; then
        log_error "PostgreSQL container is not running"
        echo "Run 'sm postgres start' first"
        exit 1
    fi

    if [[ $# -gt 0 ]]; then
        docker exec "$POSTGRES_CONTAINER" psql -U postgres "$@"
    else
        echo "Connecting to PostgreSQL..."
        docker exec -it "$POSTGRES_CONTAINER" psql -U postgres
    fi
}

# --- Register PostgreSQL Service ---
register_service "postgres" "PostgreSQL" \
    start_cmd="if docker ps -a --format '{{.Names}}' | grep -q '^${POSTGRES_CONTAINER}\$'; then docker start '$POSTGRES_CONTAINER'; else docker run -d --name '$POSTGRES_CONTAINER' -e POSTGRES_PASSWORD='$POSTGRES_PASSWORD' -p 5432:5432 postgres:latest; fi" \
    stop_cmd="docker stop '$POSTGRES_CONTAINER'" \
    status_cmd="docker ps -q -f name='^${POSTGRES_CONTAINER}\$' | grep ." \
    info_func="_postgres_info" \
    custom_func="_postgres_psql"

# --- Register Gradle Service ---
register_service "gradle" "Gradle Daemon" \
    start_cmd="'$GRADLE_HOME/bin/gradle' --daemon --quiet" \
    stop_cmd="'$GRADLE_HOME/bin/gradle' --stop" \
    status_cmd="'$GRADLE_HOME/bin/gradle' --status | grep -q 'IDLE\|BUSY'"

# =============================================================================
# TEMPLATE FOR NEW SERVICES
# =============================================================================
#
# Adding a new service is as simple as calling register_service():
#
# register_service "myservice" "My Service" \
#     start_cmd="systemctl start myservice" \
#     stop_cmd="systemctl stop myservice" \
#     status_cmd="systemctl is-active myservice"
#
# Optional: Add custom functions for 'info' or special actions:
#
# _myservice_info() {
#     echo "Service details here"
# }
#
# register_service "myservice" "My Service" \
#     start_cmd="..." \
#     stop_cmd="..." \
#     status_cmd="..." \
#     info_func="_myservice_info"
#

# =============================================================================
# CORE FUNCTIONS (Do not modify unless adding new actions)
# =============================================================================

list_services() {
    echo "Available services:"
    for service in "${!SERVICE_DISPLAY_NAMES[@]}"; do
        echo "  - $service (${SERVICE_DISPLAY_NAMES[$service]})"
    done | sort
}

show_help() {
    cat << 'EOF'
Service Manager (sm) - Control your services easily

USAGE:
    sm [--verbose] <service> <action>
    sm <command>

OPTIONS:
    --verbose, -v   Show detailed output from service commands (useful for debugging)

ACTIONS:
    start       Start the specified service
    stop        Stop the specified service
    status      Check the status of the specified service
    info        Show connection details (service-specific)
    psql        Connect to database via psql client (postgres only)

COMMANDS:
    list        List all available services
    help        Show this help message

EXAMPLES:
    sm postgres start
    sm postgres status
    sm --verbose postgres start   # Show full docker output
    sm postgres info              # Show connection details
    sm postgres psql              # Start interactive psql session
    sm gradle stop
    sm list

ADDING NEW SERVICES:
    Simply add a register_service() call in the SERVICE DEFINITIONS section:

    register_service "myservice" "My Service" \
        start_cmd="systemctl start myservice" \
        stop_cmd="systemctl stop myservice" \
        status_cmd="systemctl is-active myservice"

EOF
}

run_action() {
    local service="$1"
    local action="$2"
    shift 2  # Remove service and action from args

    # Check if service exists
    if [[ -z "${SERVICE_DISPLAY_NAMES[$service]:-}" ]]; then
        log_error "Unknown service '$service'"
        echo "Run 'sm list' to see available services"
        exit 1
    fi

    local display_name="${SERVICE_DISPLAY_NAMES[$service]}"

    case "$action" in
        start)
            if [[ -z "${SERVICE_START_CMDS[$service]:-}" ]]; then
                log_error "Start action not supported for $service"
                exit 1
            fi

            log_action "Starting $display_name"
            if execute_command "start" "$service" "${SERVICE_START_CMDS[$service]}"; then
                log_success "$display_name started successfully"
            else
                log_error "Failed to start $display_name"
                exit 1
            fi
            ;;

        stop)
            if [[ -z "${SERVICE_STOP_CMDS[$service]:-}" ]]; then
                log_error "Stop action not supported for $service"
                exit 1
            fi

            log_action "Stopping $display_name"
            if execute_command "stop" "$service" "${SERVICE_STOP_CMDS[$service]}"; then
                log_success "$display_name stopped successfully"
            else
                log_error "Failed to stop $display_name"
                exit 1
            fi
            ;;

        status)
            if [[ -z "${SERVICE_STATUS_CMDS[$service]:-}" ]]; then
                log_error "Status action not supported for $service"
                exit 1
            fi

            if execute_command "status" "$service" "${SERVICE_STATUS_CMDS[$service]}"; then
                log_status_running "$display_name"
            else
                log_status_stopped "$display_name"
            fi
            ;;

        info)
            if [[ -n "${SERVICE_INFO_FUNCS[$service]:-}" ]]; then
                echo "$display_name Information:"
                ${SERVICE_INFO_FUNCS[$service]}
            else
                log_error "Info action not supported for $service"
                exit 1
            fi
            ;;

        psql)
            # Special case for postgres psql command
            if [[ "$service" == "postgres" && -n "${SERVICE_CUSTOM_FUNCS[$service]:-}" ]]; then
                ${SERVICE_CUSTOM_FUNCS[$service]} "$@"
            else
                log_error "Action '$action' not supported for $service"
                exit 1
            fi
            ;;

        *)
            log_error "Invalid action '$action'"
            echo "Valid actions: start, stop, status, info, psql"
            exit 1
            ;;
    esac
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    # Parse --verbose flag
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    case "$1" in
        list)
            list_services
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            if [[ $# -lt 2 ]]; then
                log_error "Missing action"
                echo "Usage: sm [--verbose] <service> <action>"
                echo "Run 'sm help' for more information"
                exit 1
            fi

            local service="$1"
            local action="$2"
            shift 2  # Remove service and action, keep remaining args

            # Validate action
            case "$action" in
                start|stop|status|info|psql)
                    run_action "$service" "$action" "$@"
                    ;;
                *)
                    log_error "Invalid action '$action'"
                    echo "Valid actions: start, stop, status, info, psql"
                    exit 1
                    ;;
            esac
            ;;
    esac
}

main "$@"
SM_EOF

    chown "$TARGET_USER:$TARGET_USER" "$sm_script"
    chmod 770 "$sm_script"

    log_success "Service Manager installed to $sm_script"
}

# =============================================================================
# TASK: INSTALL DOCKER
# =============================================================================

task_install_docker() {
    log_task "Installing Docker"

    if command -v docker &>/dev/null; then
        log_skip "Docker already installed"
    else
        log_info "Downloading Docker installation script..."
        curl -fsSL https://get.docker.com -o /tmp/install-docker.sh

        log_info "Running Docker installation..."
        sh /tmp/install-docker.sh

        rm -f /tmp/install-docker.sh
        log_success "Docker installed"
    fi

    # Add user to docker group
    if check_idempotent user_in_group "$TARGET_USER" "docker"; then
        usermod -aG docker "$TARGET_USER"
        log_success "Added $TARGET_USER to docker group"
    else
        log_info "$TARGET_USER already in docker group"
    fi

    # Enable Docker service
    systemctl enable docker
    systemctl start docker

    log_success "Docker configured"
}

# =============================================================================
# TASK: INSTALL GRADLE
# =============================================================================

task_install_gradle() {
    log_task "Installing Gradle"

    local gradle_dir="$TARGET_HOME/gradle"
    local gradle_bin="$gradle_dir/bin/gradle"

    # Get latest version from API
    log_info "Fetching latest Gradle version..."
    local gradle_json
    gradle_json=$(curl -s https://services.gradle.org/versions/current)

    local gradle_version
    gradle_version=$(echo "$gradle_json" | jq -r '.version')

    local gradle_url
    gradle_url=$(echo "$gradle_json" | jq -r '.downloadUrl')

    log_info "Latest Gradle version: $gradle_version"

    # Check if already installed at correct version
    if [[ -x "$gradle_bin" ]]; then
        local installed_version
        installed_version=$("$gradle_bin" --version 2>/dev/null | grep "^Gradle" | awk '{print $2}' || echo "")
        if [[ "$installed_version" == "$gradle_version" ]]; then
            log_skip "Gradle $gradle_version already installed"
            return
        fi
        log_info "Upgrading Gradle from $installed_version to $gradle_version"
    fi

    # Download Gradle
    log_info "Downloading Gradle $gradle_version..."
    curl -sL "$gradle_url" -o /tmp/gradle.zip

    # Remove old installation if exists
    if [[ -d "$gradle_dir" ]]; then
        rm -rf "$gradle_dir"
    fi

    # Extract
    log_info "Extracting Gradle..."
    mkdir -p "$gradle_dir"
    unzip -q /tmp/gradle.zip -d /tmp

    # Move contents to gradle directory
    mv /tmp/gradle-${gradle_version}/* "$gradle_dir/"

    # Cleanup
    rm -rf /tmp/gradle.zip /tmp/gradle-${gradle_version}

    # Set ownership
    chown -R "$TARGET_USER:$TARGET_USER" "$gradle_dir"

    log_success "Gradle $gradle_version installed to $gradle_dir"
}

# =============================================================================
# TASK: INSTALL CLAUDE CODE
# =============================================================================

task_install_claude_code() {
    log_task "Installing Claude Code"

    if command -v claude &>/dev/null; then
        log_skip "Claude Code already installed"
        return
    fi

    log_info "Downloading and installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | sudo -u "$TARGET_USER" bash

    log_success "Claude Code installed"
}

# =============================================================================
# TASK: SETUP POSTGRESQL
# =============================================================================

task_setup_postgresql() {
    log_task "Setting up PostgreSQL Docker container"

    # Pull the image
    log_info "Pulling postgres:latest image..."
    docker pull postgres:latest

    # Check if container exists
    if docker ps -a --format '{{.Names}}' | grep -q "^postgres$"; then
        log_info "PostgreSQL container already exists"
        # Start if not running
        if ! docker ps --format '{{.Names}}' | grep -q "^postgres$"; then
            docker start postgres
            log_info "Started existing PostgreSQL container"
        fi
    else
        # Create and start container
        log_info "Creating PostgreSQL container..."
        docker run -d \
            --name postgres \
            -e POSTGRES_PASSWORD=changeme \
            -p 5432:5432 \
            postgres:latest
    fi

    # Wait for container to be ready
    log_info "Waiting for PostgreSQL to be ready..."
    sleep 5

    log_success "PostgreSQL container running"
}

# =============================================================================
# TASK: VERIFY SERVICE MANAGER
# =============================================================================

task_verify_service_manager() {
    log_task "Verifying Service Manager"

    local sm_script="$TARGET_HOME/bin/sm"

    # Test postgres status
    log_info "Testing 'sm postgres status'..."
    if sudo -u "$TARGET_USER" "$sm_script" postgres status; then
        log_success "PostgreSQL status check works"
    else
        log_warning "PostgreSQL status check returned stopped (may be expected)"
    fi

    # Test gradle status
    log_info "Testing 'sm gradle status'..."
    if sudo -u "$TARGET_USER" "$sm_script" gradle status 2>/dev/null; then
        log_success "Gradle status check works"
    else
        log_info "Gradle daemon not running (expected)"
    fi

    log_success "Service Manager verified"
}

# =============================================================================
# TASK: FINAL CLEANUP
# =============================================================================

task_final_cleanup() {
    log_task "Final cleanup"

    log_info "Running apt autoremove..."
    apt autoremove -y

    log_info "Running apt clean..."
    apt clean

    log_success "Cleanup complete"
}

# =============================================================================
# SUMMARY REPORT
# =============================================================================

show_summary() {
    log_header "CONFIGURATION COMPLETE"

    echo ""
    echo "System Information:"
    echo "  Hostname:     $(hostname)"
    echo "  IP Address:   $(hostname -I | awk '{print $1}')"
    echo "  OS:           $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
    echo "  Kernel:       $(uname -r)"
    echo "  Architecture: $(uname -m)"
    echo ""
    echo "  Disk Usage:   $(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 " used)"}')"
    echo "  Memory:       $(free -h | awk 'NR==2 {print $2 " total, " $7 " available"}')"
    echo ""
    echo "Installed Software:"
    echo "  Docker:       $(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo 'Not found')"
    echo "  Gradle:       $("$TARGET_HOME/gradle/bin/gradle" --version 2>/dev/null | grep "^Gradle" | awk '{print $2}' || echo 'Not found')"
    echo "  Java:         $(java --version 2>/dev/null | head -1 || echo 'Not found')"
    echo "  Claude Code:  $(command -v claude &>/dev/null && echo 'Installed' || echo 'Not found')"
    echo ""
    echo "Configuration:"
    echo "  Locale:       $LOCALE"
    echo "  Timezone:     $TIMEZONE"
    echo "  SSH:          Key-only authentication enabled"
    echo "  Sudo:         Password required"
    echo ""
    echo "Tasks Completed: $TASKS_COMPLETED/$TASKS_TOTAL"
    echo ""

    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        echo "Warnings:"
        for warning in "${WARNINGS[@]}"; do
            echo "  - $warning"
        done
        echo ""
    fi

    echo "Next Steps:"
    echo "  1. Log out and log back in for group changes to take effect"
    echo "  2. Reboot to apply GPU memory and kernel changes"
    echo "  3. Run 'sm list' to see available services"
    echo ""
    echo "============================================================================="
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    log_header "Raspberry Pi OS Lite Configuration Script"

    parse_arguments "$@"
    preflight_checks

    task_system_update
    task_set_locale
    task_set_timezone
    task_set_hostname
    task_set_gpu_memory
    task_set_wifi_country
    task_disable_interfaces
    task_install_packages
    task_configure_ssh
    task_configure_sudo
    task_configure_bashrc
    task_install_gitconfig
    task_install_service_manager
    task_install_docker
    task_install_gradle
    task_install_claude_code
    task_setup_postgresql
    task_verify_service_manager
    task_final_cleanup

    show_summary
}

main "$@"
