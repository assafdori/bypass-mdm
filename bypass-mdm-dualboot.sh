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

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root. Please use sudo.${RED}"
    exit 1
fi

# Prompt user for choice
PS3='Please enter your choice: '
options=("Bypass MDM from Recovery" "Reboot & Exit")
select opt in "${options[@]}"; do
    case $opt in
        "Bypass MDM from Recovery")
            read -p "Enter the main partition (Default is 'Machintosh HD'): " baseVolume
            baseVolume="${baseVolume:='Machintosh HD'}"
            read -p "Enter the data partition (Default is 'Machintosh HD - Data'): " dataVolume
            dataVolume="${dataVolume:='Machintosh HD - Data'}"

            # Check if baseVolume exists
            if [ ! -d "/Volumes/$baseVolume" ]; then
                echo -e "${RED}Error: Main partition '/Volumes/$baseVolume' not found.${RED}"
                exit 1
            fi

            # Check if dataVolume exists
            if [ ! -d "/Volumes/$dataVolume" ]; then
                echo -e "${RED}Error: Data partition '/Volumes/$dataVolume' not found.${RED}"
                exit 1
            fi

            # Create Temporary User
            echo -e "${NC}Create a Temporary User"
            read -p "Enter Temporary Fullname (Default is 'Apple'): " realName
            realName="${realName:=Apple}"
            read -p "Enter Temporary Username (Default is 'Apple'): " username
            username="${username:=Apple}"
            read -p "Enter Temporary Password (Default is '1234'): " passw
            passw="${passw:=1234}"

            # Create User
            dscl_path="/Volumes/${dataVolume}/private/var/db/dslocal/nodes/Default"
            echo -e "${GREEN}Creating Temporary User"
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username"
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh"
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName"
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "501"
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20"
            mkdir "/Volumes/$dataVolume/Users/$username"
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username"
            dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw"
            dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership $username

            # Block MDM domains
            echo "0.0.0.0 deviceenrollment.apple.com" >> "/Volumes/$baseVolume/etc/hosts"
            echo "0.0.0.0 mdmenrollment.apple.com" >> "/Volumes/$baseVolume/etc/hosts"
            echo "0.0.0.0 iprofiles.apple.com" >> "/Volumes/$baseVolume/etc/hosts"
            echo -e "${GRN}Successfully blocked MDM & Profile Domains"

            # Remove configuration profiles
            touch "/Volumes/$dataVolume/private/var/db/.AppleSetupDone"
            rm -rf "/Volumes/$baseVolume/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord"
            rm -rf "/Volumes/$baseVolume/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound"
            touch "/Volumes/$baseVolume/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled"
            touch "/Volumes/$baseVolume/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound"


            echo -e "${GRN}MDM enrollment has been bypassed!${NC}"
            echo -e "${NC}Exit terminal and reboot your Mac.${NC}"
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
