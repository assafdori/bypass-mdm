#!/bin/bash
RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
PUR='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

echo -e "${CYAN}Bypass MDM By Assaf Dori (assafdori.com)${NC}"
echo ""
PS3='Please enter your choice: '
options=("Bypass MDM from Recovery" "Reboot")
select opt in "${options[@]}"; do
    case $opt in
    "Bypass MDM from Recovery")
        echo -e "${YEL}Bypass MDM from Recovery"
        if [ -d "/Volumes/Macintosh HD - Data" ]; then
               diskutil rename "Macintosh HD - Data" "Data"
        fi
        echo -e "${NC}Create a Temporary User"
          echo -e "Enter Temporary Fullname (Default is 'Apple')"
        read realName
          realName="${realName:= Apple}"
        echo -e "${NC}Enter Temporary Username ${RED}A-Z ONLY, NO SPACES ALLOWED ${NC}(Default is 'Apple')"
          read username
        username="${username:=Apple}"
          echo -e "${NC}Enter Temporary Password (Default is '1234')"
        read passw
          passw="${passw:=1234}"
        dscl_path='/Volumes/Data/private/var/db/dslocal/nodes/Default'
        echo -e "${GREEN}Creating Temporary User"
          # Create user
        dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username"
          dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh"
        dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName"
         dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName"
        dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "501"
        dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20"
        mkdir "/Volumes/Data/Users/$username"
        dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username"
        dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw"
        dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership $username
        echo "0.0.0.0 deviceenrollment.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
        echo "0.0.0.0 mdmenrollment.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
        echo "0.0.0.0 iprofiles.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
        echo -e "${GRN}Successfully blocked MDM domains"
        echo -e "${NC}Removing configuration profiles"
      touch /Volumes/Data/private/var/db/.AppleSetupDone
        rm -rf /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord
    rm -rf /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound
    touch /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled
    touch /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound
    echo -e "${GRN}MDM enrollement has been bypassed!${NC}"
    echo -e "${NC}Exit terminal and reboot your Mac.${NC}"
        break
        ;;
    "Disable Notification (SIP)")
        echo -e "${RED}Please Insert Your Password To Proceed${NC}"
        sudo rm /var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord
        sudo rm /var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound
        sudo touch /var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled
        sudo touch /var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound
        break
        ;;
    "Disable Notification (Recovery)")
        rm -rf /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord
    rm -rf /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound
    touch /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled
    touch /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound

        break
        ;;
    "Check MDM Enrollment")
        echo ""
        echo -e "${GRN}Check MDM Enrollment. Error is success${NC}"
        echo ""
        echo -e "${RED}Please Insert Your Password To Proceed${NC}"
        echo ""
        sudo profiles show -type enrollment
        break
        ;;
    "Exit")
         echo "Rebooting..."
        reboot
        break
        ;;
    *) echo "Invalid option $REPLY" ;;
    esac
done
