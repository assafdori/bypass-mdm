#!/bin/bash

# Define color codes
RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
PUR='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

VOLUMES_ROOT="${VOLUMES_ROOT:-/Volumes}"
DISKUTIL_BIN="${DISKUTIL_BIN:-diskutil}"
PLISTBUDDY_BIN="${PLISTBUDDY_BIN:-/usr/libexec/PlistBuddy}"
PLUTIL_BIN="${PLUTIL_BIN:-plutil}"

requested_system_volume=""
requested_data_volume=""
require_external=false
validate_only=false
demo_mode=false
target_volume_group_id=""
SYSTEM_VOLUME_CANDIDATES=()
SYSTEM_VOLUME_LABELS=()
MENU_OPTIONS=()
SELECTED_MENU_INDEX=0
MENU_ALLOW_BACK=false
MENU_WENT_BACK=false

# Error handling function
error_exit() {
	echo -e "${RED}ERROR: $1${NC}" >&2
	exit 1
}

# Warning function
warn() {
	echo -e "${YEL}WARNING: $1${NC}"
}

# Success function
success() {
	echo -e "${GRN}✓ $1${NC}"
}

# Info function
info() {
	echo -e "${BLU}ℹ $1${NC}"
}

usage() {
	cat <<'EOF'
Usage: bypass-mdm-v2.sh [options]

Options:
  --system-volume NAME  Target macOS system volume name (interactive menu if omitted)
  --data-volume NAME    Target macOS data volume name
  --require-external    Refuse to operate unless both volumes are external
  --validate-only       Validate the target without changing any files
  --demo                Preview the complete UI with simulated data and no system access
  -h, --help            Show this help

Example:
  ./bypass-mdm-v2.sh \
    --system-volume "GoldenGate" \
    --data-volume "GoldenGate - Data" \
    --require-external
EOF
}

validate_volume_name() {
	local volume_name="$1"

	if [ -z "$volume_name" ]; then
		echo "Volume name cannot be empty"
		return 1
	fi

	case "$volume_name" in
	"." | ".." | */* | *$'\n'* | *$'\r'*)
		echo "Volume name must be a direct child of $VOLUMES_ROOT"
		return 1
		;;
	esac

	return 0
}

parse_arguments() {
	while [ $# -gt 0 ]; do
		case "$1" in
		--system-volume)
			[ $# -ge 2 ] || error_exit "--system-volume requires a volume name"
			requested_system_volume="$2"
			shift 2
			;;
		--data-volume)
			[ $# -ge 2 ] || error_exit "--data-volume requires a volume name"
			requested_data_volume="$2"
			shift 2
			;;
		--require-external)
			require_external=true
			shift
			;;
		--validate-only)
			validate_only=true
			shift
			;;
		--demo)
			demo_mode=true
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			error_exit "Unknown option: $1"
			;;
		esac
	done

	if [ "$demo_mode" = true ] && { [ -n "$requested_system_volume" ] || [ -n "$requested_data_volume" ] || [ "$validate_only" = true ]; }; then
		error_exit "--demo cannot be combined with --system-volume, --data-volume, or --validate-only"
	fi
}

disk_info_value() {
	local volume_path="$1"
	local key="$2"
	local plist_file
	local value

	plist_file=$(mktemp "${TMPDIR:-/tmp}/bypass-mdm-disk-info.XXXXXX") || return 1
	if ! "$DISKUTIL_BIN" info -plist "$volume_path" >"$plist_file" 2>/dev/null; then
		rm -f "$plist_file"
		return 1
	fi

	value=$("$PLISTBUDDY_BIN" -c "Print :$key" "$plist_file" 2>/dev/null)
	local status=$?
	rm -f "$plist_file"

	if [ $status -ne 0 ]; then
		return $status
	fi

	printf '%s\n' "$value"
}

normalize_apfs_device_identifier() {
	local device_identifier="$1"
	local is_snapshot="$2"

	if [ "$is_snapshot" = "true" ] || [ "$is_snapshot" = "yes" ] || [ "$is_snapshot" = "Yes" ] || [ "$is_snapshot" = "1" ]; then
		device_identifier="${device_identifier%s[0-9]*}"
	fi

	printf '%s\n' "$device_identifier"
}

apfs_volume_role() {
	local volume_path="$1"
	local device_identifier
	local is_snapshot
	local plist_file
	local container_count
	local group_count
	local volume_count
	local container_index=0
	local group_index
	local volume_index
	local plist_device
	local plist_role

	device_identifier=$(disk_info_value "$volume_path" DeviceIdentifier) || return 1
	is_snapshot=$(disk_info_value "$volume_path" APFSSnapshot 2>/dev/null) || is_snapshot="false"
	device_identifier=$(normalize_apfs_device_identifier "$device_identifier" "$is_snapshot")

	plist_file=$(mktemp "${TMPDIR:-/tmp}/bypass-mdm-volume-groups.XXXXXX") || return 1
	if ! "$DISKUTIL_BIN" apfs listVolumeGroups -plist >"$plist_file" 2>/dev/null; then
		rm -f "$plist_file"
		return 1
	fi

	container_count=$("$PLUTIL_BIN" -extract Containers raw -o - "$plist_file" 2>/dev/null) || {
		rm -f "$plist_file"
		return 1
	}

	while [ "$container_index" -lt "$container_count" ]; do
		group_count=$("$PLUTIL_BIN" -extract "Containers.$container_index.VolumeGroups" raw -o - "$plist_file" 2>/dev/null) || group_count=0
		group_index=0
		while [ "$group_index" -lt "$group_count" ]; do
			volume_count=$("$PLUTIL_BIN" -extract "Containers.$container_index.VolumeGroups.$group_index.Volumes" raw -o - "$plist_file" 2>/dev/null) || volume_count=0
			volume_index=0
			while [ "$volume_index" -lt "$volume_count" ]; do
				plist_device=$("$PLUTIL_BIN" -extract "Containers.$container_index.VolumeGroups.$group_index.Volumes.$volume_index.DeviceIdentifier" raw -o - "$plist_file" 2>/dev/null) || plist_device=""
				if [ "$plist_device" = "$device_identifier" ]; then
					plist_role=$("$PLUTIL_BIN" -extract "Containers.$container_index.VolumeGroups.$group_index.Volumes.$volume_index.Role" raw -o - "$plist_file" 2>/dev/null) || plist_role=""
					rm -f "$plist_file"
					printf '%s\n' "$plist_role"
					[ -n "$plist_role" ]
					return
				fi
				volume_index=$((volume_index + 1))
			done
			group_index=$((group_index + 1))
		done
		container_index=$((container_index + 1))
	done

	rm -f "$plist_file"
	return 1
}

is_apfs_system_volume() {
	[ "$(apfs_volume_role "$1" 2>/dev/null)" = "System" ]
}

# Validation function for username
validate_username() {
	local username="$1"

	# Check if username is empty
	if [ -z "$username" ]; then
		echo "Username cannot be empty"
		return 1
	fi

	# Check length (1-31 characters for macOS)
	if [ ${#username} -gt 31 ]; then
		echo "Username too long (max 31 characters)"
		return 1
	fi

	# Check for valid characters (alphanumeric, underscore, hyphen)
	if ! [[ "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
		echo "Username can only contain letters, numbers, underscore, and hyphen"
		return 1
	fi

	# Check if starts with letter or underscore
	if ! [[ "$username" =~ ^[a-zA-Z_] ]]; then
		echo "Username must start with a letter or underscore"
		return 1
	fi

	return 0
}

# Validation function for password
validate_password() {
	local password="$1"

	# Check if password is empty
	if [ -z "$password" ]; then
		echo "Password cannot be empty"
		return 1
	fi

	# Check minimum length (macOS allows any length, but recommend 4+)
	if [ ${#password} -lt 4 ]; then
		echo "Password too short (minimum 4 characters recommended)"
		return 1
	fi

	return 0
}

# Check if user already exists
check_user_exists() {
	local dscl_path="$1"
	local username="$2"

	if [ "$demo_mode" = true ]; then
		return 1
	fi

	if dscl -f "$dscl_path" localhost -read "/Local/Default/Users/$username" 2>/dev/null; then
		return 0 # User exists
	else
		return 1 # User doesn't exist
	fi
}

# Find available UID
find_available_uid() {
	local dscl_path="$1"
	local uid=501

	if [ "$demo_mode" = true ]; then
		echo "501"
		return 0
	fi

	# Check UIDs from 501-599
	while [ $uid -lt 600 ]; do
		if ! dscl -f "$dscl_path" localhost -search /Local/Default/Users UniqueID $uid 2>/dev/null | grep -q "UniqueID"; then
			echo $uid
			return 0
		fi
		uid=$((uid + 1))
	done

	echo "501" # Default fallback
	return 1
}

discover_system_volumes() {
	local volume_path

	SYSTEM_VOLUME_CANDIDATES=()
	SYSTEM_VOLUME_LABELS=()
	if [ "$demo_mode" = true ]; then
		if [ "$require_external" != true ]; then
			SYSTEM_VOLUME_CANDIDATES+=("Macintosh HD")
			SYSTEM_VOLUME_LABELS+=("Internal")
		fi
		SYSTEM_VOLUME_CANDIDATES+=("GoldenGate")
		SYSTEM_VOLUME_LABELS+=("External")
		return
	fi

	for volume_path in "$VOLUMES_ROOT"/*; do
		[ ! -L "$volume_path" ] || continue
		[ -d "$volume_path/System/Library/CoreServices" ] || continue
		is_apfs_system_volume "$volume_path" || continue
		SYSTEM_VOLUME_CANDIDATES+=("$(basename "$volume_path")")
		SYSTEM_VOLUME_LABELS+=("$(volume_location_label "$volume_path")")
	done

	if [ "${#SYSTEM_VOLUME_CANDIDATES[@]}" -eq 0 ]; then
		error_exit "No mounted macOS system volumes were found under $VOLUMES_ROOT"
	fi
}

volume_location_label() {
	local volume_path="$1"
	local internal_value

	if [ "$demo_mode" = true ]; then
		case "$volume_path" in
		*GoldenGate) printf 'External\n' ;;
		*) printf 'Internal\n' ;;
		esac
		return
	fi

	if is_external_volume "$volume_path"; then
		printf 'External\n'
		return
	fi

	internal_value=$(disk_info_value "$volume_path" Internal 2>/dev/null) || internal_value=""
	case "$internal_value" in
	true | yes | Yes | 1) printf 'Internal\n' ;;
	*) printf 'Unknown\n' ;;
	esac
}

use_arrow_menu() {
	if [ "${BYPASS_MDM_FORCE_ARROW_MENU:-0}" = "1" ]; then
		return 0
	fi

	[ -t 0 ] && [ "${TERM:-dumb}" != "dumb" ]
}

restore_terminal_cursor() {
	printf '\033[?25h'
}

render_arrow_menu() {
	local selected_index="$1"
	local title="$2"
	local instruction="$3"
	local redraw="${4:-false}"
	local index=0
	local menu_line_count

	menu_line_count=$((${#MENU_OPTIONS[@]} + 3))

	if [ "$redraw" = true ]; then
		printf '\033[%dA' "$menu_line_count"
	fi
	printf '\r\033[2K%s\n' "$title"
	printf '\r\033[2K%s\n' "$instruction"
	printf '\r\033[2K\n'
	while [ "$index" -lt "${#MENU_OPTIONS[@]}" ]; do
		if [ "$index" -eq "$selected_index" ]; then
			printf '\r\033[2K \033[7m> %s\033[0m\n' "${MENU_OPTIONS[$index]}"
		else
			printf '\r\033[2K   %s\n' "${MENU_OPTIONS[$index]}"
		fi
		index=$((index + 1))
	done
}

choose_with_arrow_menu() {
	local title="$1"
	local instruction="$2"
	local selected_index=0
	local key
	local key_tail
	local option_count="${#MENU_OPTIONS[@]}"
	local menu_rendered=false

	printf '\033[?25l'
	trap 'restore_terminal_cursor; exit 130' INT TERM
	trap 'restore_terminal_cursor' EXIT

	while true; do
		render_arrow_menu "$selected_index" "$title" "$instruction" "$menu_rendered"
		menu_rendered=true
		key=""
		if ! IFS= read -r -s -n 1 key; then
			restore_terminal_cursor
			trap - INT TERM EXIT
			error_exit "Could not read the menu selection"
		fi

		case "$key" in
		$'\033')
			key_tail=""
			if ! IFS= read -r -s -n 2 -t 1 key_tail; then
				if [ "$MENU_ALLOW_BACK" = true ]; then
					MENU_WENT_BACK=true
					restore_terminal_cursor
					trap - INT TERM EXIT
					printf '\n'
					return 2
				fi
				continue
			fi
			case "$key_tail" in
			"[A")
				if [ "$selected_index" -eq 0 ]; then
					selected_index=$((option_count - 1))
				else
					selected_index=$((selected_index - 1))
				fi
				;;
			"[B") selected_index=$(((selected_index + 1) % option_count)) ;;
			esac
			;;
		"")
			if [ "$MENU_ALLOW_BACK" = true ] && [ "$selected_index" -eq "$((option_count - 1))" ]; then
				MENU_WENT_BACK=true
				restore_terminal_cursor
				trap - INT TERM EXIT
				printf '\n'
				return 2
			fi
			SELECTED_MENU_INDEX="$selected_index"
			restore_terminal_cursor
			trap - INT TERM EXIT
			printf '\n'
			return
			;;
		esac
	done
}

choose_with_numbered_menu() {
	local title="$1"
	local selection
	local selected_index
	local index=0

	printf '%s\n' "$title"
	while [ "$index" -lt "${#MENU_OPTIONS[@]}" ]; do
		printf '  %d) %s\n' "$((index + 1))" "${MENU_OPTIONS[$index]}"
		index=$((index + 1))
	done
	echo ""

	while true; do
		if ! read -r -p "Select an option [1-${#MENU_OPTIONS[@]}]: " selection; then
			error_exit "Could not read the menu selection"
		fi

		case "$selection" in
		[1-9] | [1-9][0-9]*) ;;
		*)
			warn "Enter one of the listed numbers"
			continue
			;;
		esac

		if [ "$selection" -gt "${#MENU_OPTIONS[@]}" ]; then
			warn "Selection must be between 1 and ${#MENU_OPTIONS[@]}"
			continue
		fi

		selected_index=$((selection - 1))
		if [ "$MENU_ALLOW_BACK" = true ] && [ "$selected_index" -eq "$((${#MENU_OPTIONS[@]} - 1))" ]; then
			MENU_WENT_BACK=true
			return 2
		fi
		SELECTED_MENU_INDEX="$selected_index"
		return
	done
}

choose_menu_option() {
	local title="$1"
	local instruction="$2"
	shift 2

	MENU_WENT_BACK=false
	MENU_OPTIONS=("$@")
	if [ "$MENU_ALLOW_BACK" = true ]; then
		MENU_OPTIONS+=("← Back")
	fi
	[ "${#MENU_OPTIONS[@]}" -gt 0 ] || error_exit "Menu has no options"

	if use_arrow_menu; then
		choose_with_arrow_menu "$title" "$instruction"
	else
		choose_with_numbered_menu "$title"
	fi
}

choose_menu_option_with_back() {
	local menu_status

	MENU_ALLOW_BACK=true
	choose_menu_option "$@"
	menu_status=$?
	MENU_ALLOW_BACK=false
	return "$menu_status"
}

prompt_for_system_volume() {
	local index=0
	local menu_entries=()

	discover_system_volumes
	while [ "$index" -lt "${#SYSTEM_VOLUME_CANDIDATES[@]}" ]; do
		menu_entries+=("${SYSTEM_VOLUME_CANDIDATES[$index]} [${SYSTEM_VOLUME_LABELS[$index]}]")
		index=$((index + 1))
	done

	choose_menu_option \
		"Mounted macOS system volumes:" \
		"Use Up/Down arrows to choose a macOS system volume, then press Enter." \
		"${menu_entries[@]}"
	requested_system_volume="${SYSTEM_VOLUME_CANDIDATES[$SELECTED_MENU_INDEX]}"
}

find_matching_data_volume() {
	local selected_system_path="$VOLUMES_ROOT/$requested_system_volume"
	local system_group_id
	local candidate_group_id
	local candidate_path
	local candidate_name
	local matching_data_volume=""
	local match_count=0

	if [ "$demo_mode" = true ]; then
		case "$requested_system_volume" in
		"Macintosh HD") requested_data_volume="Macintosh HD - Data" ;;
		"GoldenGate") requested_data_volume="GoldenGate - Data" ;;
		*) error_exit "Unknown simulated System volume: $requested_system_volume" ;;
		esac
		return
	fi

	[ -d "$selected_system_path" ] || error_exit "System volume is not mounted: $selected_system_path"
	system_group_id=$(disk_info_value "$selected_system_path" APFSVolumeGroupID) || error_exit "Could not read the APFS volume group for: $selected_system_path"

	for candidate_path in "$VOLUMES_ROOT"/*; do
		[ "$candidate_path" != "$selected_system_path" ] || continue
		[ ! -L "$candidate_path" ] || continue
		[ -d "$candidate_path/private/var/db/dslocal/nodes/Default" ] || continue
		[ "$(apfs_volume_role "$candidate_path" 2>/dev/null)" = "Data" ] || continue
		candidate_group_id=$(disk_info_value "$candidate_path" APFSVolumeGroupID) || continue
		[ "$candidate_group_id" = "$system_group_id" ] || continue

		candidate_name=$(basename "$candidate_path")
		matching_data_volume="$candidate_name"
		match_count=$((match_count + 1))
	done

	if [ "$match_count" -eq 0 ]; then
		error_exit "Could not find a mounted Data volume matching system volume '$requested_system_volume'"
	fi

	if [ "$match_count" -gt 1 ]; then
		error_exit "Multiple Data volumes match '$requested_system_volume'. Specify --data-volume explicitly."
	fi

	requested_data_volume="$matching_data_volume"
}

resolve_target_volumes() {
	local validation_message

	if [ -z "$requested_system_volume" ] && [ -n "$requested_data_volume" ]; then
		case "$requested_data_volume" in
		*" - Data") requested_system_volume="${requested_data_volume% - Data}" ;;
		*) error_exit "Specify --system-volume when the data volume name does not end with ' - Data'" ;;
		esac
	fi

	if [ -z "$requested_system_volume" ]; then
		prompt_for_system_volume
	fi

	if ! validation_message=$(validate_volume_name "$requested_system_volume"); then
		error_exit "Invalid system volume: $validation_message"
	fi

	if [ -z "$requested_data_volume" ]; then
		find_matching_data_volume
	fi

	if ! validation_message=$(validate_volume_name "$requested_data_volume"); then
		error_exit "Invalid data volume: $validation_message"
	fi

	if [ "$requested_system_volume" = "$requested_data_volume" ]; then
		error_exit "System and data volumes must be different"
	fi

	system_volume="$requested_system_volume"
	data_volume="$requested_data_volume"
}

is_external_volume() {
	local internal_value
	local external_device_value

	internal_value=$(disk_info_value "$1" Internal) || return 1
	case "$internal_value" in
	false | no | No | 0) ;;
	*) return 1 ;;
	esac

	external_device_value=$(disk_info_value "$1" RemovableMediaOrExternalDevice) || return 1
	case "$external_device_value" in
	true | yes | Yes | 1) return 0 ;;
	*) return 1 ;;
	esac
}

validate_target_volumes() {
	local system_group_id
	local data_group_id
	local system_role
	local data_role

	system_path="$VOLUMES_ROOT/$system_volume"
	data_path="$VOLUMES_ROOT/$data_volume"
	dscl_path="$data_path/private/var/db/dslocal/nodes/Default"

	if [ "$demo_mode" = true ]; then
		case "$system_volume" in
		"Macintosh HD")
			[ "$require_external" != true ] || error_exit "The simulated internal volume is unavailable with --require-external"
			target_volume_group_id="DEMO-INTERNAL-GROUP"
			;;
		"GoldenGate") target_volume_group_id="DEMO-EXTERNAL-GROUP" ;;
		*) error_exit "Unknown simulated System volume: $system_volume" ;;
		esac
		return
	fi

	[ -d "$system_path" ] || error_exit "System volume is not mounted: $system_path"
	[ -d "$data_path" ] || error_exit "Data volume is not mounted: $data_path"
	[ -d "$system_path/System/Library/CoreServices" ] || error_exit "Target does not look like a macOS system volume: $system_path"
	[ -d "$dscl_path" ] || error_exit "Directory Services path does not exist: $dscl_path"

	system_role=$(apfs_volume_role "$system_path") || error_exit "Could not read the APFS role for: $system_path"
	data_role=$(apfs_volume_role "$data_path") || error_exit "Could not read the APFS role for: $data_path"
	[ "$system_role" = "System" ] || error_exit "Selected system volume does not have the APFS System role: $system_path"
	[ "$data_role" = "Data" ] || error_exit "Selected data volume does not have the APFS Data role: $data_path"

	system_group_id=$(disk_info_value "$system_path" APFSVolumeGroupID) || error_exit "Could not read the APFS volume group for: $system_path"
	data_group_id=$(disk_info_value "$data_path" APFSVolumeGroupID) || error_exit "Could not read the APFS volume group for: $data_path"

	if [ -z "$system_group_id" ] || [ "$system_group_id" != "$data_group_id" ]; then
		error_exit "Selected System and Data volumes are not in the same APFS volume group"
	fi

	if [ -n "$target_volume_group_id" ] && [ "$target_volume_group_id" != "$system_group_id" ]; then
		error_exit "The selected APFS volume group changed while the script was running"
	fi
	target_volume_group_id="$system_group_id"

	if [ "$require_external" = true ]; then
		is_external_volume "$system_path" || error_exit "System volume is not reported as external: $system_path"
		is_external_volume "$data_path" || error_exit "Data volume is not reported as external: $data_path"
	fi
}

reset_target_selection() {
	requested_system_volume=""
	requested_data_volume=""
	system_volume=""
	data_volume=""
	system_path=""
	data_path=""
	dscl_path=""
	target_volume_group_id=""
}

display_selected_target() {
	echo ""
	echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
	echo -e "${CYAN}║  Bypass MDM By Assaf Dori (assafdori.com)   ║${NC}"
	echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
	echo ""
	if [ "$demo_mode" = true ]; then
		echo -e "${PUR}DEMO MODE - NO CHANGES WILL BE MADE${NC}"
		echo ""
	fi
	success "System Volume: $system_volume"
	success "Data Volume: $data_volume"
	echo ""
}

collect_account_information() {
	local validation_msg
	local menu_status

	echo -e "${CYAN}Creating Temporary Admin User${NC}"
	echo -e "${NC}Press Enter to use defaults (recommended)${NC}"

	read -p "Enter Temporary Fullname (Default is 'Apple'): " realName
	realName="${realName:=Apple}"

	while true; do
		read -p "Enter Temporary Username (Default is 'Apple'): " username
		username="${username:=Apple}"

		if ! validation_msg=$(validate_username "$username"); then
			warn "$validation_msg"
			echo -e "${YEL}Please try again or press Ctrl+C to exit${NC}"
			continue
		fi

		if ! check_user_exists "$dscl_path" "$username"; then
			break
		fi

		warn "User '$username' already exists in the system"
		choose_menu_option_with_back "User already exists" "Choose how to continue. Esc returns to username entry." \
			"Use a different username" \
			"Continue with the existing username"
		menu_status=$?
		if [ "$menu_status" -eq 2 ] || [ "$SELECTED_MENU_INDEX" -eq 0 ]; then
			continue
		fi

		warn "Continuing with existing user '$username' (may cause conflicts)"
		break
	done

	while true; do
		read -p "Enter Temporary Password (Default is '1234'): " passw
		passw="${passw:=1234}"

		if validation_msg=$(validate_password "$passw"); then
			break
		fi

		warn "$validation_msg"
		echo -e "${YEL}Please try again or press Ctrl+C to exit${NC}"
	done
}

prepare_available_uid() {
	info "Checking for available UID..."
	if available_uid=$(find_available_uid "$dscl_path"); then
		if [ "$available_uid" != "501" ]; then
			info "UID 501 is in use, using UID $available_uid instead"
		fi
	else
		available_uid="501"
	fi
	success "Using UID: $available_uid"
}

print_confirmation_summary() {
	local location_label
	local account_status="New account"
	local action_label="Bypass MDM from Recovery"

	location_label=$(volume_location_label "$system_path")
	if check_user_exists "$dscl_path" "$username"; then
		account_status="Existing account will be updated"
	fi
	if [ "$demo_mode" = true ]; then
		action_label="Demo Preview Only"
		account_status="Simulated new account"
	fi

	echo ""
	echo -e "${CYAN}════════════ Final Confirmation ════════════${NC}"
	echo ""
	echo "Action: $action_label"
	echo "System Volume: $system_volume"
	echo "System Path: $system_path"
	echo "Data Volume: $data_volume"
	echo "Data Path: $data_path"
	echo "Target Location: $location_label"
	echo "APFS Volume Group: $target_volume_group_id"
	echo "Directory Services: $dscl_path"
	echo ""
	echo "Full Name: $realName"
	echo "Username: $username"
	echo "Password: $passw"
	echo "Account Status: $account_status"
	echo "UID: $available_uid"
	echo "Primary Group ID: 20"
	echo "Shell: /bin/zsh"
	echo "Home Directory: /Users/$username"
	echo "Admin Group: Yes"
	echo ""
	echo "Planned Changes:"
	echo "  - Create or update the local administrator account"
	echo "  - Create the user home directory on the selected Data volume"
	echo "  - Add MDM enrollment domains to the selected Data volume hosts file"
	echo "  - Mark Setup Assistant as complete on the selected Data volume"
	echo "  - Update local cloud configuration markers on the selected Data volume"
	echo ""
	if [ "$demo_mode" = true ]; then
		info "Demo confirmation only; no commands or file changes will run."
	else
		warn "After confirmation, these changes cannot be taken back by this wizard."
	fi
	echo ""
}

confirm_bypass_settings() {
	local menu_status

	print_confirmation_summary
	choose_menu_option_with_back "Review all settings" "Use Up/Down and Enter. Esc returns to account editing." \
		"Confirm and Run" \
		"Edit Account Information" \
		"Change System Volume" \
		"Back to Action Menu" \
		"Exit Without Changes"
	menu_status=$?

	if [ "$menu_status" -eq 2 ]; then
		return 10
	fi

	case "$SELECTED_MENU_INDEX" in
	0) return 0 ;;
	1) return 10 ;;
	2) return 11 ;;
	3) return 12 ;;
	4) return 13 ;;
	esac

	return 13
}

execute_bypass() {
	local user_home
	local hosts_file
	local config_path

	echo ""
	echo -e "${YEL}═══════════════════════════════════════${NC}"
	echo -e "${YEL}  Starting MDM Bypass Process${NC}"
	echo -e "${YEL}═══════════════════════════════════════${NC}"
	echo ""

	info "Revalidating target volume pair before writing..."
	validate_target_volumes
	success "Target volume pair is unchanged"
	info "Changes are now being written and can no longer be taken back."
	echo ""

	info "Creating user account: $username"
	if ! dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" 2>/dev/null; then
		error_exit "Failed to create user account"
	fi

	dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh" || warn "Failed to set user shell"
	dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName" || warn "Failed to set real name"
	dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "$available_uid" || warn "Failed to set UID"
	dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20" || warn "Failed to set GID"

	user_home="$data_path/Users/$username"
	if [ ! -d "$user_home" ]; then
		if mkdir -p "$user_home" 2>/dev/null; then
			success "Created user home directory"
		else
			error_exit "Failed to create user home directory: $user_home"
		fi
	else
		warn "User home directory already exists: $user_home"
	fi

	dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username" || warn "Failed to set home directory"

	if ! dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw" 2>/dev/null; then
		error_exit "Failed to set user password"
	fi

	if ! dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership "$username" 2>/dev/null; then
		error_exit "Failed to add user to admin group"
	fi

	success "User account created successfully"
	echo ""

	info "Blocking MDM enrollment domains..."
	hosts_file="$data_path/private/etc/hosts"
	if [ ! -f "$hosts_file" ]; then
		warn "Hosts file does not exist, creating it"
		touch "$hosts_file" || error_exit "Failed to create hosts file"
	fi

	grep -q "deviceenrollment.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 deviceenrollment.apple.com" >>"$hosts_file"
	grep -q "mdmenrollment.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 mdmenrollment.apple.com" >>"$hosts_file"
	grep -q "iprofiles.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 iprofiles.apple.com" >>"$hosts_file"
	success "MDM domains blocked in hosts file"
	echo ""

	info "Configuring MDM bypass settings..."
	config_path="$data_path/private/var/db/ConfigurationProfiles/Settings"
	if [ ! -d "$config_path" ]; then
		if mkdir -p "$config_path" 2>/dev/null; then
			success "Created configuration directory"
		else
			warn "Could not create configuration directory"
		fi
	fi

	touch "$data_path/private/var/db/.AppleSetupDone" 2>/dev/null && success "Marked setup as complete" || warn "Could not mark setup as complete"
	rm -rf "$config_path/.cloudConfigHasActivationRecord" 2>/dev/null && success "Removed activation record" || info "No activation record to remove"
	rm -rf "$config_path/.cloudConfigRecordFound" 2>/dev/null && success "Removed cloud config record" || info "No cloud config record to remove"
	touch "$config_path/.cloudConfigProfileInstalled" 2>/dev/null && success "Created profile installed marker" || warn "Could not create profile marker"
	touch "$config_path/.cloudConfigRecordNotFound" 2>/dev/null && success "Created record not found marker" || warn "Could not create not found marker"

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
}

execute_demo() {
	echo ""
	echo -e "${PUR}═════════════════════════════════════${NC}"
	echo -e "${PUR}  Demo Execution Preview${NC}"
	echo -e "${PUR}═════════════════════════════════════${NC}"
	echo ""
	info "Would create or update administrator account: $username"
	info "Would create home directory: $data_path/Users/$username"
	info "Would update MDM enrollment entries on: $system_volume"
	info "Would update setup and cloud configuration markers"
	echo ""
	success "Demo completed; no changes were made."
	echo -e "Login preview - username: ${YEL}$username${NC}, password: ${YEL}$passw${NC}"
	echo ""
}

run_bypass_wizard() {
	local confirmation_status

	while true; do
		collect_account_information
		echo ""
		prepare_available_uid

		confirm_bypass_settings
		confirmation_status=$?
		case "$confirmation_status" in
		0)
			if [ "$demo_mode" = true ]; then
				execute_demo
			else
				execute_bypass
			fi
			return 0
			;;
		10) continue ;;
		11) return 11 ;;
		12) return 12 ;;
		13) return 13 ;;
		esac
	done
}

parse_arguments "$@"

if [ "$demo_mode" = true ]; then
	echo -e "${PUR}DEMO MODE - NO CHANGES WILL BE MADE${NC}"
	echo "All volumes, accounts, IDs, and operations shown below are simulated."
	echo ""
fi

while true; do
	resolve_target_volumes
	validate_target_volumes
	display_selected_target

	if [ "$validate_only" = true ]; then
		success "Target volume pair validated; no changes were made"
		exit 0
	fi

	if [ "$demo_mode" != true ] && [ "$(id -u)" -ne 0 ]; then
		error_exit "Run this script as root from macOS Recovery"
	fi

	while true; do
		choose_menu_option_with_back "Choose an action" "Use Up/Down and Enter. Esc returns to volume selection." \
			"Bypass MDM from Recovery" \
			"Reboot & Exit" \
			"Exit Without Changes"
		menu_status=$?

		if [ "$menu_status" -eq 2 ]; then
			reset_target_selection
			break
		fi

		case "$SELECTED_MENU_INDEX" in
		0)
			run_bypass_wizard
			wizard_status=$?
			case "$wizard_status" in
			0) exit 0 ;;
			11)
				reset_target_selection
				break
				;;
			12) continue ;;
			13)
				info "Exited without making changes."
				exit 0
				;;
			esac
			;;
		1)
			choose_menu_option_with_back "Confirm reboot" "Reboot has not started. Esc returns to the action menu." \
				"Reboot Now"
			if [ $? -eq 2 ]; then
				continue
			fi
			if [ "$demo_mode" = true ]; then
				info "Demo reboot selected; no reboot was performed."
			else
				info "Rebooting system..."
				reboot
			fi
			exit 0
			;;
		2)
			info "Exited without making changes."
			exit 0
			;;
		esac
	done
done
