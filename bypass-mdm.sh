#!/bin/bash

# Define color codes
RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
PUR='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

# Display header
echo -e "${CYAN}Bypass MDM By Assaf Dori (assafdori.com)${NC}"
echo ""

# Prompt user for choice
PS3='Please enter your choice: '
options=("Bypass MDM from Recovery" "Reboot & Exit")
select opt in "${options[@]}"; do
    case $opt in
        "Bypass MDM from Recovery")
            # Bypass MDM from Recovery
            echo -e "${YEL}Bypass MDM from Recovery"

            # Remove configuration profiles
            touch /Volumes/Data/private/var/db/.AppleSetupDone
            rm -rf "/Volumes/Без названия/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound"
            touch "/Volumes/Без названия/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled"
            touch "/Volumes/Без названия/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound"

            echo -e "${GRN}MDM enrollment has been bypassed!${NC}"
            echo -e "${NC}Exit terminal and reboot your Mac.${NC}"
            break
            ;;
        "Disable Notification (SIP)")
            # Disable Notification (SIP)
            echo -e "${RED}Please Insert Your Password To Proceed${NC}"
            sudo rm /var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord
            sudo rm /var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound
            sudo touch /var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled
            sudo touch /var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound
            break
            ;;
        "Disable Notification (Recovery)")
            # Disable Notification (Recovery)
            rm -rf "/Volumes/Без названия/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord"
            rm -rf "/Volumes/Без названия/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound"
            touch "/Volumes/Без названия/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled"
            touch "/Volumes/Без названия/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound"
            break
            ;;
        "Check MDM Enrollment")
            # Check MDM Enrollment
            echo ""
            echo -e "${GRN}Check MDM Enrollment. Error is success${NC}"
            echo ""
            echo -e "${RED}Please Insert Your Password To Proceed${NC}"
            echo ""
            sudo profiles show -type enrollment
            break
            ;;
        "Reboot & Exit")
            # Reboot & Exit
            echo "Rebooting..."
            reboot
            break
            ;;
        *) echo "Invalid option $REPLY" ;;
    esac
done
