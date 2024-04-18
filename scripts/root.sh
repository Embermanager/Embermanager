#!/bin/bash

# Prompt the user for the root password
echo "Enter the root password:"
read -s password

# Set the root password
echo "Setting root password..."
echo "root:$password" | sudo chpasswd

# Unlock the root account if it's locked
echo "Unlocking root account..."
sudo passwd -u root

# Enable root login via SSH
echo "Enabling root login via SSH..."
sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Restart SSH service to apply changes
echo "Restarting SSH service..."
sudo systemctl restart ssh

echo "Root login via SSH has been enabled. Use the password you set for the root user."
