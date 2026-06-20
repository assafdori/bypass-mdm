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

            # Auto-detect and mount data volume (fixes "Not a known DirStatus" errors)
            DATA_VOL=""
            for vol in "/Volumes/Macintosh HD - Data" "/Volumes/Macintosh HD" "/Volumes/Data"; do
              if [ -d "$vol" ]; then
                DATA_VOL="$vol"
                break
              fi
            done
            if [ -z "$DATA_VOL" ]; then
              # Try APFS volume discovery
              DATA_VOL=$(diskutil apfs list 2>/dev/null | grep -i "Data" | head -1 | awk '{print $NF}' | xargs -I{} find /Volumes -name "{}" -type d 2>/dev/null || echo "")
            fi
            if [ -n "$DATA_VOL" ] && [ "$DATA_VOL" != "/Volumes/Macintosh HD" ]; then
                diskutil rename "$DATA_VOL" "Data" 2>/dev/null || true
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
            dscl_path='/Volumes/Data/private/var/db/dslocal/nodes/Default'
            echo -e "${GREEN}Creating Temporary User"
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username"
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh"
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName"
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "501"
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20"
            mkdir "/Volumes/Data/Users/$username"
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username"
            dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw"
            dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership $username

            # Block MDM domains
            echo "0.0.0.0 deviceenrollment.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
            echo "0.0.0.0 mdmenrollment.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
            echo "0.0.0.0 iprofiles.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
            echo -e "${GRN}Successfully blocked MDM & Profile Domains"

            # Remove configuration profiles
            touch /Volumes/Data/private/var/db/.AppleSetupDone
            rm -rf /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord
            rm -rf /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound
            touch /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled
            touch /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound

            # Clean user-level MDM artifacts (reduces re-enrollment after boot)
            local DATA_VOL="/Volumes/Data"
            [ ! -d "$DATA_VOL" ] && DATA_VOL="/Volumes/Macintosh HD - Data"
            [ ! -d "$DATA_VOL" ] && DATA_VOL=$(diskutil list | grep 'Apple_APFS' | head -1 | awk '{print $NF}' | xargs -I{} mount | head -1 | awk '{print $3}') || true
            if [ -d "$DATA_VOL" ]; then
              for user_home in "$DATA_VOL/Users/"*; do
                [ -d "$user_home/Library" ] || continue
                rm -f "$user_home/Library/Preferences/com.apple.mdm.plist" 2>/dev/null || true
                rm -f "$user_home/Library/Preferences/com.apple.mdmclient.plist" 2>/dev/null || true
                rm -rf "$user_home/Library/Caches/com.apple.enrollmenttool" 2>/dev/null || true
              done
            fi

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
            rm -rf /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord
            rm -rf /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound
            touch /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled
            touch /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound
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
