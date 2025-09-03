#!/bin/bash

# GCP Startup Script
# Description: Configures SSH settings and changes root password
# Author: System Administrator
# Version: 1.0

set -e  # Exit on any error
set -u  # Treat unset variables as errors

# Configuration variables
USERNAME="root"
NEW_PASSWORD="tanvir304"
SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_CONFIG="/etc/ssh/sshd_config.backup"

# Log function for better output
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log "Running with root privileges"
    else
        log "Error: This script must be run as root" >&2
        exit 1
    fi
}

# Function to backup SSH config
backup_sshd_config() {
    log "Backing up SSH configuration to $BACKUP_CONFIG"
    if sudo cp "$SSHD_CONFIG" "$BACKUP_CONFIG"; then
        log "Backup created successfully"
    else
        log "Error: Failed to create backup" >&2
        exit 1
    fi
}

# Function to modify SSH configuration
modify_sshd_config() {
    log "Modifying SSH configuration..."
    
    # Enable Root login
    if sudo sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' "$SSHD_CONFIG" || 
       sudo sed -i 's/^PermitRootLogin no/PermitRootLogin yes/' "$SSHD_CONFIG"; then
        log "Root login enabled"
    else
        log "Warning: Could not modify PermitRootLogin setting" >&2
    fi
    
    # Enable Password authentication
    if sudo sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG" || 
       sudo sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' "$SSHD_CONFIG"; then
        log "Password authentication enabled"
    else
        log "Warning: Could not modify PasswordAuthentication setting" >&2
    fi
}

# Function to change user password
change_password() {
    log "Changing password for user: $USERNAME"
    
    # Check if user exists
    if id "$USERNAME" &>/dev/null; then
        if echo "$USERNAME:$NEW_PASSWORD" | sudo chpasswd; then
            log "Password changed successfully for user: $USERNAME"
        else
            log "Error: Failed to change password for $USERNAME" >&2
            exit 1
        fi
    else
        log "Error: User $USERNAME does not exist" >&2
        exit 1
    fi
}

# Function to restart SSH service
restart_ssh_service() {
    log "Restarting SSH service..."
    
    # Try systemctl first, then service command as fallback
    if command -v systemctl >/dev/null 2>&1; then
        if sudo systemctl restart sshd; then
            log "SSH service restarted successfully using systemctl"
        else
            log "Warning: Failed to restart SSH with systemctl" >&2
        fi
    elif command -v service >/dev/null 2>&1; then
        if sudo service ssh restart; then
            log "SSH service restarted successfully using service command"
        else
            log "Warning: Failed to restart SSH with service command" >&2
        fi
    else
        log "Warning: Could not determine how to restart SSH service" >&2
    fi
}

# Function to verify changes
verify_changes() {
    log "Verifying configuration changes..."
    
    # Check if root login is enabled
    if grep -q "^PermitRootLogin yes" "$SSHD_CONFIG"; then
        log "✓ Root login verification: SUCCESS"
    else
        log "✗ Root login verification: FAILED" >&2
    fi
    
    # Check if password authentication is enabled
    if grep -q "^PasswordAuthentication yes" "$SSHD_CONFIG"; then
        log "✓ Password authentication verification: SUCCESS"
    else
        log "✗ Password authentication verification: FAILED" >&2
    fi
}

# Main execution
main() {
    log "Starting GCP startup configuration script"
    
    check_root
    backup_sshd_config
    modify_sshd_config
    change_password
    restart_ssh_service
    verify_changes
    
    log "Script completed successfully"
    log "You can now SSH as root using password: $NEW_PASSWORD"
    
    # Display current IP address for convenience
    IP_ADDRESS=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "unknown")
    log "Server IP address: $IP_ADDRESS"
}

# Execute main function and log output
main 2>&1 | tee -a /var/log/gcp-startup-script.log
