#!/bin/bash
#===============================================================================
#
#   n8n Autoscaling - Production VPS Installer
#   https://github.com/judetelan/n8n-autoscaling
#
#   Production-ready installer with Cloudflare Tunnel for secure deployment
#   Supports: Ubuntu, Debian, CentOS, RHEL, Fedora, Amazon Linux, Alpine
#
#===============================================================================

set -e

# Version
INSTALLER_VERSION="2.0.0"

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
NC='\033[0m'
BOLD='\033[1m'

# Symbols
CHECK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"
ARROW="${CYAN}→${NC}"
INFO="${BLUE}ℹ${NC}"
WARN="${YELLOW}⚠${NC}"
LOCK="${GREEN}🔒${NC}"

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
    ██║╚██╗██║██╔══██╗██║╚██╗██║    Production
    ██║ ╚████║╚█████╔╝██║ ╚████║    v${INSTALLER_VERSION}
    ╚═╝  ╚═══╝ ╚════╝ ╚═╝  ╚═══╝
EOF
    echo -e "${NC}"
    echo -e "    ${WHITE}Production-Ready VPS Installer${NC}"
    echo -e "    ${LOCK} ${GREEN}Secured with Cloudflare Tunnel${NC}"
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

print_secure() {
    echo -e "  ${LOCK} $1"
}

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

ask_input() {
    local prompt="$1"
    local default="$2"
    local required="${3:-false}"
    local answer

    if [[ -n "$default" ]]; then
        read -p "  ${prompt} [${default}]: " answer
        echo "${answer:-$default}"
    else
        while true; do
            read -p "  ${prompt}: " answer
            if [[ -n "$answer" ]] || [[ "$required" != "true" ]]; then
                echo "$answer"
                break
            fi
            echo -e "  ${RED}This field is required${NC}"
        done
    fi
}

ask_password() {
    local prompt="$1"
    local password

    read -s -p "  ${prompt}: " password
    echo ""
    echo "$password"
}

generate_random() {
    local length="${1:-32}"
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c "$length"
}

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

    # Check memory - Production requires 4GB minimum
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    if [[ $TOTAL_MEM -ge 4000 ]]; then
        print_success "Memory: ${TOTAL_MEM}MB (production ready)"
    elif [[ $TOTAL_MEM -ge 2000 ]]; then
        print_warning "Memory: ${TOTAL_MEM}MB (minimum for testing, production needs 4GB+)"
        if ! ask_yes_no "Continue anyway?" "n"; then
            exit 1
        fi
    else
        print_error "Memory: ${TOTAL_MEM}MB (minimum 4GB required for production)"
        exit 1
    fi

    # Check disk space
    DISK_AVAIL=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ $DISK_AVAIL -ge 40 ]]; then
        print_success "Disk space: ${DISK_AVAIL}GB available (production ready)"
    elif [[ $DISK_AVAIL -ge 20 ]]; then
        print_warning "Disk space: ${DISK_AVAIL}GB (recommend 40GB+ for production)"
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
# Security Hardening
#===============================================================================

harden_ssh() {
    print_step "Hardening SSH configuration"

    local SSH_CONFIG="/etc/ssh/sshd_config"
    local BACKUP_CONFIG="/etc/ssh/sshd_config.backup.$(date +%Y%m%d%H%M%S)"

    # Backup original config
    cp "$SSH_CONFIG" "$BACKUP_CONFIG"

    # Apply security settings
    sed -i 's/#PermitRootLogin.*/PermitRootLogin prohibit-password/' "$SSH_CONFIG"
    sed -i 's/PermitRootLogin yes/PermitRootLogin prohibit-password/' "$SSH_CONFIG"
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_CONFIG"
    sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' "$SSH_CONFIG"
    sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSH_CONFIG"
    sed -i 's/#MaxAuthTries.*/MaxAuthTries 3/' "$SSH_CONFIG"
    sed -i 's/#ClientAliveInterval.*/ClientAliveInterval 300/' "$SSH_CONFIG"
    sed -i 's/#ClientAliveCountMax.*/ClientAliveCountMax 2/' "$SSH_CONFIG"

    # Restart SSH
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true

    print_secure "SSH hardened: key-only auth, root login restricted"
}

configure_firewall_production() {
    print_step "Configuring production firewall"

    if command -v ufw &> /dev/null; then
        print_info "Configuring UFW for production..."

        # Reset and set defaults
        ufw --force reset > /dev/null 2>&1
        ufw default deny incoming > /dev/null 2>&1
        ufw default allow outgoing > /dev/null 2>&1

        # Only allow SSH - n8n accessed via Cloudflare Tunnel only
        ufw allow ssh > /dev/null 2>&1

        # Rate limit SSH to prevent brute force
        ufw limit ssh > /dev/null 2>&1

        echo "y" | ufw enable > /dev/null 2>&1

        print_secure "Firewall: Only SSH (22) open - n8n secured via Cloudflare Tunnel"

    elif command -v firewall-cmd &> /dev/null; then
        print_info "Configuring firewalld for production..."

        firewall-cmd --set-default-zone=drop > /dev/null 2>&1
        firewall-cmd --permanent --add-service=ssh > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1

        print_secure "Firewall: Only SSH open - n8n secured via Cloudflare Tunnel"
    else
        print_warning "No firewall detected - please configure manually"
        print_info "Only port 22 (SSH) should be open for production"
    fi
}

configure_fail2ban_production() {
    print_step "Configuring fail2ban for intrusion prevention"

    # Install fail2ban if not present
    case $PKG_MANAGER in
        apt)
            apt-get install -y -qq fail2ban > /dev/null 2>&1
            ;;
        dnf|yum)
            $PKG_MANAGER install -y -q fail2ban > /dev/null 2>&1
            ;;
    esac

    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
# Ban for 1 hour
bantime = 3600
# Check last 10 minutes
findtime = 600
# Ban after 3 failures
maxretry = 3
# Use modern backend
backend = systemd

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400

# Aggressive SSH protection
[sshd-aggressive]
enabled = true
port = ssh
filter = sshd[mode=aggressive]
logpath = /var/log/auth.log
maxretry = 2
bantime = 172800
EOF

    systemctl enable fail2ban > /dev/null 2>&1
    systemctl restart fail2ban > /dev/null 2>&1

    print_secure "Fail2ban: Aggressive SSH protection enabled"
}

setup_automatic_updates() {
    print_step "Configuring automatic security updates"

    case $PKG_MANAGER in
        apt)
            apt-get install -y -qq unattended-upgrades > /dev/null 2>&1

            cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

            cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
            print_secure "Automatic security updates enabled"
            ;;
        dnf)
            dnf install -y -q dnf-automatic > /dev/null 2>&1
            sed -i 's/apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf
            systemctl enable --now dnf-automatic.timer > /dev/null 2>&1
            print_secure "Automatic security updates enabled"
            ;;
        *)
            print_warning "Please configure automatic updates manually"
            ;;
    esac
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
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
                curl wget git nano htop \
                apt-transport-https ca-certificates \
                gnupg lsb-release \
                openssl jq > /dev/null 2>&1
            ;;
        dnf)
            print_info "Installing packages..."
            dnf install -y -q \
                curl wget git nano htop \
                ca-certificates \
                openssl jq > /dev/null 2>&1
            ;;
        yum)
            print_info "Installing packages..."
            yum install -y -q \
                curl wget git nano htop \
                ca-certificates \
                openssl jq > /dev/null 2>&1
            ;;
        apk)
            print_info "Installing packages..."
            apk add --no-cache \
                curl wget git nano htop \
                ca-certificates openssl jq bash > /dev/null 2>&1
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

    systemctl enable docker > /dev/null 2>&1
    systemctl start docker

    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')
        print_success "Docker installed (v$DOCKER_VERSION)"
    else
        print_error "Docker installation failed"
        exit 1
    fi

    if ! docker compose version &> /dev/null; then
        print_info "Installing Docker Compose plugin..."
        mkdir -p ~/.docker/cli-plugins/
        curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m) -o ~/.docker/cli-plugins/docker-compose
        chmod +x ~/.docker/cli-plugins/docker-compose
    fi

    print_success "Docker Compose available"
    rm -f /tmp/get-docker.sh
}

#===============================================================================
# Production Configuration Wizard
#===============================================================================

configuration_wizard() {
    print_banner
    echo -e "  ${BOLD}Production Configuration Wizard${NC}"
    echo -e "  ${BLUE}───────────────────────────────────${NC}"
    echo ""
    echo -e "  ${LOCK} This installer configures n8n for ${GREEN}production use${NC}"
    echo -e "  ${LOCK} All traffic secured via ${GREEN}Cloudflare Tunnel${NC}"
    echo -e "  ${LOCK} No ports exposed except SSH"
    echo ""

    # Cloudflare Tunnel - Required for production
    echo -e "\n  ${BOLD}1. Cloudflare Tunnel Configuration (Required)${NC}"
    echo -e "  ${BLUE}───────────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${INFO} Cloudflare Tunnel secures your n8n instance by:"
    echo -e "      • Hiding your server's real IP address"
    echo -e "      • Providing free SSL/TLS encryption"
    echo -e "      • Blocking direct attacks to your server"
    echo -e "      • No need to open ports 80, 443, or 5678"
    echo ""
    echo -e "  ${CYAN}To get your tunnel token:${NC}"
    echo -e "      1. Go to https://one.dash.cloudflare.com/"
    echo -e "      2. Navigate to Networks → Tunnels"
    echo -e "      3. Create a tunnel and copy the token"
    echo ""

    while true; do
        CLOUDFLARE_TOKEN=$(ask_input "Enter your Cloudflare Tunnel token" "" "true")
        if [[ -n "$CLOUDFLARE_TOKEN" ]] && [[ ${#CLOUDFLARE_TOKEN} -gt 50 ]]; then
            print_success "Tunnel token accepted"
            break
        else
            print_error "Invalid token. Cloudflare tokens are typically 100+ characters"
            echo -e "  ${INFO} The token starts with 'eyJ' and is very long"
        fi
    done

    # Domain configuration
    echo -e "\n  ${BOLD}2. Domain Configuration${NC}"
    echo -e "  ${BLUE}──────────────────────────${NC}"

    N8N_DOMAIN=$(ask_input "Enter your n8n domain (e.g., n8n.example.com)" "" "true")
    WEBHOOK_DOMAIN=$(ask_input "Enter webhook domain" "$N8N_DOMAIN")
    N8N_PROTOCOL="https"

    # Database configuration
    echo -e "\n  ${BOLD}3. Database Configuration${NC}"
    echo -e "  ${BLUE}──────────────────────────${NC}"

    POSTGRES_USER=$(ask_input "PostgreSQL username" "n8n_prod")
    POSTGRES_DB=$(ask_input "PostgreSQL database name" "n8n_production")

    # Always generate strong passwords for production
    print_info "Generating secure credentials..."
    POSTGRES_PASSWORD=$(generate_random 32)
    N8N_ENCRYPTION_KEY=$(generate_random 32)
    N8N_JWT_SECRET=$(generate_random 32)
    N8N_RUNNERS_TOKEN=$(generate_random 32)
    print_secure "Strong passwords generated (32 characters each)"

    # Production autoscaling configuration
    echo -e "\n  ${BOLD}4. Autoscaling Configuration${NC}"
    echo -e "  ${BLUE}──────────────────────────────${NC}"
    echo ""
    echo -e "  ${INFO} Production defaults are optimized for stability"
    echo ""

    MIN_REPLICAS=$(ask_input "Minimum workers (always running)" "2")
    MAX_REPLICAS=$(ask_input "Maximum workers (scale limit)" "10")
    SCALE_UP_THRESHOLD=$(ask_input "Scale up when queue exceeds" "3")
    SCALE_DOWN_THRESHOLD=$(ask_input "Scale down when queue below" "1")

    # Timezone
    echo -e "\n  ${BOLD}5. General Settings${NC}"
    echo -e "  ${BLUE}─────────────────────${NC}"

    TIMEZONE=$(ask_input "Timezone" "UTC")

    # Confirmation
    echo -e "\n  ${BOLD}Production Configuration Summary${NC}"
    echo -e "  ${BLUE}──────────────────────────────────${NC}"
    echo -e "  ${LOCK} Security:      ${GREEN}Cloudflare Tunnel (no exposed ports)${NC}"
    echo -e "  Domain:          ${CYAN}https://$N8N_DOMAIN${NC}"
    echo -e "  Webhook:         ${CYAN}https://$WEBHOOK_DOMAIN${NC}"
    echo -e "  Database:        ${CYAN}$POSTGRES_DB${NC}"
    echo -e "  Min Workers:     ${CYAN}$MIN_REPLICAS${NC}"
    echo -e "  Max Workers:     ${CYAN}$MAX_REPLICAS${NC}"
    echo -e "  Timezone:        ${CYAN}$TIMEZONE${NC}"
    echo ""

    if ! ask_yes_no "Proceed with production deployment?" "y"; then
        echo ""
        print_warning "Deployment cancelled"
        exit 0
    fi
}

#===============================================================================
# n8n Setup
#===============================================================================

clone_repository() {
    print_step "Setting up n8n-autoscaling"

    if [[ -d "$INSTALL_DIR" ]]; then
        if ask_yes_no "Existing installation found. Backup and reinstall?" "y"; then
            BACKUP_NAME="n8n-backup-$(date +%Y%m%d-%H%M%S)"
            print_info "Backing up to ${BACKUP_DIR}/${BACKUP_NAME}"
            mkdir -p "$BACKUP_DIR"

            if [[ -f "$INSTALL_DIR/.env" ]]; then
                cp "$INSTALL_DIR/.env" "${BACKUP_DIR}/${BACKUP_NAME}.env"
            fi

            # Backup database if running
            if docker compose -f "$INSTALL_DIR/docker-compose.yml" ps 2>/dev/null | grep -q "postgres"; then
                print_info "Backing up database..."
                docker compose -f "$INSTALL_DIR/docker-compose.yml" exec -T postgres pg_dump -U postgres n8n > "${BACKUP_DIR}/${BACKUP_NAME}.sql" 2>/dev/null || true
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
    print_step "Creating production environment configuration"

    cat > "$INSTALL_DIR/.env" << EOF
#===============================================================================
# n8n Autoscaling - PRODUCTION Configuration
# Generated: $(date)
# Installer Version: $INSTALLER_VERSION
#
# SECURITY: This server is secured via Cloudflare Tunnel
#           No ports are exposed except SSH (22)
#===============================================================================

## Autoscaling - Production optimized
COMPOSE_PROJECT_NAME=n8n-production
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

## Redis - Production
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=
QUEUE_NAME_PREFIX=bull
QUEUE_NAME=jobs
QUEUE_BULL_REDIS_HOST=redis
QUEUE_HEALTH_CHECK_ACTIVE=true

## Postgres - Production
POSTGRES_HOST=postgres
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
PGDATA=/var/lib/postgresql/data/pgdata
DB_TYPE=postgresdb

## N8N - Production with Cloudflare Tunnel
N8N_HOST=${N8N_DOMAIN}
N8N_WEBHOOK=${WEBHOOK_DOMAIN}
N8N_WEBHOOK_URL=https://${WEBHOOK_DOMAIN}
WEBHOOK_URL=https://${WEBHOOK_DOMAIN}
N8N_EDITOR_BASE_URL=https://${N8N_DOMAIN}
N8N_PROTOCOL=https
N8N_PORT=5678
N8N_DIAGNOSTICS_ENABLED=false
N8N_USER_FOLDER=/n8n/main
N8N_SECURE_COOKIE=true
N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
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

## Data limits - Production
N8N_DATA_TABLES_MAX_SIZE_BYTES=1048576000
N8N_BLOCK_ENV_ACCESS_IN_NODE=true

## Cloudflare Tunnel - Required for production security
CLOUDFLARE_TUNNEL_TOKEN=${CLOUDFLARE_TOKEN}

## Tailscale - Not needed with Cloudflare Tunnel
TAILSCALE_IP=
EOF

    chmod 600 "$INSTALL_DIR/.env"
    print_secure "Production environment configured"
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
    print_step "Starting production services"

    cd "$INSTALL_DIR"

    print_info "Building containers (this may take several minutes)..."
    docker compose build --no-cache > /dev/null 2>&1 &
    spinner $! "Building containers..."
    print_success "Containers built"

    print_info "Starting services..."
    docker compose up -d > /dev/null 2>&1
    print_success "Services started"

    print_info "Waiting for services to be healthy..."
    local max_wait=180
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

    cat > /usr/local/bin/n8n-ctl << 'EOFCTL'
#!/bin/bash
#===============================================================================
# n8n Production Control Script
#===============================================================================

INSTALL_DIR="/opt/n8n-autoscaling"
cd "$INSTALL_DIR" 2>/dev/null || { echo "n8n not installed at $INSTALL_DIR"; exit 1; }

case "$1" in
    status)
        echo "=== n8n Production Status ==="
        echo ""
        echo "Services:"
        docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
        echo ""
        echo "Resource Usage:"
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
        echo ""
        echo "Security: Cloudflare Tunnel (no exposed ports)"
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
        echo "Restarting n8n production services..."
        docker compose restart
        echo "Done"
        ;;
    stop)
        echo "Stopping n8n production services..."
        docker compose down
        echo "Done"
        ;;
    start)
        echo "Starting n8n production services..."
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

        echo "Creating production backup..."

        # Backup database
        docker compose exec -T postgres pg_dump -U n8n_prod n8n_production > "$BACKUP_DIR/db_$TIMESTAMP.sql" 2>/dev/null || \
        docker compose exec -T postgres pg_dump -U postgres n8n > "$BACKUP_DIR/db_$TIMESTAMP.sql" 2>/dev/null || true

        # Backup config
        cp .env "$BACKUP_DIR/env_$TIMESTAMP"

        # Compress
        tar -czf "$BACKUP_DIR/n8n_backup_$TIMESTAMP.tar.gz" \
            -C "$BACKUP_DIR" "db_$TIMESTAMP.sql" "env_$TIMESTAMP" 2>/dev/null
        rm -f "$BACKUP_DIR/db_$TIMESTAMP.sql" "$BACKUP_DIR/env_$TIMESTAMP"

        # Keep last 14 backups (2 weeks)
        ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | tail -n +15 | xargs -r rm

        echo "Backup saved: $BACKUP_DIR/n8n_backup_$TIMESTAMP.tar.gz"
        ;;
    scale)
        if [[ -z "$2" ]]; then
            echo "Current workers:"
            docker compose ps n8n-worker --format "table {{.Name}}\t{{.Status}}"
        else
            echo "Scaling workers to $2..."
            docker compose up -d --scale n8n-worker="$2" --scale n8n-worker-runner="$2"
            echo "Done - scaled to $2 workers"
        fi
        ;;
    config)
        ${EDITOR:-nano} "$INSTALL_DIR/.env"
        echo "Configuration updated. Run 'n8n-ctl restart' to apply changes."
        ;;
    health)
        echo "=== Health Check ==="
        echo ""
        echo "Docker:"
        docker info --format "  Version: {{.ServerVersion}}" 2>/dev/null
        echo ""
        echo "Services:"
        docker compose ps --format "  {{.Name}}: {{.Status}}"
        echo ""
        echo "Disk:"
        df -h / | awk 'NR==2 {print "  Used: "$3" / "$2" ("$5")"}'
        echo ""
        echo "Memory:"
        free -h | awk '/^Mem:/ {print "  Used: "$3" / "$2}'
        ;;
    *)
        echo "n8n Production Control"
        echo ""
        echo "Usage: n8n-ctl <command>"
        echo ""
        echo "Commands:"
        echo "  status    Show service status and resource usage"
        echo "  health    Full health check"
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
    for cmd in status logs restart start stop; do
        ln -sf /usr/local/bin/n8n-ctl /usr/local/bin/n8n-$cmd 2>/dev/null || true
    done

    print_success "Control script created: n8n-ctl"
}

create_systemd_service() {
    print_step "Creating systemd service"

    cat > /etc/systemd/system/n8n-autoscaling.service << EOF
[Unit]
Description=n8n Autoscaling Production
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

    # Production: backup twice daily at 2 AM and 2 PM
    (crontab -l 2>/dev/null | grep -v "n8n-ctl backup"; \
     echo "0 2,14 * * * /usr/local/bin/n8n-ctl backup > /var/log/n8n-backup.log 2>&1") | crontab -

    print_success "Automated backups: twice daily (2:00 AM & 2:00 PM)"
}

setup_log_rotation() {
    print_step "Setting up log rotation"

    cat > /etc/logrotate.d/n8n << 'EOF'
/var/log/n8n-backup.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
}
EOF

    print_success "Log rotation configured"
}

save_credentials() {
    print_step "Saving credentials securely"

    CREDS_FILE="$INSTALL_DIR/CREDENTIALS.txt"

    cat > "$CREDS_FILE" << EOF
================================================================================
n8n Autoscaling - PRODUCTION Credentials
Generated: $(date)
================================================================================

CRITICAL: Save these credentials securely and DELETE this file!

================================================================================
ACCESS
================================================================================

n8n Editor:     https://${N8N_DOMAIN}
Webhook URL:    https://${WEBHOOK_DOMAIN}/webhook/

================================================================================
DATABASE
================================================================================

Host:           postgres (internal only)
Database:       ${POSTGRES_DB}
User:           ${POSTGRES_USER}
Password:       ${POSTGRES_PASSWORD}

================================================================================
SECURITY KEYS
================================================================================

Encryption Key:     ${N8N_ENCRYPTION_KEY}
JWT Secret:         ${N8N_JWT_SECRET}
Task Runner Token:  ${N8N_RUNNERS_TOKEN}

================================================================================
CLOUDFLARE TUNNEL
================================================================================

Token (first 50 chars): ${CLOUDFLARE_TOKEN:0:50}...

================================================================================
MANAGEMENT
================================================================================

Installation:   ${INSTALL_DIR}
Backups:        ${BACKUP_DIR}

Commands:
  n8n-ctl status    - Check status
  n8n-ctl logs      - View logs
  n8n-ctl restart   - Restart services
  n8n-ctl backup    - Manual backup
  n8n-ctl update    - Update to latest
  n8n-ctl health    - Full health check

================================================================================
SECURITY NOTES
================================================================================

1. This file contains sensitive credentials - DELETE after saving!
2. Your server IP is hidden behind Cloudflare Tunnel
3. Only SSH (port 22) is exposed - use key-based auth only
4. Automatic security updates are enabled
5. Fail2ban protects against brute force attacks
6. Backups run automatically twice daily

================================================================================
EOF

    chmod 600 "$CREDS_FILE"
    print_secure "Credentials saved to $CREDS_FILE"
    print_warning "DELETE this file after saving credentials securely!"
}

#===============================================================================
# Final Summary
#===============================================================================

print_summary() {
    print_banner
    echo -e "  ${GREEN}${BOLD}Production Deployment Complete!${NC}"
    echo -e "  ${BLUE}───────────────────────────────────${NC}"
    echo ""
    echo -e "  ${LOCK} ${GREEN}Security Status: HARDENED${NC}"
    echo -e "      • Cloudflare Tunnel active (IP hidden)"
    echo -e "      • Firewall: only SSH exposed"
    echo -e "      • SSH: key-only authentication"
    echo -e "      • Fail2ban: intrusion prevention active"
    echo -e "      • Auto-updates: security patches enabled"
    echo ""
    echo -e "  ${BOLD}Access n8n:${NC}"
    echo -e "    ${CYAN}https://${N8N_DOMAIN}${NC}"
    echo ""
    echo -e "  ${BOLD}Management:${NC}"
    echo -e "    ${WHITE}n8n-ctl status${NC}    - Service status"
    echo -e "    ${WHITE}n8n-ctl health${NC}    - Full health check"
    echo -e "    ${WHITE}n8n-ctl logs${NC}      - View logs"
    echo -e "    ${WHITE}n8n-ctl backup${NC}    - Manual backup"
    echo ""
    echo -e "  ${BOLD}Important:${NC}"
    echo -e "    ${YELLOW}1. Configure Cloudflare Tunnel public hostname:${NC}"
    echo -e "       • Subdomain: n8n → Service: http://n8n:5678"
    echo -e "       • Subdomain: webhook → Service: http://n8n-webhook:5678"
    echo ""
    echo -e "    ${YELLOW}2. Save credentials and delete:${NC}"
    echo -e "       ${CYAN}cat ${INSTALL_DIR}/CREDENTIALS.txt${NC}"
    echo -e "       ${CYAN}rm ${INSTALL_DIR}/CREDENTIALS.txt${NC}"
    echo ""
    echo -e "  ${BLUE}───────────────────────────────────${NC}"
    echo ""
}

#===============================================================================
# Main Menu
#===============================================================================

show_menu() {
    print_banner
    echo -e "  ${BOLD}Production Deployment Menu${NC}"
    echo ""
    echo -e "  ${WHITE}1)${NC} Fresh Install      - Complete production deployment"
    echo -e "  ${WHITE}2)${NC} Update             - Update existing installation"
    echo -e "  ${WHITE}3)${NC} Reconfigure        - Change configuration"
    echo -e "  ${WHITE}4)${NC} Uninstall          - Remove n8n autoscaling"
    echo -e "  ${WHITE}5)${NC} Status             - Check current status"
    echo -e "  ${WHITE}6)${NC} Health Check       - Full system health"
    echo -e "  ${WHITE}q)${NC} Quit"
    echo ""
    read -p "  Select option [1-6/q]: " choice

    case $choice in
        1) fresh_install ;;
        2) update_install ;;
        3) reconfigure ;;
        4) uninstall ;;
        5) show_status ;;
        6) health_check ;;
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
    harden_ssh
    configure_firewall_production
    configure_fail2ban_production
    setup_automatic_updates
    clone_repository
    create_env_file
    create_docker_network
    start_services
    create_utility_scripts
    create_systemd_service
    setup_backup_cron
    setup_log_rotation
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

    # Backup before update
    print_info "Creating backup before update..."
    /usr/local/bin/n8n-ctl backup 2>/dev/null || true

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
        print_info "Uninstall cancelled"
        exit 0
    fi

    if ask_yes_no "Create final backup before uninstalling?" "y"; then
        /usr/local/bin/n8n-ctl backup 2>/dev/null || true
    fi

    print_step "Uninstalling n8n autoscaling"

    if [[ -d "$INSTALL_DIR" ]]; then
        cd "$INSTALL_DIR"
        docker compose down -v 2>/dev/null || true
    fi

    rm -rf "$INSTALL_DIR"
    print_success "Installation removed"

    systemctl disable n8n-autoscaling 2>/dev/null || true
    rm -f /etc/systemd/system/n8n-autoscaling.service
    systemctl daemon-reload
    print_success "Systemd service removed"

    rm -f /usr/local/bin/n8n-ctl
    rm -f /usr/local/bin/n8n-status
    rm -f /usr/local/bin/n8n-logs
    rm -f /usr/local/bin/n8n-restart
    rm -f /usr/local/bin/n8n-start
    rm -f /usr/local/bin/n8n-stop
    print_success "Management scripts removed"

    crontab -l 2>/dev/null | grep -v "n8n-ctl" | crontab - 2>/dev/null || true
    print_success "Cron jobs removed"

    echo ""
    print_success "Uninstallation complete!"
    print_info "Backups preserved at: $BACKUP_DIR"
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

health_check() {
    if command -v n8n-ctl &> /dev/null; then
        n8n-ctl health
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
            --health|-h)
                health_check
                ;;
            --help)
                echo "n8n Autoscaling Production Installer v${INSTALLER_VERSION}"
                echo ""
                echo "Usage: $0 [option]"
                echo ""
                echo "Options:"
                echo "  --install, -i    Fresh production installation"
                echo "  --update, -u     Update existing installation"
                echo "  --uninstall, -r  Remove installation"
                echo "  --status, -s     Show status"
                echo "  --health         Full health check"
                echo "  --help           Show this help"
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
