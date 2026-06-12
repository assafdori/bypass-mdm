#!/bin/bash
set -euo pipefail

# bypass-mdm-v3.sh — DEP/MDM enrollment suppression for macOS, hardened for
# Apple Silicon + Signed System Volume (macOS 11 Big Sur .. 26 Tahoe).
#
# TWO MODES:
#   · Suppress enrollment only  — for a Mac that is ALREADY SET UP and just
#     nags you to enroll. Blocks the enrollment fetch, clears the cached DEP
#     record, and disables the enrollment daemon. Does NOT create any user.
#   · Full bypass               — for a Mac stuck at the Remote Management /
#     Setup Assistant screen. Also creates a temp local admin + .AppleSetupDone
#     so first boot skips Setup Assistant, then runs the same suppression.
#
# WHY v3 EXISTS (what was broken in v1/v2 on modern macOS):
#   1. v1/v2 wrote /etc/hosts and the ConfigurationProfiles markers to the
#      *System* volume. On Apple Silicon the OS boots from a sealed, read-only
#      snapshot; the live /etc/hosts and /var/db/ConfigurationProfiles actually
#      live on the *Data* volume (via /etc -> /private/etc, /var -> /private/var,
#      and the /private firmlink). Those writes never reached the running OS.
#      THIS IS THE MAIN FIX: everything is written to the Data volume.
#   2. FileVault is on by default, so in Recovery the Data volume is LOCKED and
#      not auto-mounted (v2's "Could not detect data volume"). v3 finds it by
#      APFS role and unlocks it.
#   3. Markers alone aren't durable: macOS re-fetches the record from Apple after
#      an update. v3 also blocks iprofiles.apple.com + the org's own MDM host,
#      and disables the enrollment daemon via a launchd override ON THE DATA
#      VOLUME (survives the System-volume reseal an update performs).
#   4. cloudconfigurationd no longer exists on macOS 26 — the work moved to
#      com.apple.ManagedClient.enroll. v3 targets the current daemon names.
#
# HARD LIMIT: this does NOT remove your device from the organization's Apple
# Business/School Manager. The record is keyed to your serial and re-fetched
# whenever the Mac reaches Apple. This only SUPPRESSES enrollment locally; the
# permanent fix is the owning org releasing your serial in ABM. Never run
# `profiles renew`, and avoid Erase All Content & Settings / factory reset.
#
# RUN FROM RECOVERY (Apple Silicon: hold Power -> Options -> Utilities ->
# Terminal). Use responsibly, on devices you own.

RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

error_exit() { echo -e "${RED}ERROR: $1${NC}" >&2; exit 1; }
warn()       { echo -e "${YEL}WARNING: $1${NC}" >&2; }
success()    { echo -e "${GRN}\u2713 $1${NC}"; }
info()       { echo -e "${BLU}\u2139 $1${NC}"; }
step()       { echo -e "${CYAN}\u25b8 $1${NC}"; }

PB=/usr/libexec/PlistBuddy

# ------------------------------------------------------------------
# Input validation
# ------------------------------------------------------------------
validate_username() {
	local u="$1"
	[ -z "$u" ] && { echo "Username cannot be empty" >&2; return 1; }
	[ ${#u} -gt 31 ] && { echo "Username too long (max 31 chars)" >&2; return 1; }
	[[ "$u" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo "Use only letters, numbers, _ and -" >&2; return 1; }
	[[ "$u" =~ ^[a-zA-Z_] ]] || { echo "Must start with a letter or underscore" >&2; return 1; }
	return 0
}

validate_password() {
	[ -z "$1" ] && { echo "Password cannot be empty" >&2; return 1; }
	[ ${#1} -lt 4 ] && { echo "Password too short (min 4 chars)" >&2; return 1; }
	return 0
}

# ------------------------------------------------------------------
# Locate and mount the Data volume by APFS role.
# Multi-strategy: (1) awk regex, (2) literal name, (3) user prompt.
# Fallback chain: mount -> FileVault unlock.
# Echoes the mount point on stdout; all messages go to stderr.
# ------------------------------------------------------------------
resolve_data_volume() {
	step "Locating the Data volume by APFS role..."

	local id mount_pt

	id=$(diskutil apfs list 2>/dev/null \
		| awk '/\(Data\)/ && match($0, /disk[0-9]+s[0-9]+/) {print substr($0, RSTART, RLENGTH); exit}')

	if [ -z "$id" ] || ! diskutil info "/dev/$id" >/dev/null 2>&1; then
		info "Could not identify Data volume by role — trying name-based detection..."
		id=$(diskutil list 2>/dev/null \
			| awk '/[[:space:]]Data[[:space:]]/{for(i=1;i<=NF;i++) if($i ~ /^disk[0-9]+s[0-9]+$/) v=$i} END{print v}')
	fi

	if [ -z "$id" ] || ! diskutil info "/dev/$id" >/dev/null 2>&1; then
		warn "Could not auto-detect the Data volume. Available disks:"
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
			|| error_exit "Failed to unlock Data volume. Re-run with a valid password or recovery key."
		mount_pt=$(_mount_point)
	fi

	[ -d "$mount_pt" ] || error_exit "Data volume mount point not found after mount/unlock."

	if [ ! -d "$mount_pt/private/var/db/dslocal/nodes/Default" ]; then
		error_exit "This does not look like a macOS Data volume (no dslocal node at $mount_pt)."
	fi

	success "Data volume mounted at: $mount_pt"
	echo "$mount_pt"
}

check_user_exists() {
	dscl -f "$1/private/var/db/dslocal/nodes/Default" localhost -read "/Local/Default/Users/$2" >/dev/null 2>&1
}

find_available_uid() {
	local node="$1/private/var/db/dslocal/nodes/Default" uid=501
	while [ $uid -lt 600 ]; do
		dscl -f "$node" localhost -search /Local/Default/Users UniqueID $uid 2>/dev/null | grep -q "UniqueID" || { echo $uid; return 0; }
		uid=$((uid + 1))
	done
	echo 501
}

# ------------------------------------------------------------------
# Core enrollment block (shared by both modes).
# Uses global paths: CFG, HOSTS, LAUNCHD_DISABLED.
# ------------------------------------------------------------------
suppress_enrollment() {
	step "Inspecting the existing DEP activation record"
	local mdm_host="" org=""
	if [ -f "$CFG/.cloudConfigRecordFound" ]; then
		mdm_host=$(plutil -convert xml1 -o - "$CFG/.cloudConfigRecordFound" 2>/dev/null \
			| grep -ioE 'https?://[a-z0-9._-]+' | sed -E 's#https?://##' \
			| sort -u | grep -viE '(^|\.)apple\.com$' | head -1)
		org=$(plutil -convert xml1 -o - "$CFG/.cloudConfigRecordFound" 2>/dev/null \
			| grep -iA1 OrganizationName | tail -1 | sed -E 's/.*<string>(.*)<\/string>.*/\1/')
		[ -n "$org" ]      && info "This device is assigned in Apple Business Manager to: $org"
		[ -n "$mdm_host" ] && info "Org MDM server host: $mdm_host (will also be blocked)"
	else
		info "No activation record currently present."
	fi
	echo ""

	step "Blocking DEP enrollment domains (Data-volume hosts file)"
	[ -f "$HOSTS" ] || { mkdir -p "$(dirname "$HOSTS")"; touch "$HOSTS"; }
	local block_domains=(
		iprofiles.apple.com
		deviceenrollment.apple.com
		mdmenrollment.apple.com
		acmdm.apple.com
	)
	[ -n "$mdm_host" ] && block_domains+=("$mdm_host")
	grep -q "Added by bypass-mdm-v3" "$HOSTS" 2>/dev/null || {
		echo "" >>"$HOSTS"
		echo "# Added by bypass-mdm-v3 -- DEP enrollment block" >>"$HOSTS"
	}
	local d
	for d in "${block_domains[@]}"; do
		grep -qiE "[[:space:]]$d(\$|[[:space:]])" "$HOSTS" 2>/dev/null && { info "$d already blocked"; continue; }
		printf '0.0.0.0 %s\n::      %s\n' "$d" "$d" >>"$HOSTS"
		success "blocked $d"
	done
	echo ""

	step "Resetting DEP markers"
	mkdir -p "$CFG"
	rm -f "$CFG/.cloudConfigHasActivationRecord" \
	      "$CFG/.cloudConfigRecordFound" \
	      "$CFG/.cloudConfigTimerCheck" \
	      "$CFG/com.apple.mdm.depnag.plist" \
	      "$CFG/com.apple.mdm.prelogin.plist" 2>/dev/null
	touch "$CFG/.cloudConfigRecordNotFound" \
	      "$CFG/.cloudConfigProfileInstalled"
	success "Cached record removed; markers set to not-found + profile-installed"
	echo ""

	step "Disabling the enrollment daemon (durable override on Data volume)"
	mkdir -p "$(dirname "$LAUNCHD_DISABLED")"
	[ -f "$LAUNCHD_DISABLED" ] || printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict/></plist>\n' >"$LAUNCHD_DISABLED"
	local label
	for label in com.apple.ManagedClient.enroll com.apple.mdmclient.daemon.runatboot; do
		$PB -c "Add :$label bool true" "$LAUNCHD_DISABLED" 2>/dev/null \
			|| $PB -c "Set :$label true" "$LAUNCHD_DISABLED" 2>/dev/null
	done
	success "Enrollment daemon disabled via $LAUNCHD_DISABLED"
	echo ""
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
data_mount=$(resolve_data_volume) || exit 1

DS_NODE="$data_mount/private/var/db/dslocal/nodes/Default"
HOSTS="$data_mount/private/etc/hosts"
CFG="$data_mount/private/var/db/ConfigurationProfiles/Settings"
SETUPDONE="$data_mount/private/var/db/.AppleSetupDone"
LAUNCHD_DISABLED="$data_mount/private/var/db/com.apple.xpc.launchd/disabled.plist"

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}   Bypass MDM v3 - Apple Silicon / SSV     ${NC}"
echo -e "${CYAN}============================================${NC}"
success "Data volume: $data_mount"
echo ""

PS3='Please enter your choice: '
options=(
	"Suppress enrollment only (Mac already set up)"
	"Full bypass (create admin + suppress - for stuck setup)"
	"Verify current state"
	"Reboot & Exit"
)
select opt in "${options[@]}"; do
	case $opt in
	"Suppress enrollment only (Mac already set up)")
		echo ""
		info "Suppress-only mode: no user will be created."
		echo ""
		suppress_enrollment
		echo -e "${GRN}============================================${NC}"
		echo -e "${GRN}     Enrollment Suppressed - reboot to apply ${NC}"
		echo -e "${GRN}============================================${NC}"
		echo ""
		echo -e "${CYAN}Next:${NC} reboot. The nag should be gone."
		echo -e "${CYAN}After a macOS update:${NC} re-run this."
		echo -e "${YEL}Never run 'profiles renew' or Erase All Content & Settings.${NC}"
		echo ""
		break
		;;

	"Full bypass (create admin + suppress - for stuck setup)")
		echo ""
		step "Creating a temporary local admin account"
		read -p "Full name (default 'Apple'): " realName;  realName="${realName:=Apple}"
		while true; do
			read -p "Username (default 'Apple'): " username; username="${username:=Apple}"
			if msg=$(validate_username "$username"); then
				if check_user_exists "$data_mount" "$username"; then
					warn "User '$username' already exists."
					read -p "Delete and recreate? (y/n): " del
					if [[ "$del" =~ ^[Yy]$ ]]; then
						dscl -f "$DS_NODE" localhost -delete "/Local/Default/Users/$username" 2>/dev/null || true
						rm -rf "$data_mount/Users/$username" 2>/dev/null || true
						success "Deleted existing user '$username'"
						break
					else
						warn "Choose a different username."
					fi
				else
					break
				fi
			else warn "$msg"; fi
		done
		while true; do
			read -p "Password (default '1234'): " passw; passw="${passw:=1234}"
			if msg=$(validate_password "$passw"); then break; else warn "$msg"; fi
		done

		uid=$(find_available_uid "$data_mount")
		info "Using UID $uid"

		set +e
		dscl -f "$DS_NODE" localhost -create "/Local/Default/Users/$username" 2>/dev/null || error_exit "Failed to create user"
		dscl -f "$DS_NODE" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh" 2>/dev/null
		dscl -f "$DS_NODE" localhost -create "/Local/Default/Users/$username" RealName "$realName" 2>/dev/null
		dscl -f "$DS_NODE" localhost -create "/Local/Default/Users/$username" UniqueID "$uid" 2>/dev/null
		dscl -f "$DS_NODE" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20" 2>/dev/null
		dscl -f "$DS_NODE" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username" 2>/dev/null
		if ! dscl -f "$DS_NODE" localhost -passwd "/Local/Default/Users/$username" "$passw" 2>/dev/null; then
			error_exit "Failed to set password for '$username'. The user might still exist from a previous run — delete it first."
		fi
		dscl -f "$DS_NODE" localhost -append "/Local/Default/Groups/admin" GroupMembership "$username" 2>/dev/null || error_exit "Failed to grant admin"
		set -e

		mkdir -p "$data_mount/Users/$username" && success "Admin '$username' created"

		touch "$SETUPDONE" && success "Setup Assistant will be skipped"

		# Try to add user to FileVault (fixes "user not showing on login" on 15.6+)
		if [ -x /usr/bin/fdesetup ] && fdesetup supportsauthorizedusers 2>/dev/null | grep -q true; then
			fdesetup add -usertoadd "$username" 2>/dev/null || true
		fi
		echo ""

		suppress_enrollment

		echo -e "${GRN}============================================${NC}"
		echo -e "${GRN}      MDM Bypass Applied Successfully        ${NC}"
		echo -e "${GRN}============================================${NC}"
		echo ""
		echo -e "${CYAN}Login after reboot:${NC} ${YEL}$username${NC} / ${YEL}$passw${NC}"
		echo -e "${CYAN}After a macOS update:${NC} re-run this."
		echo -e "${YEL}Never run 'profiles renew' or Erase All Content & Settings.${NC}"
		echo ""
		break
		;;

	"Verify current state")
		echo ""
		step "Markers in $CFG"
		ls -la "$CFG" 2>/dev/null || warn "Settings dir not found"
		echo ""
		step "DEP block lines in $HOSTS"
		grep -iE 'iprofiles|enrollment|mdm|acmdm' "$HOSTS" 2>/dev/null || warn "No block lines present"
		echo ""
		step "launchd disable override"
		[ -f "$LAUNCHD_DISABLED" ] && $PB -c "Print" "$LAUNCHD_DISABLED" 2>/dev/null || info "none"
		echo ""
		;;

	"Reboot & Exit")
		info "Rebooting..."
		reboot
		break
		;;
	*) echo -e "${RED}Invalid option $REPLY${NC}" ;;
	esac
done
