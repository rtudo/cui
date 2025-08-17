#!/bin/bash

# CUI Systemd Service Installation Script
# This script installs CUI as a systemd service on Linux systems

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
DEFAULT_PORT=4001
DEFAULT_USER=$USER
DEFAULT_NODE_VERSION="22.18.0"

# Function to print colored output
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
   print_error "Please do not run this script as root"
   exit 1
fi

# Check if systemd is available
if ! command -v systemctl &> /dev/null; then
    print_error "systemctl not found. This script requires systemd."
    exit 1
fi

# Get the script's directory (project root)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

print_info "CUI Systemd Service Installer"
print_info "=============================="
print_info "Project directory: $PROJECT_DIR"

# Prompt for configuration
read -p "Enter the user to run the service as [$DEFAULT_USER]: " SERVICE_USER
SERVICE_USER=${SERVICE_USER:-$DEFAULT_USER}

read -p "Enter the port for CUI server [$DEFAULT_PORT]: " SERVICE_PORT
SERVICE_PORT=${SERVICE_PORT:-$DEFAULT_PORT}

# Detect Node.js installation
NODE_PATH=""
if [ -d "$HOME/.nvm" ]; then
    # Check for nvm installation
    NVM_NODE_PATH="$HOME/.nvm/versions/node"
    if [ -d "$NVM_NODE_PATH" ]; then
        print_info "Found nvm installation"
        # List available Node versions
        echo "Available Node versions:"
        ls -1 "$NVM_NODE_PATH" | grep -E "^v[0-9]+" | sed 's/^/  /'
        
        read -p "Enter Node version to use (e.g., v22.18.0): " NODE_VERSION
        NODE_VERSION=${NODE_VERSION:-v$DEFAULT_NODE_VERSION}
        
        if [ ! -d "$NVM_NODE_PATH/$NODE_VERSION" ]; then
            print_error "Node version $NODE_VERSION not found"
            exit 1
        fi
        
        NODE_PATH="$NVM_NODE_PATH/$NODE_VERSION/bin"
    fi
elif command -v node &> /dev/null; then
    # Use system Node.js
    NODE_PATH="$(dirname $(which node))"
    print_info "Using system Node.js from $NODE_PATH"
else
    print_error "Node.js not found. Please install Node.js first."
    exit 1
fi

# Verify Node.js is accessible
if [ ! -x "$NODE_PATH/node" ]; then
    print_error "Node.js executable not found at $NODE_PATH/node"
    exit 1
fi

NODE_VERSION_OUTPUT=$("$NODE_PATH/node" --version)
print_info "Using Node.js $NODE_VERSION_OUTPUT"

# Check if the project is built
if [ ! -d "$PROJECT_DIR/dist" ]; then
    print_warn "dist/ directory not found. Building project..."
    cd "$PROJECT_DIR"
    npm run build
    cd - > /dev/null
fi

# Create .cui directory for the user if it doesn't exist
CUI_DIR="/home/$SERVICE_USER/.cui"
if [ ! -d "$CUI_DIR" ]; then
    print_info "Creating $CUI_DIR directory..."
    mkdir -p "$CUI_DIR"
fi

# Generate systemd service file
SERVICE_NAME="cui@${SERVICE_USER}.service"
SERVICE_FILE="/tmp/${SERVICE_NAME}"

print_info "Generating systemd service file..."

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=CUI Server - Web UI Agent Platform
Documentation=https://github.com/bmpixel/cui
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$PROJECT_DIR

# Environment variables
Environment="NODE_ENV=production"
Environment="PATH=/usr/local/bin:/usr/bin:/bin:$NODE_PATH"
Environment="PORT=$SERVICE_PORT"
Environment="HOME=/home/$SERVICE_USER"

# Main service command
ExecStart=$NODE_PATH/node $PROJECT_DIR/dist/server.js

# Restart policy
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

# Process management
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

print_info "Service file generated at $SERVICE_FILE"

# Install the service
print_info "Installing systemd service..."
sudo cp "$SERVICE_FILE" "/etc/systemd/system/${SERVICE_NAME}"
sudo systemctl daemon-reload

# Set proper permissions
sudo chown root:root "/etc/systemd/system/${SERVICE_NAME}"
sudo chmod 644 "/etc/systemd/system/${SERVICE_NAME}"

# Clean up temp file
rm "$SERVICE_FILE"

print_info "Service installed successfully!"

# Ask if user wants to enable and start the service
read -p "Do you want to enable the service to start on boot? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo systemctl enable "$SERVICE_NAME"
    print_info "Service enabled to start on boot"
fi

read -p "Do you want to start the service now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo systemctl start "$SERVICE_NAME"
    sleep 2
    
    # Check if service started successfully
    if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
        print_info "Service started successfully!"
        print_info ""
        print_info "Service Status:"
        sudo systemctl status "$SERVICE_NAME" --no-pager | head -15
        print_info ""
        print_info "Access CUI at: http://localhost:$SERVICE_PORT"
    else
        print_error "Service failed to start. Check logs with:"
        print_error "  sudo journalctl -xeu $SERVICE_NAME"
    fi
fi

print_info ""
print_info "Useful commands:"
print_info "  Check status:  sudo systemctl status $SERVICE_NAME"
print_info "  Start service: sudo systemctl start $SERVICE_NAME"
print_info "  Stop service:  sudo systemctl stop $SERVICE_NAME"
print_info "  Restart:       sudo systemctl restart $SERVICE_NAME"
print_info "  View logs:     sudo journalctl -fu $SERVICE_NAME"
print_info "  Disable:       sudo systemctl disable $SERVICE_NAME"
print_info "  Uninstall:     sudo rm /etc/systemd/system/$SERVICE_NAME && sudo systemctl daemon-reload"