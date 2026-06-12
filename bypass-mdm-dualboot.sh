#!/bin/bash
set -euo pipefail

# bypass-mdm-dualboot.sh -- MDM bypass for dual-boot setups.
# Run this script from an enrolled macOS (with sudo) targeting a second,
# freshly-installed macOS volume to bypass MDM enrollment.
#
# Unlike the Recovery-mode scripts, this script writes to the *Data* volume
# of the target installation (via /private firmlink), which is the correct
# location on Apple Silicon with Signed System Volume (SSV).
#
# Usage: sudo ./bypass-mdm-dualboot.sh

RED='\033[1;31m'; GRN='\033[1;32m'; BLU='\033[1;34m'; YEL='\033[1;33m'; CYAN='\033[1;36m'; NC='\033[0m'

error_exit() { echo -e "${RED}ERROR: $1${NC}" >&2; exit 1; }
warn()       { echo -e "${YEL}WARNING: $1${NC}" >&2; }
success()    { echo -e "${GRN}\u2713 $1${NC}"; }
info()       { echo -e "${BLU}\u2139 $1${NC}"; }

if [[ $EUID -ne 0 ]]; then
	error_exit "This script must be run as root. Use: sudo $0"
fi

echo ""
echo -e "${CYAN}Bypass MDM -- Dual-Boot Mode${NC}"
echo ""

PS3='Please enter your choice: '
options=("Bypass MDM on target volume" "Reboot & Exit")
select opt in "${options[@]}"; do
	case $opt in
	"Bypass MDM on target volume")

		read -p "Enter the target system volume name (default 'Macintosh HD'): " baseVolume
		baseVolume="${baseVolume:=Macintosh HD}"
		read -p "Enter the target data volume name (default 'Macintosh HD - Data'): " dataVolume
		dataVolume="${dataVolume:=Macintosh HD - Data}"

		sys_path="/Volumes/$baseVolume"
		data_path="/Volumes/$dataVolume"

		if [ ! -d "$sys_path" ]; then
			error_exit "System volume not found at: $sys_path"
		fi
		if [ ! -d "$data_path" ]; then
			error_exit "Data volume not found at: $data_path"
		fi

		info "Target system volume: $sys_path"
		info "Target data volume: $data_path"

		# Create Temporary User on the Data volume
		echo -e "${NC}Create a Temporary Admin User${NC}"
		read -p "Enter Temporary Fullname (Default is 'Apple'): " realName
		realName="${realName:=Apple}"
		read -p "Enter Temporary Username (Default is 'Apple'): " username
		username="${username:=Apple}"
		read -p "Enter Temporary Password (Default is '1234'): " passw
		passw="${passw:=1234}"

		dscl_path="$data_path/private/var/db/dslocal/nodes/Default"
		if [ ! -d "$dscl_path" ]; then
			error_exit "Directory Services path not found: $dscl_path"
		fi

		info "Creating user account: $username"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "501"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20"
		mkdir -p "$data_path/Users/$username"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username"
		dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw"
		dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership "$username"
		success "Admin account created"

		# Block MDM domains on the DATA volume's hosts file (SSV-aware)
		hosts_file="$data_path/private/etc/hosts"
		[ -f "$hosts_file" ] || touch "$hosts_file"
		echo "0.0.0.0 deviceenrollment.apple.com" >>"$hosts_file"
		echo "0.0.0.0 mdmenrollment.apple.com"    >>"$hosts_file"
		echo "0.0.0.0 iprofiles.apple.com"        >>"$hosts_file"
		success "MDM domains blocked"

		# Mark setup as done
		touch "$data_path/private/var/db/.AppleSetupDone"
		success "Setup Assistant will be skipped"

		# Remove configuration profiles on the DATA volume
		config_path="$data_path/private/var/db/ConfigurationProfiles/Settings"
		mkdir -p "$config_path"
		rm -f "$config_path/.cloudConfigHasActivationRecord" \
		      "$config_path/.cloudConfigRecordFound"
		touch "$config_path/.cloudConfigProfileInstalled" \
		      "$config_path/.cloudConfigRecordNotFound"
		success "Configuration profiles reset"

		echo ""
		echo -e "${GRN}MDM bypass applied to target volume!${NC}"
		echo -e "${NC}Reboot into the new installation and login with:${NC}"
		echo -e "${YEL}  User: $username${NC}"
		echo -e "${YEL}  Pass: $passw${NC}"
		echo ""
		break
		;;
	"Reboot & Exit")
		info "Rebooting..."
		reboot
		break
		;;
	*) echo -e "${RED}Invalid option $REPLY${NC}" ;;
	esac
done
