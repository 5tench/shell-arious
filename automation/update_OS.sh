#!/bin/bash

echo "Starting system cleanup & updates..."

# Clean up unused packages and dependencies
sudo apt autoremove -y
sudo apt autoclean -y
sudo systemd-tmpfiles --remove
sudo rm -rf .cache/thumbnails/*
sudo du -sh /var/cache/apt | sudo apt-get clean
sudo apt-get install -f

# Prompt for system updates
read -p "Do you want to update the system as well? (y/n): " update_choice
update_choice=${update_choice:-y}  # Default to 'y' if empty

if [ "$update_choice" = "y" -o "$update_choice" = "Y" ]; then
    # Update system
    echo "Updating the system...."
    sudo apt update && sudo apt upgrade -y
    sudo apt install --install-recommends linux-generic
    sudo apt update && sudo apt upgrade -y
    sudo apt dist-upgrade -y
    sudo apt full-upgrade
    sudo apt update && sudo apt upgrade -y
    echo "System updated successfully!"
else
    echo "Skipping system updates."
fi

echo "Cleanup complete."
