#!bin/bash

clean_directory (){   
    dir=$1
    echo "Cleaning all files in $dir..."
    rm -rf "$dir"/*
}

# Clean /tmp and /var/tmp

echo "Cleaning system temp"
clean_directory "/tmp"
clean_directory "/var/tmp"

# Clean cache directories

echo "Cleaning system cache..."
rm -rf /var/cache/*
rm -rf /home/*/.cache/*

# Clean apt package cache

echo "Cleaning apt cache..."
sudo apt-get clean

# Remove old kernel versions

echo "Removing old kernel versions..."
sudo apt-get autoremove --purge -y

# Clean old logs (keep the most recent ones)

echo "Cleaning old logs..."
find /var/log -type f -name "*.log" -exec rm -f {} \;

# Clean crash reports

echo "Cleaning crash reports..."
rm -rf /var/crash/*

# Clean systemd journal logs (older than 7 days)

echo "Cleaning systemd journal logs..."
sudo journalctl --vacuum-time=7d

# Clean Trash

echo "Cleaning Trash folders..."
rm -rf $HOME/.local/share/Trash/*

# Clean thumbnail cache

echo "Cleaning thumbnail cache..."
rm -rf $HOME/.cache/thumbnails/*
echo "System cleanup complete."