#!/bin/bash

# bypass-mdm-v2-FIXED.sh
# Version: 3.5 - 2024-03-23
# Fixed version that mounts the Data volume in Recovery Mode
# Handles FileVault encrypted volumes

VERSION="3.5"

# Define color codes
RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
PUR='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

# Error handling function
error_exit() {
	echo -e "${RED}ERROR: $1${NC}" >&2
	exit 1
}

# Warning function
warn() {
	echo -e "${YEL}WARNING: $1${NC}" >&2
}

# Success function
success() {
	echo -e "${GRN}✓ $1${NC}" >&2
}

# Info function
info() {
	echo -e "${BLU}ℹ $1${NC}" >&2
}

# Debug function
debug() {
	echo -e "${PUR}[DEBUG] $1${NC}" >&2
}

# Show current system state
show_system_state() {
	echo ""
	echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
	echo -e "${CYAN}║  Debug Info - Version ${VERSION}                     ║${NC}"
	echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
	echo ""
	
	info "Current mounted volumes:"
	ls -la /Volumes/ 2>&1 | while read line; do
		echo "    $line"
	done
	
	echo ""
	info "APFS Volumes from diskutil:"
	diskutil list | grep "APFS Volume" | while read line; do
		echo "    $line"
	done
	
	echo ""
	info "Checking for Data volume in diskutil:"
	diskutil list | grep "APFS Volume" | grep "Data"
	if [ $? -ne 0 ]; then
		echo "    (No Data volume found in diskutil list)"
	fi
	
	echo ""
}

# Function to unlock and mount data volume
# Returns the mounted volume name via echo for capture
mount_data_volume() {
    info "=== MOUNT DATA VOLUME STEP ==="
    
    # Check if Data volume is already mounted
    if [ -d "/Volumes/Data" ]; then
        info "Data volume already mounted at /Volumes/Data" >&2
        echo "Data"
        return 0
    fi
    
    debug "Data volume not found at /Volumes/Data, need to mount it" >&2
    
    # Find the data volume identifier from diskutil
    local data_volume_id=""
    
    info "Searching for 'Data' volume in diskutil..." >&2
    
    # Strategy 1: Look for "Data" APFS volume on disk3
    data_volume_id=$(diskutil list | grep "APFS Volume" | grep "Data" | grep "disk3" | awk '{print $NF}' | head -1)
    debug "After searching on disk3: data_volume_id='$data_volume_id'" >&2
    
    # Strategy 2: If not found, look for volume with Data in name (any disk)
    if [ -z "$data_volume_id" ]; then
        debug "Not found on disk3, searching all disks..." >&2
        data_volume_id=$(diskutil list | grep "APFS Volume" | grep "Data" | awk '{print $NF}' | head -1)
        debug "After searching all disks: data_volume_id='$data_volume_id'" >&2
    fi
    
    if [ -z "$data_volume_id" ]; then
        error_exit "Could not find 'Data' volume identifier in diskutil output"
    fi
    
    info "Found data volume identifier: $data_volume_id" >&2
    
    # Check if volume is encrypted/locked
    info "Checking if volume is encrypted..." >&2
    local disk_info
    disk_info=$(diskutil apfs list 2>&1 | grep -A 5 "$data_volume_id")
    debug "Volume info:\n$disk_info" >&2
    
    # Check if locked (look for FileVault: Yes or Locked: Yes)
    local volume_status
    volume_status=$(diskutil apfs list 2>&1 | grep -A 15 "Volume $data_volume_id" | head -20)
    debug "Full volume status:\n$volume_status" >&2
    
    if echo "$volume_status" | grep -E "(FileVault.*Yes|Locked.*Yes)" > /dev/null; then
        warn "╔════════════════════════════════════════════════════════╗" >&2
        warn "║  FILEVAULT ENCRYPTED VOLUME DETECTED                   ║" >&2  
        warn "║  The Data volume is encrypted and needs to be unlocked ║" >&2
        warn "║  before we can create a user account.                  ║" >&2
        warn "╚════════════════════════════════════════════════════════╝" >&2
        
        # Try to unlock with user password
        local unlock_success=0
        local unlock_attempts=0
        
        while [ $unlock_success -eq 0 ] && [ $unlock_attempts -lt 3 ]; do
            unlock_attempts=$((unlock_attempts + 1))
            
            echo ""
            echo -e "${CYAN}────────────────────────────────────────────────${NC}" >&2
            if [ $unlock_attempts -eq 1 ]; then
                echo -e "${YEL}Please enter your FileVault password${NC}" >&2
                echo -e "${YEL}(This is the password you use to unlock your Mac at startup)${NC}" >&2
                echo ""
                read -s -p "Password: " filevault_pass
            else
                echo -e "${RED}Password incorrect. Attempt $unlock_attempts of 3${NC}" >&2
                echo ""
                read -s -p "Try again: " filevault_pass
            fi
            echo ""
            echo -e "${CYAN}────────────────────────────────────────────────${NC}" >&2
            echo ""
            
            info "Attempting to unlock volume..." >&2
            local unlock_output
            unlock_output=$(diskutil apfs unlockVolume "$data_volume_id" -passphrase "$filevault_pass" 2>&1)
            local unlock_exit=$?
            
            debug "Unlock output: $unlock_output" >&2
            
            if [ $unlock_exit -eq 0 ]; then
                success "Volume unlocked successfully" >&2
                unlock_success=1
            else
                warn "Unlock failed: $unlock_output" >&2
            fi
        done
        
        if [ $unlock_success -eq 0 ]; then
            error_exit "Failed to unlock volume after $unlock_attempts attempts. Cannot proceed."
        fi
    fi
    
    # Now try to mount the volume
    info "Attempting to mount data volume..." >&2
    
    # Try method 1: standard mount
    debug "Method 1: diskutil mount $data_volume_id" >&2
    local mount_output
    mount_output=$(diskutil mount "$data_volume_id" 2>&1)
    debug "Mount output: $mount_output" >&2
    
    if echo "$mount_output" | grep -q "mounted"; then
        success "Data volume mounted successfully (method 1)" >&2
        sleep 1
        
        # Verify it actually mounted
        if [ -d "/Volumes/Data" ]; then
            success "Verified: /Volumes/Data exists" >&2
            echo "Data"
            return 0
        else
            warn "Mount reported success but /Volumes/Data does not exist" >&2
        fi
    else
        warn "Method 1 failed: $mount_output" >&2
    fi
    
    # Try method 2: mountDisk
    debug "Method 2: diskutil mountDisk $data_volume_id" >&2
    mount_output=$(diskutil mountDisk "$data_volume_id" 2>&1)
    debug "MountDisk output: $mount_output" >&2
    
    if echo "$mount_output" | grep -q "mounted"; then
        success "Data volume mounted with mountDisk (method 2)" >&2
        sleep 1
        
        if [ -d "/Volumes/Data" ]; then
            success "Verified: /Volumes/Data exists" >&2
            echo "Data"
            return 0
        fi
    else
        warn "Method 2 failed: $mount_output" >&2
    fi
    
    # Try method 3: force mount with explicit mount point
    debug "Method 3: Force mount to /Volumes/Data" >&2
    mkdir -p /Volumes/Data 2>/dev/null
    mount_output=$(diskutil mount -mountPoint /Volumes/Data "$data_volume_id" 2>&1)
    debug "Force mount output: $mount_output" >&2
    
    if echo "$mount_output" | grep -q "mounted"; then
        success "Data volume force mounted (method 3)" >&2
        sleep 1
        
        if [ -d "/Volumes/Data" ]; then
            success "Verified: /Volumes/Data exists" >&2
            echo "Data"
            return 0
        fi
    else
        warn "Method 3 failed: $mount_output" >&2
    fi
    
    # Method 4: Try using mount command directly
    debug "Method 4: Direct mount command" >&2
    local device_path="/dev/$data_volume_id"
    if [ -e "$device_path" ]; then
        debug "Device exists: $device_path" >&2
        mount_output=$(mount -t apfs "$device_path" /Volumes/Data 2>&1)
        if [ $? -eq 0 ]; then
            success "Data volume mounted with direct mount (method 4)" >&2
            echo "Data"
            return 0
        else
            warn "Method 4 failed: $mount_output" >&2
        fi
    else
        debug "Device does not exist: $device_path" >&2
    fi
    
    error_exit "All mount methods failed. Could not mount data volume."
}

# Function to detect system volumes with multiple fallback strategies
# Optional argument: $1 = pre-mounted data volume name
detect_volumes() {
	local system_vol=""
	local data_vol="${1:-}"

	info "=== DETECT VOLUMES STEP ==="
	
	# Debug: Show what was passed in
	debug "Passed data_vol argument: '$data_vol'" >&2
	
	# Strategy 0: If data volume was already mounted and passed in, verify it
	if [ -n "$data_vol" ]; then
		info "Checking if passed data volume '$data_vol' is valid..." >&2
		if [ -d "/Volumes/$data_vol/private/var/db/dslocal" ]; then
			success "Passed data volume '$data_vol' is valid (has dslocal)" >&2
			# Still need to find system volume
		else
			warn "Passed data volume '$data_vol' does not have dslocal directory" >&2
			data_vol=""
		fi
	fi
	
	# Strategy 1: Look for common macOS APFS volume patterns
	info "Strategy 1: Looking for system volume..." >&2
	for vol in /Volumes/*; do
		if [ -d "$vol" ]; then
			vol_name=$(basename "$vol")
			debug "Checking volume: $vol_name" >&2

			# Check if this looks like a system volume (not Data, not recovery)
			if [[ ! "$vol_name" =~ "Data"$ ]] && [[ ! "$vol_name" =~ "Recovery" ]] && [ -d "$vol/System" ]; then
				system_vol="$vol_name"
				success "Found system volume: $system_vol" >&2
				break
			fi
		fi
	done

	# Strategy 2: If no system volume found, try looking for any volume with /System directory
	if [ -z "$system_vol" ]; then
		info "Strategy 2: Looking for any volume with /System directory..." >&2
		for vol in /Volumes/*; do
			if [ -d "$vol/System" ]; then
				system_vol=$(basename "$vol")
				warn "Using volume with /System directory: $system_vol" >&2
				break
			fi
		done
	fi

	# Strategy 3: Check for Data volume
	if [ -z "$data_vol" ]; then
		info "Strategy 3: Checking for Data volume..." >&2
		if [ -d "/Volumes/Data" ]; then
			data_vol="Data"
			success "Found data volume: $data_vol" >&2
		elif [ -n "$system_vol" ] && [ -d "/Volumes/$system_vol - Data" ]; then
			data_vol="$system_vol - Data"
			success "Found data volume: $data_vol" >&2
		else
			# Look for any volume ending with "Data"
			for vol in /Volumes/*Data; do
				if [ -d "$vol" ]; then
					data_vol=$(basename "$vol")
					warn "Found data volume: $data_vol" >&2
					break
				fi
			done
		fi
	fi
	
	# Strategy 4: Look for any volume with dslocal directory (indicates data volume)
	if [ -z "$data_vol" ]; then
		info "Strategy 4: Looking for volume with dslocal directory..." >&2
		for vol in /Volumes/*; do
			if [ -d "$vol" ]; then
				vol_name=$(basename "$vol")
				debug "Checking volume '$vol_name' for dslocal..." >&2
				
				# Skip system volume, recovery volumes, and macOS Base System
				if [ "$vol_name" != "$system_vol" ] && [[ ! "$vol_name" =~ "Recovery" ]] && [[ ! "$vol_name" =~ "Preboot" ]] && [[ ! "$vol_name" =~ "VM" ]] && [[ ! "$vol_name" =~ "Base System" ]]; then
					# Check if this volume has the dslocal directory
					if [ -d "$vol/private/var/db/dslocal" ]; then
						data_vol="$vol_name"
						success "Found data volume by dslocal presence: $data_vol" >&2
						break
					else
						debug "Volume '$vol_name' does not have /private/var/db/dslocal" >&2
					fi
				else
					debug "Skipping volume '$vol_name' (filtered out)" >&2
				fi
			fi
		done
	fi

	# Validate findings
	info "=== DETECTION RESULTS ==="
	debug "system_vol='$system_vol'" >&2
	debug "data_vol='$data_vol'" >&2
	
	if [ -z "$system_vol" ]; then
		error_exit "Could not detect system volume. Please ensure you're running this in Recovery mode with a macOS installation present."
	fi

	if [ -z "$data_vol" ]; then
		error_exit "Could not detect data volume. Please ensure you're running this in Recovery mode with a macOS installation present."
	fi

	echo "$system_vol|$data_vol"
}

# Show initial debug info
show_system_state

# Mount data volume first
info "=== STARTING MOUNT PROCESS ==="
mount_data_volume
mount_exit_code=$?

if [ $mount_exit_code -ne 0 ]; then
	error_exit "Mount process failed with exit code $mount_exit_code"
fi

# Check if Data volume was mounted
if [ ! -d "/Volumes/Data" ]; then
	error_exit "Mount reported success but /Volumes/Data does not exist"
fi

mounted_data_vol="Data"
success "Mount process completed successfully"

# Detect volumes at startup, passing the mounted volume if found
info "=== STARTING DETECTION PROCESS ==="
volume_info=$(detect_volumes "$mounted_data_vol")
if [ $? -ne 0 ]; then
	exit 1
fi

system_volume=$(echo "$volume_info" | cut -d'|' -f1)
data_volume=$(echo "$volume_info" | cut -d'|' -f2)

# Display header
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Bypass MDM By Assaf Dori (assafdori.com)   ║${NC}"
echo -e "${CYAN}║  Version: ${VERSION}                                ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
success "System Volume: $system_volume"
success "Data Volume: $data_volume"
echo ""

# Prompt user for choice
PS3='Please enter your choice: '
options=("Bypass MDM from Recovery" "Reboot & Exit")
select opt in "${options[@]}"; do
	case $opt in
	"Bypass MDM from Recovery")
		echo ""
		echo -e "${YEL}═══════════════════════════════════════${NC}"
		echo -e "${YEL}  Starting MDM Bypass Process${NC}"
		echo -e "${YEL}═══════════════════════════════════════${NC}"
		echo ""

		# Normalize data volume name if needed
		if [ "$data_volume" != "Data" ]; then
			info "Renaming data volume to 'Data' for consistency..."
			if diskutil rename "$data_volume" "Data" >/dev/null 2>&1; then
				success "Data volume renamed successfully"
				data_volume="Data"
			else
				warn "Could not rename data volume, continuing with: $data_volume"
			fi
		fi

		# Validate critical paths
		info "Validating system paths..."

		system_path="/Volumes/$system_volume"
		data_path="/Volumes/$data_volume"

		if [ ! -d "$system_path" ]; then
			error_exit "System volume path does not exist: $system_path"
		fi

		if [ ! -d "$data_path" ]; then
			error_exit "Data volume path does not exist: $data_path"
		fi

		dscl_path="$data_path/private/var/db/dslocal/nodes/Default"
		if [ ! -d "$dscl_path" ]; then
			error_exit "Directory Services path does not exist: $dscl_path"
		fi

		success "All system paths validated"
		echo ""

		# Create Temporary User
		echo -e "${CYAN}Creating Temporary Admin User${NC}"
		echo -e "${NC}Press Enter to use defaults (recommended)${NC}"

		# Get and validate real name
		read -p "Enter Temporary Fullname (Default is 'Apple'): " realName
		realName="${realName:=Apple}"

		# Get and validate username
		while true; do
			read -p "Enter Temporary Username (Default is 'Apple'): " username
			username="${username:=Apple}"
			
			# Check if username is empty
			if [ -z "$username" ]; then
				warn "Username cannot be empty"
				continue
			fi
			
			# Check length (1-31 characters for macOS)
			if [ ${#username} -gt 31 ]; then
				warn "Username too long (max 31 characters)"
				continue
			fi
			
			break
		done

		# Get and validate password
		while true; do
			read -p "Enter Temporary Password (Default is '1234'): " passw
			passw="${passw:=1234}"
			
			if [ ${#passw} -lt 4 ]; then
				warn "Password too short (minimum 4 characters recommended)"
				continue
			fi
			
			break
		done

		echo ""

		# Find available UID
		info "Checking for available UID..."
		available_uid="501"
		if dscl -f "$dscl_path" localhost -search /Local/Default/Users UniqueID 501 >/dev/null 2>&1; then
			available_uid="502"
			info "UID 501 is in use, using UID $available_uid instead"
		fi
		success "Using UID: $available_uid"
		echo ""

		# Create User with error handling
		info "Creating user account: $username"

		if ! dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" >/dev/null 2>&1; then
			error_exit "Failed to create user account"
		fi

		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh" >/dev/null 2>&1 || warn "Failed to set user shell"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName" >/dev/null 2>&1 || warn "Failed to set real name"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "$available_uid" >/dev/null 2>&1 || warn "Failed to set UID"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20" >/dev/null 2>&1 || warn "Failed to set GID"

		user_home="$data_path/Users/$username"
		if [ ! -d "$user_home" ]; then
			if mkdir -p "$user_home" >/dev/null 2>&1; then
				success "Created user home directory"
			else
				error_exit "Failed to create user home directory: $user_home"
			fi
		else
			warn "User home directory already exists: $user_home"
		fi

		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username" >/dev/null 2>&1 || warn "Failed to set home directory"

		if ! dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw" >/dev/null 2>&1; then
			error_exit "Failed to set user password"
		fi

		if ! dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership "$username" >/dev/null 2>&1; then
			error_exit "Failed to add user to admin group"
		fi

		success "User account created successfully"
		echo ""

		# Block MDM domains
		info "Blocking MDM enrollment domains..."

		hosts_file="$system_path/etc/hosts"
		if [ ! -f "$hosts_file" ]; then
			warn "Hosts file does not exist, creating it"
			touch "$hosts_file" >/dev/null 2>&1 || error_exit "Failed to create hosts file"
		fi

		# Check if entries already exist to avoid duplicates
		grep -q "deviceenrollment.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 deviceenrollment.apple.com" >> "$hosts_file"
		grep -q "mdmenrollment.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 mdmenrollment.apple.com" >> "$hosts_file"
		grep -q "iprofiles.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 iprofiles.apple.com" >> "$hosts_file"

		success "MDM domains blocked in hosts file"
		echo ""

		# Remove configuration profiles
		info "Configuring MDM bypass settings..."

		config_path="$system_path/var/db/ConfigurationProfiles/Settings"

		# Create config directory if it doesn't exist
		if [ ! -d "$config_path" ]; then
			if mkdir -p "$config_path" >/dev/null 2>&1; then
				success "Created configuration directory"
			else
				warn "Could not create configuration directory"
			fi
		fi

		# Mark setup as done
		touch "$data_path/private/var/db/.AppleSetupDone" >/dev/null 2>&1 && success "Marked setup as complete" || warn "Could not mark setup as complete"

		# Remove activation records
		rm -rf "$config_path/.cloudConfigHasActivationRecord" >/dev/null 2>&1 && success "Removed activation record" || info "No activation record to remove"
		rm -rf "$config_path/.cloudConfigRecordFound" >/dev/null 2>&1 && success "Removed cloud config record" || info "No cloud config record to remove"

		# Create bypass markers
		touch "$config_path/.cloudConfigProfileInstalled" >/dev/null 2>&1 && success "Created profile installed marker" || warn "Could not create profile marker"
		touch "$config_path/.cloudConfigRecordNotFound" >/dev/null 2>&1 && success "Created record not found marker" || warn "Could not create not found marker"

		echo ""
		echo -e "${GRN}╔═══════════════════════════════════════════════╗${NC}"
		echo -e "${GRN}║       MDM Bypass Completed Successfully!     ║${NC}"
		echo -e "${GRN}╚═══════════════════════════════════════════════╝${NC}"
		echo ""
		echo -e "${CYAN}Next steps:${NC}"
		echo -e "  1. Close this terminal window"
		echo -e "  2. Reboot your Mac"
		echo -e "  3. Login with username: ${YEL}$username${NC} and password: ${YEL}$passw${NC}"
		echo ""
		break
		;;
	"Reboot & Exit")
		echo ""
		info "Rebooting system..."
		reboot
		break
		;;
	*)
		echo -e "${RED}Invalid option $REPLY${NC}"
		;;
	esac
done
