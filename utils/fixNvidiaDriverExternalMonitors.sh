#!/bin/bash

#Ensure graphics drivers are up to date and compatible. 
#Ensure Inte/ Nvidia / AMD/ Mesa drivers are up to date.
#To ensure optimal performance, keep Mesa updated.
apt update &&  apt upgrade
sudo add-apt-repository ppa:kisak/kisak-mesa
apt update &&  apt upgrade

#Install latest Nvidia Driver
apt install nvidia-driver-535
sudo reboot


#Check NVIDIA Settings with "nvidia-settings"
#