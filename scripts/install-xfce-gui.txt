sys#!/bin/bash
# Post-installation script for Rocky Linux VM: Update system, install XFCE, VirtualBox Guest Additions, and add user to wheel group
# Run as root or with sudo

# Exit on error
set -e

# Step 1: Update the system
echo "Updating system..."
dnf update -y

# Step 2: Add user to wheel group
USERNAME="devuser"
if id "$USERNAME" &>/dev/null; then
    echo "Adding existing user $USERNAME to wheel group..."
    usermod -aG wheel "$USERNAME"
else
    echo "Creating new user $USERNAME and adding to wheel group..."
    useradd -m -G wheel "$USERNAME"
    echo "Setting password for $USERNAME..."
    passwd "$USERNAME"
fi
echo "Verifying $USERNAME group membership..."
id "$USERNAME"

# Step 3: Install XFCE desktop environment
echo "Installing XFCE desktop environment..."
dnf groupinstall "Xfce" -y

# Step 4: Set graphical target
echo "Setting system to boot into graphical target..."
systemctl set-default graphical.target

# Step 5: Install prerequisites for VirtualBox Guest Additions
echo "Installing prerequisites for VirtualBox Guest Additions..."
dnf install -y epel-release
dnf install -y kernel-devel gcc make perl elfutils-libelf-devel

# Step 6: Install VirtualBox Guest Additions (assumes CD is inserted)
echo "Please ensure VirtualBox Guest Additions CD is inserted via Devices > Insert Guest Additions CD Image."
read -p "Press Enter to continue after inserting CD..."
mkdir -p /mnt/cdrom
mount /dev/cdrom /mnt/cdrom
sh /mnt/cdrom/VBox_LinuxAdditions.run || echo "Guest Additions installation may have warnings; check output."
umount /mnt/cdrom

# Step 7: Clean up
echo "Cleaning up..."
dnf clean all

# Step 8: Notify user of next steps
echo "Setup complete! Reboot the VM with 'sudo reboot'."
echo "After reboot, log in as $USERNAME to use XFCE."
echo "Ensure VirtualBox Display settings: Video Memory ≥ 64MB, Enable 3D Acceleration."
echo "Verify mouse cursor in XFCE; if issues, check Guest Additions logs (/var/log/vboxadd-setup.log)."
echo "Test sudo access: 'sudo dnf update' as $USERNAME."
echo "To use Azure CLI, install it with: 'sudo dnf install azure-cli -y'."