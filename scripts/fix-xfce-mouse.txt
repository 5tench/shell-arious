#!/bin/bash
# Script to fix mouse issues in XFCE on Rocky Linux VM, reinstall Guest Additions, add user to wheel group, and prepare for Azure CLI
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

# Step 3: Fix rc.local permissions (optional, to silence warning)
if [ -f /etc/rc.d/rc.local ]; then
    echo "Fixing permissions for /etc/rc.d/rc.local..."
    chmod +x /etc/rc.d/rc.local
    ls -l /etc/rc.d/rc.local
else
    echo "No /etc/rc.d/rc.local found, skipping permission fix."
fi

# Step 4: Verify graphical target
echo "Verifying graphical target..."
systemctl get-default
if [ "$(systemctl get-default)" != "graphical.target" ]; then
    echo "Setting graphical target..."
    systemctl set-default graphical.target
fi

# Step 5: Install prerequisites for VirtualBox Guest Additions
echo "Installing prerequisites for VirtualBox Guest Additions..."
dnf install -y epel-release
dnf install -y kernel-devel gcc make perl elfutils-libelf-devel
# Verify kernel match
echo "Kernel version: $(uname -r)"
echo "Kernel-devel version: $(rpm -q kernel-devel)"

# Step 6: Reinstall VirtualBox Guest Additions
echo "Please ensure VirtualBox Guest Additions CD is inserted via Devices > Insert Guest Additions CD Image."
read -p "Press Enter to continue after inserting CD..."
mkdir -p /mnt/cdrom
mount /dev/cdrom /mnt/cdrom
sh /mnt/cdrom/VBox_LinuxAdditions.run || echo "Guest Additions installation may have warnings; check output."
umount /mnt/cdrom
echo "Checking Guest Additions logs..."
cat /var/log/vboxadd-setup.log | grep -i error || echo "No errors found in Guest Additions log."

# Step 7: Check XFCE and X server
echo "Checking X server logs for errors..."
cat /var/log/Xorg.0.log | grep -i error || echo "No errors in Xorg log."
echo "Checking vboxvideo driver..."
lsmod | grep vboxvideo || echo "vboxvideo driver not loaded; Guest Additions may have failed."
echo "Checking vboxguest driver..."
lsmod | grep vboxguest || echo "vboxguest driver not loaded; Guest Additions may have failed."

# Step 8: Clean up
echo "Cleaning up..."
dnf clean all

# Step 9: Notify user of next steps
echo "Setup complete! Reboot the VM with 'sudo reboot'."
echo "After reboot, log in as $USERNAME to XFCE and verify mouse cursor."
echo "Ensure VirtualBox Display settings: Video Memory ≥ 64MB, Enable 3D Acceleration, Graphics Controller VMSVGA."
echo "Check Input > Mouse Integration is enabled in VirtualBox."
echo "If mouse issues persist, check logs: /var/log/vboxadd-setup.log, /var/log/Xorg.0.log."
echo "In XFCE, adjust mouse settings: Menu > Settings > Mouse and Touchpad."
echo "Test sudo access: 'sudo dnf update' as $USERNAME."
echo "To install Azure CLI: 'sudo dnf install azure-cli -y'."