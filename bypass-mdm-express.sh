#!/bin/bash
set -euo pipefail

# bypass-mdm-express.sh — All-in-one MDM tool.
# Put this on an external SSD. Plug into any Mac. Run from Recovery.
#
# What it does:
#   1. Backs up the current state (hosts, config profiles)
#   2. Suppresses MDM enrollment
#   3. Can restore the original state later
#
# Why "express": no curl, no download, no typing URLs.
# Just chmod +x and run. Backup stays on the SSD so you can
# restore whenever you want — take it to Apple, let them
# re-enroll, then restore if needed.
#
# RUN FROM RECOVERY (Apple Silicon: hold Power -> Options ->
# Utilities -> Terminal). Use responsibly.

RED='\033[1;31m'; GRN='\033[1;32m'; BLU='\033[1;34m'; YEL='\033[1;33m'; CYAN='\033[1;36m'; NC='\033[0m'
error_exit() { echo -e "${RED}ERROR: $1${NC}" >&2; exit 1; }
warn()       { echo -e "${YEL}WARNING: $1${NC}" >&2; }
success()    { echo -e "${GRN}\u2713 $1${NC}"; }
info()       { echo -e "${BLU}\u2139 $1${NC}"; }
step()       { echo -e "${CYAN}\u25b8 $1${NC}"; }

PB=/usr/libexec/PlistBuddy

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/.bypass-backup"

# ------------------------------------------------------------------
# Detect and mount the Data volume
# ------------------------------------------------------------------
resolve_data_volume() {
	step "Locating the Data volume by APFS role..."

	local id mount_pt

	id=$(diskutil apfs list 2>/dev/null \
		| awk '/\(Data\)/ && match($0, /disk[0-9]+s[0-9]+/) {print substr($0, RSTART, RLENGTH); exit}')

	if [ -z "$id" ] || ! diskutil info "/dev/$id" >/dev/null 2>&1; then
		id=$(diskutil list 2>/dev/null \
			| awk '/[[:space:]]Data[[:space:]]/{for(i=1;i<=NF;i++) if($i ~ /^disk[0-9]+s[0-9]+$/) v=$i} END{print v}')
	fi

	if [ -z "$id" ] || ! diskutil info "/dev/$id" >/dev/null 2>&1; then
		warn "Could not auto-detect the Data volume."
		diskutil list >&2
		echo ""
		read -p "Type the Data volume identifier (e.g. disk3s1): " id </dev/tty
		id="${id#/dev/}"
	fi

	[ -n "$id" ] || error_exit "No Data volume identifier provided."
	local data_dev="/dev/$id"
	diskutil info "$data_dev" >/dev/null 2>&1 || error_exit "Not a valid disk: $data_dev"
	info "Data volume device: $data_dev"

	_mount_point() { diskutil info "$data_dev" 2>/dev/null | awk -F': *' '/Mount Point/{print $2}' | sed 's/[[:space:]]*$//'; }

	mount_pt=$(_mount_point)

	if [ -z "$mount_pt" ] || [ ! -d "$mount_pt" ]; then
		info "Data volume not mounted — mounting..."
		diskutil mount "$data_dev" 2>/dev/null || true
		mount_pt=$(_mount_point)
	fi

	if [ -z "$mount_pt" ] || [ ! -d "$mount_pt" ]; then
		warn "Data volume is FileVault-locked — need to unlock."
		echo -e "${YEL}Enter the password of an account on this Mac (or FileVault recovery key):${NC}" >&2
		diskutil apfs unlockVolume "$data_dev" 2>/dev/null \
			|| error_exit "Failed to unlock Data volume."
		mount_pt=$(_mount_point)
	fi

	[ -d "$mount_pt" ] || error_exit "Data volume mount point not found."
	[ -d "$mount_pt/private/var/db/dslocal/nodes/Default" ] \
		|| error_exit "This does not look like a macOS Data volume (no dslocal node)."

	success "Data volume mounted at: $mount_pt"
	echo "$mount_pt"
}

# ------------------------------------------------------------------
# Backup original state to SSD
# ------------------------------------------------------------------
backup_state() {
	local dm="$1"
	mkdir -p "$BACKUP_DIR"
	step "Saving backup to $BACKUP_DIR"

	if [ -f "$dm/private/etc/hosts" ]; then
		cp "$dm/private/etc/hosts" "$BACKUP_DIR/hosts.backup"
	fi
	if [ -d "$dm/private/var/db/ConfigurationProfiles/Settings" ]; then
		mkdir -p "$BACKUP_DIR/ConfigurationProfiles"
		cp -r "$dm/private/var/db/ConfigurationProfiles/Settings/"* "$BACKUP_DIR/ConfigurationProfiles/" 2>/dev/null || true
	fi
	if [ -f "$dm/private/var/db/com.apple.xpc.launchd/disabled.plist" ]; then
		cp "$dm/private/var/db/com.apple.xpc.launchd/disabled.plist" "$BACKUP_DIR/disabled.plist.backup" 2>/dev/null || true
	fi
	date +%Y-%m-%d_%H-%M-%S > "$BACKUP_DIR/timestamp"
	echo "$dm" > "$BACKUP_DIR/data_volume_path"
	success "Backup saved: $(cat "$BACKUP_DIR/timestamp")"
}

# ------------------------------------------------------------------
# Restore original state from SSD backup
# ------------------------------------------------------------------
restore_state() {
	if [ ! -f "$BACKUP_DIR/timestamp" ]; then
		error_exit "No backup found at $BACKUP_DIR"
	fi

	local dm
	if [ -f "$BACKUP_DIR/data_volume_path" ]; then
		dm=$(cat "$BACKUP_DIR/data_volume_path")
		if [ ! -d "$dm/private/var" ]; then
			warn "Saved Data volume path ($dm) not available. Re-detecting..."
			dm=$(resolve_data_volume)
		fi
	else
		dm=$(resolve_data_volume)
	fi

	step "Restoring from backup ($(cat "$BACKUP_DIR/timestamp"))"
	echo -e "${YEL}Target Data volume: $dm${NC}"

	# Restore hosts
	if [ -f "$BACKUP_DIR/hosts.backup" ]; then
		cp "$BACKUP_DIR/hosts.backup" "$dm/private/etc/hosts"
		success "hosts restored"
	fi

	# Restore config profiles markers
	if [ -d "$BACKUP_DIR/ConfigurationProfiles" ]; then
		local cfg="$dm/private/var/db/ConfigurationProfiles/Settings"
		mkdir -p "$cfg"
		cp -r "$BACKUP_DIR/ConfigurationProfiles/"* "$cfg/" 2>/dev/null || true
		success "config profiles restored"
	fi

	# Restore launchd disabled.plist
	if [ -f "$BACKUP_DIR/disabled.plist.backup" ]; then
		local ldp="$dm/private/var/db/com.apple.xpc.launchd/disabled.plist"
		mkdir -p "$(dirname "$ldp")"
		cp "$BACKUP_DIR/disabled.plist.backup" "$ldp"
		success "launchd override restored"
	fi

	# Remove enrollment block from hosts (the lines we added)
	if [ -f "$dm/private/etc/hosts" ]; then
		sed -i '' '/# Added by bypass-mdm/d' "$dm/private/etc/hosts" 2>/dev/null || true
	fi

	rm -f "$BACKUP_DIR/data_volume_path"
	rm -f "$BACKUP_DIR/timestamp"
	success "Restore complete"
}

# ------------------------------------------------------------------
# Check if running in Recovery
# ------------------------------------------------------------------
check_recovery() {
	if [ -d "/System/Installation" ] || [ -d "/Volumes/Macintosh HD" ] || [ -d "/Volumes/MacOS" ]; then
		return 0
	fi
	# Check if we're on a recovery volume
	local vol
	vol=$(diskutil info / 2>/dev/null | awk -F': *' '/Volume Name/{print $2}' | xargs)
	case "$vol" in
		"Recovery"*|"macOS Base"*) return 0 ;;
	esac
	return 1
}

# ------------------------------------------------------------------
# Core suppression logic (same across all modes)
# ------------------------------------------------------------------
suppress_enrollment() {
	local dm="$1"

	step "Reading existing DEP record..."
	local mdm_host="" org=""
	local cfg="$dm/private/var/db/ConfigurationProfiles/Settings"
	if [ -f "$cfg/.cloudConfigRecordFound" ]; then
		mdm_host=$(plutil -convert xml1 -o - "$cfg/.cloudConfigRecordFound" 2>/dev/null \
			| grep -ioE 'https?://[a-z0-9._-]+' | sed -E 's#https?://##' \
			| sort -u | grep -viE '(^|\.)apple\.com$' | head -1)
		org=$(plutil -convert xml1 -o - "$cfg/.cloudConfigRecordFound" 2>/dev/null \
			| grep -iA1 OrganizationName | tail -1 | sed -E 's/.*<string>(.*)<\/string>.*/\1/')
		[ -n "$org" ]      && info "Device assigned to: $org"
		[ -n "$mdm_host" ] && info "Org MDM host: $mdm_host"
	else
		info "No DEP activation record found."
	fi
	echo ""

	# Block domains
	step "Blocking enrollment domains..."
	local hosts="$dm/private/etc/hosts"
	[ -f "$hosts" ] || { mkdir -p "$(dirname "$hosts")"; touch "$hosts"; }
	grep -q "Added by bypass-mdm" "$hosts" 2>/dev/null || {
		echo "" >>"$hosts"
		echo "# Added by bypass-mdm — DEP enrollment block" >>"$hosts"
	}
	local domains=(iprofiles.apple.com deviceenrollment.apple.com mdmenrollment.apple.com acmdm.apple.com)
	[ -n "$mdm_host" ] && domains+=("$mdm_host")
	local d
	for d in "${domains[@]}"; do
		grep -qiE "[[:space:]]$d(\$|[[:space:]])" "$hosts" 2>/dev/null && { info "$d already blocked"; continue; }
		printf '0.0.0.0 %s\n::      %s\n' "$d" "$d" >>"$hosts"
		success "blocked $d"
	done
	echo ""

	# Reset markers
	step "Resetting DEP markers..."
	mkdir -p "$cfg"
	rm -f "$cfg/.cloudConfigHasActivationRecord" \
	      "$cfg/.cloudConfigRecordFound" \
	      "$cfg/.cloudConfigTimerCheck" 2>/dev/null
	touch "$cfg/.cloudConfigRecordNotFound" \
	      "$cfg/.cloudConfigProfileInstalled"
	success "Markers reset"

	# Disable daemon via launchd override
	step "Disabling enrollment daemon..."
	local ldp="$dm/private/var/db/com.apple.xpc.launchd/disabled.plist"
	mkdir -p "$(dirname "$ldp")"
	[ -f "$ldp" ] || printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict/></plist>\n' >"$ldp"
	for label in com.apple.ManagedClient.enroll com.apple.mdmclient.daemon.runatboot; do
		$PB -c "Add :$label bool true" "$ldp" 2>/dev/null \
			|| $PB -c "Set :$label true" "$ldp" 2>/dev/null
	done
	success "Daemon disabled"

	# Mark setup as done (for fresh install scenario)
	touch "$dm/private/var/db/.AppleSetupDone" 2>/dev/null || true
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
echo ""
echo -e "${CYAN}==============================================${NC}"
echo -e "${CYAN}   Bypass MDM Express                        ${NC}"
echo -e "${CYAN}   All-in-one: backup + bypass + restore     ${NC}"
echo -e "${CYAN}==============================================${NC}"
echo ""

if ! check_recovery; then
	warn "This script should be run from Recovery mode."
	warn "Restart and hold Power (Apple Silicon) or CMD+R (Intel)."
	echo ""
	read -p "Continue anyway? (y/N): " force
	[[ "$force" =~ ^[Yy]$ ]] || exit 1
fi

data_mount=$(resolve_data_volume)
echo ""

PS3="Choose an option: "
options=(
	"Backup + Bypass MDM (safe, reversible)"
	"Restore original state (from backup)"
	"Check current MDM status"
	"Exit"
)
select opt in "${options[@]}"; do
	case $opt in
	"Backup + Bypass MDM (safe, reversible)")
		echo ""
		backup_state "$data_mount"
		echo ""
		suppress_enrollment "$data_mount"
		echo ""
		echo -e "${GRN}==============================================${NC}"
		echo -e "${GRN}  Done! Backup saved to $BACKUP_DIR${NC}"
		echo -e "${GRN}  To restore: re-run and pick option 2${NC}"
		echo -e "${GRN}  Reboot your Mac now.${NC}"
		echo -e "${GRN}==============================================${NC}"
		break
		;;
	"Restore original state (from backup)")
		echo ""
		restore_state
		echo ""
		echo -e "${GRN}Original state restored. Reboot to apply.${NC}"
		break
		;;
	"Check current MDM status")
		echo ""
		if command -v profiles &>/dev/null; then
			profiles status -type enrollment 2>/dev/null || warn "Could not check enrollment status"
		else
			warn "'profiles' command not available"
		fi
		echo ""
		step "Blocked domains in hosts:"
		if [ -f "$data_mount/private/etc/hosts" ]; then
			grep -iE 'iprofiles|enrollment|mdm|acmdm' "$data_mount/private/etc/hosts" 2>/dev/null || echo "  (none)"
		fi
		echo ""
		step "Existing backup:"
		if [ -f "$BACKUP_DIR/timestamp" ]; then
			echo "  $(cat "$BACKUP_DIR/timestamp")"
		else
			echo "  (none)"
		fi
		break
		;;
	"Exit") exit 0 ;;
	*) echo -e "${RED}Invalid option $REPLY${NC}" ;;
	esac
done
