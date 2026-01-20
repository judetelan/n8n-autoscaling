#!/bin/bash
#===============================================================================
#
#   n8n Autoscaling - Interactive VPS Installer
#   https://github.com/judetelan/n8n-autoscaling
#
#   A universal installer for any VPS with SSH access
#   Supports: Ubuntu, Debian, CentOS, RHEL, Fedora, Amazon Linux, Alpine
#
#===============================================================================

set -e

# Version
INSTALLER_VERSION="1.0.0"

# Installation directory
INSTALL_DIR="/opt/n8n-autoscaling"
BACKUP_DIR="/opt/n8n-backups"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Symbols
CHECK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"
ARROW="${CYAN}→${NC}"
INFO="${BLUE}ℹ${NC}"
WARN="${YELLOW}⚠${NC}"

#===============================================================================
# Helper Functions
#===============================================================================

print_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
    ███╗   ██╗ █████╗ ███╗   ██╗
    ████╗  ██║██╔══██╗████╗  ██║
    ██╔██╗ ██║╚█████╔╝██╔██╗ ██║    Autoscaling
    ██║╚██╗██║██╔══██╗██║╚██╗██║    Installer
    ██║ ╚████║╚█████╔╝██║ ╚████║    v${INSTALLER_VERSION}
    ╚═╝  ╚═══╝ ╚════╝ ╚═╝  ╚═══╝
EOF
    echo -e "${NC}"
    echo -e "    ${WHITE}Universal VPS Installation Script${NC}"
    echo -e "    ${BLUE}───────────────────────────────────${NC}"
    echo ""
}

print_step() {
    echo -e "\n${ARROW} ${BOLD}$1${NC}"
}

print_success() {
    echo -e "  ${CHECK} $1"
}

print_error() {
    echo -e "  ${CROSS} $1"
}

print_warning() {
    echo -e "  ${WARN} $1"
}

print_info() {
    echo -e "  ${INFO} $1"
}

# Spinner for long operations
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while ps -p $pid > /dev/null 2>&1; do
        for i in $(seq 0 9); do
            printf "\r  ${CYAN}${spinstr:$i:1}${NC} $2"
            sleep $delay
        done
    done
    printf "\r"
}

# Ask yes/no question
ask_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local answer

    if [[ "$default" == "y" ]]; then
        prompt="${prompt} [Y/n]: "
    else
        prompt="${prompt} [y/N]: "
    fi

    read -p "  $prompt" answer
    answer=${answer:-$default}

    [[ "$answer" =~ ^[Yy]$ ]]
}

# Ask for input with default
ask_input() {
    local prompt="$1"
    local default="$2"
    local answer

    if [[ -n "$default" ]]; then
        read -p "  ${prompt} [${default}]: " answer
        echo "${answer:-$default}"
    else
        read -p "  ${prompt}: " answer
        echo "$answer"
    fi
}

# Ask for password (hidden)
ask_password() {
    local prompt="$1"
    local password

    read -s -p "  ${prompt}: " password
    echo ""
    echo "$password"
}

# Generate random string
generate_random() {
    local length="${1:-32}"
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c "$length"
}

# Press any key to continue
press_any_key() {
    echo ""
    read -n 1 -s -r -p "  Press any key to continue..."
    echo ""
}

#===============================================================================
# System Detection
#===============================================================================

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        OS_NAME=$PRETTY_NAME
    elif [[ -f /etc/redhat-release ]]; then
        OS="rhel"
        OS_NAME=$(cat /etc/redhat-release)
    else
        OS="unknown"
        OS_NAME="Unknown"
    fi

    # Detect package manager
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
    elif command -v apk &> /dev/null; then
        PKG_MANAGER="apk"
    else
        PKG_MANAGER="unknown"
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        echo -e "  Run with: ${CYAN}sudo $0${NC}"
        exit 1
    fi
}

check_system_requirements() {
    print_step "Checking system requirements"

    # Check memory
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    if [[ $TOTAL_MEM -ge 4000 ]]; then
        print_success "Memory: ${TOTAL_MEM}MB (recommended: 4GB+)"
    elif [[ $TOTAL_MEM -ge 2000 ]]; then
        print_warning "Memory: ${TOTAL_MEM}MB (minimum met, recommended: 4GB+)"
    else
        print_error "Memory: ${TOTAL_MEM}MB (minimum 2GB required)"
        exit 1
    fi

    # Check disk space
    DISK_AVAIL=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ $DISK_AVAIL -ge 20 ]]; then
        print_success "Disk space: ${DISK_AVAIL}GB available"
    else
        print_error "Disk space: ${DISK_AVAIL}GB (minimum 20GB required)"
        exit 1
    fi

    # Check architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]] || [[ "$ARCH" == "aarch64" ]]; then
        print_success "Architecture: $ARCH"
    else
        print_error "Architecture: $ARCH (unsupported)"
        exit 1
    fi

    print_success "OS: $OS_NAME"
}

#===============================================================================
# Installation Functions
#===============================================================================

install_dependencies() {
    print_step "Installing dependencies"

    case $PKG_MANAGER in
        apt)
            print_info "Updating package lists..."
            apt-get update -qq
            print_info "Installing packages..."
            apt-get install -y -qq \
                curl wget git nano htop \
                apt-transport-https ca-certificates \
                gnupg lsb-release ufw fail2ban \
                openssl jq > /dev/null 2>&1
            ;;
        dnf)
            print_info "Installing packages..."
            dnf install -y -q \
                curl wget git nano htop \
                ca-certificates firewalld \
                openssl jq > /dev/null 2>&1
            ;;
        yum)
            print_info "Installing packages..."
            yum install -y -q \
                curl wget git nano htop \
                ca-certificates firewalld \
                openssl jq > /dev/null 2>&1
            ;;
        apk)
            print_info "Installing packages..."
            apk add --no-cache \
                curl wget git nano htop \
                ca-certificates openssl jq bash > /dev/null 2>&1
            ;;
        *)
            print_warning "Unknown package manager - please install dependencies manually"
            ;;
    esac

    print_success "Dependencies installed"
}

install_docker() {
    print_step "Installing Docker"

    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')
        print_success "Docker already installed (v$DOCKER_VERSION)"
        return
    fi

    print_info "Downloading Docker installation script..."

    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh > /dev/null 2>&1 &
    spinner $! "Installing Docker..."

    # Enable and start Docker
    systemctl enable docker > /dev/null 2>&1
    systemctl start docker

    # Verify installation
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')
        print_success "Docker installed (v$DOCKER_VERSION)"
    else
        print_error "Docker installation failed"
        exit 1
    fi

    # Install Docker Compose plugin if not present
    if ! docker compose version &> /dev/null; then
        print_info "Installing Docker Compose plugin..."
        mkdir -p ~/.docker/cli-plugins/
        curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m) -o ~/.docker/cli-plugins/docker-compose
        chmod +x ~/.docker/cli-plugins/docker-compose
    fi

    print_success "Docker Compose available"

    rm -f /tmp/get-docker.sh
}

configure_firewall() {
    print_step "Configuring firewall"

    if command -v ufw &> /dev/null; then
        print_info "Configuring UFW firewall..."
        ufw default deny incoming > /dev/null 2>&1
        ufw default allow outgoing > /dev/null 2>&1
        ufw allow ssh > /dev/null 2>&1
        ufw allow 80/tcp > /dev/null 2>&1
        ufw allow 443/tcp > /dev/null 2>&1
        ufw allow 5678/tcp > /dev/null 2>&1  # n8n
        echo "y" | ufw enable > /dev/null 2>&1
        print_success "UFW firewall configured"
    elif command -v firewall-cmd &> /dev/null; then
        print_info "Configuring firewalld..."
        firewall-cmd --permanent --add-service=ssh > /dev/null 2>&1
        firewall-cmd --permanent --add-service=http > /dev/null 2>&1
        firewall-cmd --permanent --add-service=https > /dev/null 2>&1
        firewall-cmd --permanent --add-port=5678/tcp > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
        print_success "Firewalld configured"
    else
        print_warning "No firewall detected - please configure manually"
    fi
}

#===============================================================================
# n8n Configuration Wizard
#===============================================================================

configuration_wizard() {
    print_banner
    echo -e "  ${BOLD}Configuration Wizard${NC}"
    echo -e "  ${BLUE}───────────────────────────────────${NC}"
    echo ""
    echo -e "  Please provide the following configuration details."
    echo -e "  Press ${CYAN}Enter${NC} to accept default values."
    echo ""

    # Domain configuration
    echo -e "\n  ${BOLD}1. Domain Configuration${NC}"
    echo -e "  ${BLUE}─────────────────────────${NC}"

    USE_DOMAIN=$(ask_yes_no "Do you have a domain name?" "n")

    if $USE_DOMAIN; then
        N8N_DOMAIN=$(ask_input "Enter your n8n domain (e.g., n8n.example.com)")
        WEBHOOK_DOMAIN=$(ask_input "Enter webhook domain" "$N8N_DOMAIN")
        N8N_PROTOCOL="https"
    else
        SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "localhost")
        N8N_DOMAIN="$SERVER_IP"
        WEBHOOK_DOMAIN="$SERVER_IP"
        N8N_PROTOCOL="http"
        print_info "Will use IP address: $SERVER_IP"
    fi

    # Cloudflare Tunnel
    echo -e "\n  ${BOLD}2. Cloudflare Tunnel (Optional)${NC}"
    echo -e "  ${BLUE}─────────────────────────────────${NC}"

    USE_CLOUDFLARE=$(ask_yes_no "Do you want to use Cloudflare Tunnel for HTTPS?" "n")

    if $USE_CLOUDFLARE; then
        CLOUDFLARE_TOKEN=$(ask_input "Enter your Cloudflare Tunnel token")
    else
        CLOUDFLARE_TOKEN=""
    fi

    # Database configuration
    echo -e "\n  ${BOLD}3. Database Configuration${NC}"
    echo -e "  ${BLUE}──────────────────────────${NC}"

    POSTGRES_USER=$(ask_input "PostgreSQL username" "postgres")
    POSTGRES_DB=$(ask_input "PostgreSQL database name" "n8n")

    USE_RANDOM_PASSWORD=$(ask_yes_no "Generate random database password?" "y")
    if $USE_RANDOM_PASSWORD; then
        POSTGRES_PASSWORD=$(generate_random 24)
        print_info "Generated password: ${POSTGRES_PASSWORD:0:8}****"
    else
        POSTGRES_PASSWORD=$(ask_password "Enter PostgreSQL password")
    fi

    # Autoscaling configuration
    echo -e "\n  ${BOLD}4. Autoscaling Configuration${NC}"
    echo -e "  ${BLUE}──────────────────────────────${NC}"

    MIN_REPLICAS=$(ask_input "Minimum workers (always running)" "1")
    MAX_REPLICAS=$(ask_input "Maximum workers (scale limit)" "5")
    SCALE_UP_THRESHOLD=$(ask_input "Scale up when queue exceeds" "5")
    SCALE_DOWN_THRESHOLD=$(ask_input "Scale down when queue below" "1")

    # Timezone
    echo -e "\n  ${BOLD}5. General Settings${NC}"
    echo -e "  ${BLUE}─────────────────────${NC}"

    TIMEZONE=$(ask_input "Timezone" "UTC")

    # Generate security keys
    N8N_ENCRYPTION_KEY=$(generate_random 32)
    N8N_JWT_SECRET=$(generate_random 32)
    N8N_RUNNERS_TOKEN=$(generate_random 32)

    # Tailscale (optional)
    echo -e "\n  ${BOLD}6. Tailscale (Optional)${NC}"
    echo -e "  ${BLUE}─────────────────────────${NC}"

    USE_TAILSCALE=$(ask_yes_no "Bind to Tailscale IP for private access?" "n")
    if $USE_TAILSCALE; then
        TAILSCALE_IP=$(ask_input "Enter your Tailscale IP")
    else
        TAILSCALE_IP=""
    fi

    # Confirmation
    echo -e "\n  ${BOLD}Configuration Summary${NC}"
    echo -e "  ${BLUE}──────────────────────${NC}"
    echo -e "  Domain:          ${CYAN}$N8N_DOMAIN${NC}"
    echo -e "  Protocol:        ${CYAN}$N8N_PROTOCOL${NC}"
    echo -e "  Database:        ${CYAN}$POSTGRES_DB${NC}"
    echo -e "  Min Workers:     ${CYAN}$MIN_REPLICAS${NC}"
    echo -e "  Max Workers:     ${CYAN}$MAX_REPLICAS${NC}"
    echo -e "  Cloudflare:      ${CYAN}$([ -n "$CLOUDFLARE_TOKEN" ] && echo "Yes" || echo "No")${NC}"
    echo -e "  Tailscale:       ${CYAN}$([ -n "$TAILSCALE_IP" ] && echo "$TAILSCALE_IP" || echo "No")${NC}"
    echo ""

    if ! ask_yes_no "Proceed with this configuration?" "y"; then
        echo ""
        print_warning "Configuration cancelled"
        exit 0
    fi
}

#===============================================================================
# Installation Process
#===============================================================================

clone_repository() {
    print_step "Setting up n8n-autoscaling"

    if [[ -d "$INSTALL_DIR" ]]; then
        if ask_yes_no "Existing installation found. Backup and reinstall?" "y"; then
            BACKUP_NAME="n8n-backup-$(date +%Y%m%d-%H%M%S)"
            print_info "Backing up to ${BACKUP_DIR}/${BACKUP_NAME}"
            mkdir -p "$BACKUP_DIR"

            # Backup .env and data
            if [[ -f "$INSTALL_DIR/.env" ]]; then
                cp "$INSTALL_DIR/.env" "${BACKUP_DIR}/${BACKUP_NAME}.env"
            fi

            mv "$INSTALL_DIR" "${BACKUP_DIR}/${BACKUP_NAME}"
            print_success "Backup created"
        else
            print_info "Using existing installation"
            return
        fi
    fi

    print_info "Cloning repository..."
    git clone --depth 1 https://github.com/judetelan/n8n-autoscaling.git "$INSTALL_DIR" > /dev/null 2>&1
    print_success "Repository cloned to $INSTALL_DIR"
}

create_env_file() {
    print_step "Creating environment configuration"

    cat > "$INSTALL_DIR/.env" << EOF
#===============================================================================
# n8n Autoscaling Configuration
# Generated: $(date)
# Installer Version: $INSTALLER_VERSION
#===============================================================================

## Autoscaling
COMPOSE_PROJECT_NAME=n8n-autoscaling
LOG_LEVEL=INFO
COMPOSE_FILE_PATH=/app/docker-compose.yml
GENERIC_TIMEZONE=${TIMEZONE}
MIN_REPLICAS=${MIN_REPLICAS}
MAX_REPLICAS=${MAX_REPLICAS}
SCALE_UP_QUEUE_THRESHOLD=${SCALE_UP_THRESHOLD}
SCALE_DOWN_QUEUE_THRESHOLD=${SCALE_DOWN_THRESHOLD}
POLLING_INTERVAL_SECONDS=10
COOLDOWN_PERIOD_SECONDS=60
POLL_INTERVAL_SECONDS=5
N8N_QUEUE_BULL_GRACEFULSHUTDOWNTIMEOUT=300
N8N_GRACEFUL_SHUTDOWN_TIMEOUT=300

## Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=
QUEUE_NAME_PREFIX=bull
QUEUE_NAME=jobs
QUEUE_BULL_REDIS_HOST=redis
QUEUE_HEALTH_CHECK_ACTIVE=true

## Postgres
POSTGRES_HOST=postgres
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
PGDATA=/var/lib/postgresql/data/pgdata
DB_TYPE=postgresdb

## N8N
N8N_HOST=${N8N_DOMAIN}
N8N_WEBHOOK=${WEBHOOK_DOMAIN}
N8N_WEBHOOK_URL=${N8N_PROTOCOL}://${WEBHOOK_DOMAIN}
WEBHOOK_URL=${N8N_PROTOCOL}://${WEBHOOK_DOMAIN}
N8N_EDITOR_BASE_URL=${N8N_PROTOCOL}://${N8N_DOMAIN}
N8N_PROTOCOL=${N8N_PROTOCOL}
N8N_PORT=5678
N8N_DIAGNOSTICS_ENABLED=false
N8N_USER_FOLDER=/n8n/main
N8N_SECURE_COOKIE=false
N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=false
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_USER_MANAGEMENT_JWT_SECRET=${N8N_JWT_SECRET}
N8N_WORKER_SERVICE_NAME=n8n-worker
N8N_WORKER_RUNNER_SERVICE_NAME=n8n-worker-runner
EXECUTIONS_MODE=queue
OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true

## Task Runner config (n8n 2.0 - external mode)
N8N_RUNNERS_ENABLED=true
N8N_RUNNERS_MODE=external
N8N_RUNNERS_BROKER_LISTEN_ADDRESS=0.0.0.0
N8N_RUNNERS_AUTH_TOKEN=${N8N_RUNNERS_TOKEN}
N8N_RUNNERS_TASK_BROKER_URI=http://n8n:5679
N8N_RUNNERS_MAX_CONCURRENCY=5
N8N_RUNNERS_AUTO_SHUTDOWN_TIMEOUT=15

## Data limits
N8N_DATA_TABLES_MAX_SIZE_BYTES=1048576000
N8N_BLOCK_ENV_ACCESS_IN_NODE=false

## Cloudflare Tunnel
CLOUDFLARE_TUNNEL_TOKEN=${CLOUDFLARE_TOKEN}

## Tailscale (Optional)
TAILSCALE_IP=${TAILSCALE_IP}
EOF

    chmod 600 "$INSTALL_DIR/.env"
    print_success "Environment file created"
}

create_docker_network() {
    print_step "Creating Docker network"

    if docker network ls | grep -q "shark"; then
        print_info "Network 'shark' already exists"
    else
        docker network create shark > /dev/null 2>&1
        print_success "Docker network 'shark' created"
    fi
}

start_services() {
    print_step "Starting n8n services"

    cd "$INSTALL_DIR"

    print_info "Building containers (this may take a few minutes)..."
    docker compose build --no-cache > /dev/null 2>&1 &
    spinner $! "Building containers..."
    print_success "Containers built"

    print_info "Starting services..."
    docker compose up -d > /dev/null 2>&1
    print_success "Services started"

    # Wait for health checks
    print_info "Waiting for services to be healthy..."
    local max_wait=120
    local waited=0

    while [[ $waited -lt $max_wait ]]; do
        if docker compose ps 2>/dev/null | grep -q "healthy"; then
            break
        fi
        sleep 5
        waited=$((waited + 5))
        printf "\r  Waiting... (%ds/%ds)" $waited $max_wait
    done
    echo ""

    print_success "All services are running"
}

#===============================================================================
# Utility Scripts & Systemd
#===============================================================================

create_utility_scripts() {
    print_step "Creating management scripts"

    # n8n-ctl - Main control script
    cat > /usr/local/bin/n8n-ctl << 'EOFCTL'
#!/bin/bash
#===============================================================================
# n8n Control Script
#===============================================================================

INSTALL_DIR="/opt/n8n-autoscaling"
cd "$INSTALL_DIR" 2>/dev/null || { echo "n8n not installed at $INSTALL_DIR"; exit 1; }

case "$1" in
    status)
        echo "=== n8n Autoscaling Status ==="
        docker compose ps
        echo ""
        echo "=== Resource Usage ==="
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
        ;;
    logs)
        shift
        if [[ -n "$1" ]]; then
            docker compose logs -f --tail=100 "$@"
        else
            docker compose logs -f --tail=100
        fi
        ;;
    restart)
        echo "Restarting n8n services..."
        docker compose restart
        echo "Done"
        ;;
    stop)
        echo "Stopping n8n services..."
        docker compose down
        echo "Done"
        ;;
    start)
        echo "Starting n8n services..."
        docker compose up -d
        echo "Done"
        ;;
    update)
        echo "Updating n8n autoscaling..."
        git pull
        docker compose pull
        docker compose build --no-cache
        docker compose down
        docker compose up -d
        echo "Update complete"
        ;;
    backup)
        BACKUP_DIR="/opt/n8n-backups"
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        mkdir -p "$BACKUP_DIR"

        echo "Creating backup..."
        docker compose exec -T postgres pg_dump -U postgres n8n > "$BACKUP_DIR/db_$TIMESTAMP.sql"
        cp .env "$BACKUP_DIR/env_$TIMESTAMP"
        tar -czf "$BACKUP_DIR/n8n_backup_$TIMESTAMP.tar.gz" \
            -C "$BACKUP_DIR" "db_$TIMESTAMP.sql" "env_$TIMESTAMP"
        rm "$BACKUP_DIR/db_$TIMESTAMP.sql" "$BACKUP_DIR/env_$TIMESTAMP"

        # Keep last 7 backups
        ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm

        echo "Backup saved: $BACKUP_DIR/n8n_backup_$TIMESTAMP.tar.gz"
        ;;
    scale)
        if [[ -z "$2" ]]; then
            echo "Current workers:"
            docker compose ps n8n-worker --format "table {{.Name}}\t{{.Status}}"
        else
            echo "Scaling workers to $2..."
            docker compose up -d --scale n8n-worker="$2" --scale n8n-worker-runner="$2"
        fi
        ;;
    config)
        ${EDITOR:-nano} "$INSTALL_DIR/.env"
        ;;
    *)
        echo "n8n Autoscaling Control"
        echo ""
        echo "Usage: n8n-ctl <command>"
        echo ""
        echo "Commands:"
        echo "  status    Show service status and resource usage"
        echo "  logs      Show logs (optionally: logs <service>)"
        echo "  start     Start all services"
        echo "  stop      Stop all services"
        echo "  restart   Restart all services"
        echo "  update    Pull latest and rebuild"
        echo "  backup    Create database backup"
        echo "  scale N   Scale workers to N replicas"
        echo "  config    Edit configuration"
        echo ""
        ;;
esac
EOFCTL

    chmod +x /usr/local/bin/n8n-ctl

    # Create aliases
    ln -sf /usr/local/bin/n8n-ctl /usr/local/bin/n8n-status
    ln -sf /usr/local/bin/n8n-ctl /usr/local/bin/n8n-logs
    ln -sf /usr/local/bin/n8n-ctl /usr/local/bin/n8n-restart

    print_success "Control script created: n8n-ctl"
}

create_systemd_service() {
    print_step "Creating systemd service"

    cat > /etc/systemd/system/n8n-autoscaling.service << EOF
[Unit]
Description=n8n Autoscaling
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable n8n-autoscaling.service > /dev/null 2>&1

    print_success "Systemd service enabled (auto-start on boot)"
}

setup_backup_cron() {
    print_step "Setting up automated backups"

    # Daily backup at 2 AM
    (crontab -l 2>/dev/null | grep -v "n8n-ctl backup"; echo "0 2 * * * /usr/local/bin/n8n-ctl backup > /var/log/n8n-backup.log 2>&1") | crontab -

    print_success "Daily backup scheduled (2:00 AM)"
}

save_credentials() {
    print_step "Saving credentials"

    CREDS_FILE="$INSTALL_DIR/CREDENTIALS.txt"

    cat > "$CREDS_FILE" << EOF
================================================================================
n8n Autoscaling - Installation Credentials
Generated: $(date)
================================================================================

IMPORTANT: Save these credentials securely and DELETE this file!

Access URL:
  ${N8N_PROTOCOL}://${N8N_DOMAIN}:5678

Database:
  Host: postgres (internal)
  Database: ${POSTGRES_DB}
  User: ${POSTGRES_USER}
  Password: ${POSTGRES_PASSWORD}

Encryption Key:
  ${N8N_ENCRYPTION_KEY}

JWT Secret:
  ${N8N_JWT_SECRET}

Task Runner Token:
  ${N8N_RUNNERS_TOKEN}

$([ -n "$CLOUDFLARE_TOKEN" ] && echo "Cloudflare Token:
  ${CLOUDFLARE_TOKEN:0:20}...")

Installation Directory:
  ${INSTALL_DIR}

Management Commands:
  n8n-ctl status    - Check status
  n8n-ctl logs      - View logs
  n8n-ctl restart   - Restart services
  n8n-ctl backup    - Create backup
  n8n-ctl update    - Update to latest

================================================================================
EOF

    chmod 600 "$CREDS_FILE"
    print_success "Credentials saved to $CREDS_FILE"
    print_warning "Remember to delete this file after saving credentials!"
}

#===============================================================================
# Final Summary
#===============================================================================

print_summary() {
    local IP=$(curl -s ifconfig.me 2>/dev/null || echo "$N8N_DOMAIN")

    print_banner
    echo -e "  ${GREEN}${BOLD}Installation Complete!${NC}"
    echo -e "  ${BLUE}───────────────────────────────────${NC}"
    echo ""
    echo -e "  ${BOLD}Access n8n:${NC}"
    if [[ "$N8N_PROTOCOL" == "https" ]]; then
        echo -e "    ${CYAN}https://${N8N_DOMAIN}${NC}"
    else
        echo -e "    ${CYAN}http://${IP}:5678${NC}"
    fi
    echo ""
    echo -e "  ${BOLD}Management Commands:${NC}"
    echo -e "    ${WHITE}n8n-ctl status${NC}    - Check service status"
    echo -e "    ${WHITE}n8n-ctl logs${NC}      - View logs"
    echo -e "    ${WHITE}n8n-ctl restart${NC}   - Restart services"
    echo -e "    ${WHITE}n8n-ctl backup${NC}    - Create backup"
    echo -e "    ${WHITE}n8n-ctl update${NC}    - Update to latest"
    echo -e "    ${WHITE}n8n-ctl config${NC}    - Edit configuration"
    echo ""
    echo -e "  ${BOLD}Important Files:${NC}"
    echo -e "    Config:      ${CYAN}${INSTALL_DIR}/.env${NC}"
    echo -e "    Credentials: ${CYAN}${INSTALL_DIR}/CREDENTIALS.txt${NC}"
    echo -e "    Backups:     ${CYAN}${BACKUP_DIR}/${NC}"
    echo ""
    echo -e "  ${WARN} ${YELLOW}Save your credentials and delete CREDENTIALS.txt${NC}"
    echo ""
    echo -e "  ${BLUE}───────────────────────────────────${NC}"
    echo ""
}

#===============================================================================
# Main Menu
#===============================================================================

show_menu() {
    print_banner
    echo -e "  ${BOLD}What would you like to do?${NC}"
    echo ""
    echo -e "  ${WHITE}1)${NC} Fresh Install      - Complete new installation"
    echo -e "  ${WHITE}2)${NC} Update             - Update existing installation"
    echo -e "  ${WHITE}3)${NC} Reconfigure        - Change configuration"
    echo -e "  ${WHITE}4)${NC} Uninstall          - Remove n8n autoscaling"
    echo -e "  ${WHITE}5)${NC} Status             - Check current status"
    echo -e "  ${WHITE}q)${NC} Quit"
    echo ""
    read -p "  Select option [1-5/q]: " choice

    case $choice in
        1) fresh_install ;;
        2) update_install ;;
        3) reconfigure ;;
        4) uninstall ;;
        5) show_status ;;
        q|Q) exit 0 ;;
        *) show_menu ;;
    esac
}

fresh_install() {
    check_root
    detect_os
    check_system_requirements
    configuration_wizard
    install_dependencies
    install_docker
    configure_firewall
    clone_repository
    create_env_file
    create_docker_network
    start_services
    create_utility_scripts
    create_systemd_service
    setup_backup_cron
    save_credentials
    print_summary
}

update_install() {
    check_root
    print_step "Updating n8n autoscaling"

    if [[ ! -d "$INSTALL_DIR" ]]; then
        print_error "n8n not installed at $INSTALL_DIR"
        exit 1
    fi

    cd "$INSTALL_DIR"

    print_info "Pulling latest changes..."
    git pull

    print_info "Rebuilding containers..."
    docker compose pull
    docker compose build --no-cache

    print_info "Restarting services..."
    docker compose down
    docker compose up -d

    print_success "Update complete!"
}

reconfigure() {
    check_root

    if [[ ! -d "$INSTALL_DIR" ]]; then
        print_error "n8n not installed"
        exit 1
    fi

    configuration_wizard
    create_env_file

    print_info "Restarting services with new configuration..."
    cd "$INSTALL_DIR"
    docker compose down
    docker compose up -d

    print_success "Reconfiguration complete!"
}

uninstall() {
    check_root
    print_banner

    echo -e "  ${RED}${BOLD}WARNING: This will remove n8n autoscaling${NC}"
    echo ""

    if ! ask_yes_no "Are you sure you want to uninstall?" "n"; then
        echo ""
        print_info "Uninstall cancelled"
        exit 0
    fi

    if ask_yes_no "Create backup before uninstalling?" "y"; then
        /usr/local/bin/n8n-ctl backup 2>/dev/null || true
    fi

    print_step "Uninstalling n8n autoscaling"

    # Stop and remove containers
    if [[ -d "$INSTALL_DIR" ]]; then
        cd "$INSTALL_DIR"
        docker compose down -v 2>/dev/null || true
    fi

    # Remove installation
    rm -rf "$INSTALL_DIR"
    print_success "Installation removed"

    # Remove systemd service
    systemctl disable n8n-autoscaling 2>/dev/null || true
    rm -f /etc/systemd/system/n8n-autoscaling.service
    systemctl daemon-reload
    print_success "Systemd service removed"

    # Remove scripts
    rm -f /usr/local/bin/n8n-ctl
    rm -f /usr/local/bin/n8n-status
    rm -f /usr/local/bin/n8n-logs
    rm -f /usr/local/bin/n8n-restart
    print_success "Management scripts removed"

    # Remove cron
    crontab -l 2>/dev/null | grep -v "n8n-ctl" | crontab - 2>/dev/null || true
    print_success "Cron jobs removed"

    echo ""
    print_success "Uninstallation complete!"
    echo ""
    print_info "Backups preserved at: $BACKUP_DIR"
    print_info "Docker network 'shark' preserved (remove with: docker network rm shark)"
}

show_status() {
    if command -v n8n-ctl &> /dev/null; then
        n8n-ctl status
    else
        print_error "n8n not installed"
    fi
    press_any_key
    show_menu
}

#===============================================================================
# Entry Point
#===============================================================================

main() {
    # Check if running interactively or with arguments
    if [[ $# -gt 0 ]]; then
        case "$1" in
            --install|-i)
                fresh_install
                ;;
            --update|-u)
                update_install
                ;;
            --uninstall|-r)
                uninstall
                ;;
            --status|-s)
                show_status
                ;;
            --help|-h)
                echo "n8n Autoscaling Installer v${INSTALLER_VERSION}"
                echo ""
                echo "Usage: $0 [option]"
                echo ""
                echo "Options:"
                echo "  --install, -i    Fresh installation"
                echo "  --update, -u     Update existing installation"
                echo "  --uninstall, -r  Remove installation"
                echo "  --status, -s     Show status"
                echo "  --help, -h       Show this help"
                echo ""
                echo "Without options, runs interactive menu."
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    else
        show_menu
    fi
}

main "$@"
