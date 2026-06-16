#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$PROJECT_DIR/bypass-mdm-v2.sh"

failures=0

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	failures=$((failures + 1))
}

pass() {
	printf 'PASS: %s\n' "$1"
}

assert_success() {
	local name="$1"
	shift
	if "$@"; then
		pass "$name"
	else
		fail "$name"
	fi
}

assert_failure() {
	local name="$1"
	shift
	if "$@"; then
		fail "$name"
	else
		pass "$name"
	fi
}

make_fixture() {
	fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/bypass-mdm-tests.XXXXXX")"
	volumes_root="$fixture_dir/Volumes"
	mock_bin="$fixture_dir/bin"
	diskutil_log="$fixture_dir/diskutil.log"
	mkdir -p \
		"$volumes_root/GoldenGate/System/Library/CoreServices" \
		"$volumes_root/GoldenGate/private/var/db/dslocal/nodes/Default" \
		"$volumes_root/GoldenGate - Data/System/Library/CoreServices" \
		"$volumes_root/GoldenGate - Data/private/var/db/dslocal/nodes/Default" \
		"$volumes_root/GoldenGate - Data/Users" \
		"$mock_bin"

	cat >"$mock_bin/diskutil" <<'EOF'
#!/bin/bash

printf '%s\n' "$*" >>"$DISKUTIL_LOG"

if [ "$1" = "apfs" ] && [ "$2" = "listVolumeGroups" ] && [ "$3" = "-plist" ]; then
	cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Containers</key>
	<array>
		<dict>
			<key>VolumeGroups</key>
			<array>
				<dict>
					<key>Volumes</key>
					<array>
						<dict>
							<key>DeviceIdentifier</key>
							<string>disk8s1</string>
							<key>Role</key>
							<string>Data</string>
						</dict>
						<dict>
							<key>DeviceIdentifier</key>
							<string>disk8s2</string>
							<key>Role</key>
							<string>System</string>
						</dict>
					</array>
				</dict>
				<dict>
					<key>Volumes</key>
					<array>
						<dict>
							<key>DeviceIdentifier</key>
							<string>disk9s1</string>
							<key>Role</key>
							<string>Data</string>
						</dict>
						<dict>
							<key>DeviceIdentifier</key>
							<string>disk9s2</string>
							<key>Role</key>
							<string>System</string>
						</dict>
					</array>
				</dict>
			</array>
		</dict>
	</array>
</dict>
</plist>
PLIST
	exit 0
fi

if [ "$1" != "info" ] || [ "$2" != "-plist" ]; then
	exit 64
fi

case "$3" in
*"AlphaMac - Data")
	group_id="OTHER-MAC-GROUP"
	internal="true"
	external_device="false"
	volume_name="AlphaMac - Data"
	device_identifier="disk8s1"
	;;
*"AlphaMac")
	group_id="OTHER-MAC-GROUP"
	internal="true"
	external_device="false"
	volume_name="AlphaMac"
	device_identifier="disk8s2"
	;;
*"GoldenGate - Data")
	group_id="${DATA_GROUP_ID:-EXTERNAL-GROUP}"
	internal="${DATA_INTERNAL:-false}"
	external_device="${DATA_EXTERNAL_DEVICE:-true}"
	volume_name="GoldenGate - Data"
	device_identifier="disk9s1"
	;;
*"GoldenGate")
	group_id="${SYSTEM_GROUP_ID:-EXTERNAL-GROUP}"
	internal="${SYSTEM_INTERNAL:-false}"
	external_device="${SYSTEM_EXTERNAL_DEVICE:-true}"
	volume_name="GoldenGate"
	device_identifier="disk9s2"
	;;
*)
	exit 1
	;;
esac

cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>APFSVolumeGroupID</key>
	<string>$group_id</string>
	<key>Internal</key>
	<$internal/>
	<key>RemovableMediaOrExternalDevice</key>
	<$external_device/>
	<key>VolumeName</key>
	<string>$volume_name</string>
	<key>DeviceIdentifier</key>
	<string>$device_identifier</string>
	<key>APFSSnapshot</key>
	<false/>
</dict>
</plist>
PLIST
EOF
	chmod +x "$mock_bin/diskutil"
}

remove_fixture() {
	rm -rf "$fixture_dir"
}

run_script() {
	if [ "${DEBUG_TESTS:-0}" = "1" ]; then
		if [ -n "${RUN_INPUT:-}" ]; then
			printf '%s\n' "$RUN_INPUT" | env \
				VOLUMES_ROOT="$volumes_root" \
				DISKUTIL_BIN="$mock_bin/diskutil" \
				DISKUTIL_LOG="$diskutil_log" \
				/bin/bash "$SCRIPT" "$@"
		else
			VOLUMES_ROOT="$volumes_root" \
			DISKUTIL_BIN="$mock_bin/diskutil" \
			DISKUTIL_LOG="$diskutil_log" \
			/bin/bash "$SCRIPT" "$@"
		fi
	else
		if [ -n "${RUN_INPUT:-}" ]; then
			printf '%s\n' "$RUN_INPUT" | env \
				VOLUMES_ROOT="$volumes_root" \
				DISKUTIL_BIN="$mock_bin/diskutil" \
				DISKUTIL_LOG="$diskutil_log" \
				/bin/bash "$SCRIPT" "$@" >/dev/null 2>&1
		else
			VOLUMES_ROOT="$volumes_root" \
			DISKUTIL_BIN="$mock_bin/diskutil" \
			DISKUTIL_LOG="$diskutil_log" \
			/bin/bash "$SCRIPT" "$@" >/dev/null 2>&1
		fi
	fi
}

test_interactive_system_volume_selection() {
	local output
	local status

	make_fixture
	mkdir -p \
		"$volumes_root/AlphaMac/System/Library/CoreServices" \
		"$volumes_root/AlphaMac - Data/private/var/db/dslocal/nodes/Default"
	output=$(printf '2\n' | env \
		VOLUMES_ROOT="$volumes_root" \
		DISKUTIL_BIN="$mock_bin/diskutil" \
		DISKUTIL_LOG="$diskutil_log" \
		/bin/bash "$SCRIPT" --require-external --validate-only 2>&1)
	status=$?
	if [ "$status" -eq 0 ]; then
		printf '%s\n' "$output" | grep -Fq '1) AlphaMac [Internal]' || status=1
		printf '%s\n' "$output" | grep -Fq '2) GoldenGate [External]' || status=1
		if printf '%s\n' "$output" | grep -Fq 'GoldenGate - Data [External]'; then
			status=1
		fi
	fi
	remove_fixture
	return "$status"
}

test_arrow_key_system_volume_selection() {
	local status

	make_fixture
	mkdir -p \
		"$volumes_root/AlphaMac/System/Library/CoreServices" \
		"$volumes_root/AlphaMac - Data/private/var/db/dslocal/nodes/Default"
	printf '\033[B\n' | env \
		BYPASS_MDM_FORCE_ARROW_MENU=1 \
		VOLUMES_ROOT="$volumes_root" \
		DISKUTIL_BIN="$mock_bin/diskutil" \
		DISKUTIL_LOG="$diskutil_log" \
		/bin/bash "$SCRIPT" --require-external --validate-only >/dev/null 2>&1
	status=$?
	remove_fixture
	return "$status"
}

test_real_tty_uses_arrow_menu() {
	local transcript
	local status

	make_fixture
	mkdir -p \
		"$volumes_root/AlphaMac/System/Library/CoreServices" \
		"$volumes_root/AlphaMac - Data/private/var/db/dslocal/nodes/Default"
	transcript="$fixture_dir/tty-output.log"
	printf '\033[B\n' | TERM=xterm script -q -e "$transcript" env \
		VOLUMES_ROOT="$volumes_root" \
		DISKUTIL_BIN="$mock_bin/diskutil" \
		DISKUTIL_LOG="$diskutil_log" \
		/bin/bash "$SCRIPT" --require-external --validate-only >/dev/null 2>&1
	status=$?
	if [ "$status" -eq 0 ]; then
		grep -Fq 'Use Up/Down arrows to choose' "$transcript" || status=1
		grep -Fq 'Target volume pair validated' "$transcript" || status=1
	fi
	remove_fixture
	return "$status"
}

test_invalid_menu_selection_retries() {
	make_fixture
	mkdir -p \
		"$volumes_root/AlphaMac/System/Library/CoreServices" \
		"$volumes_root/AlphaMac - Data/private/var/db/dslocal/nodes/Default"
	RUN_INPUT=$'99\ninvalid\n2' run_script \
		--require-external \
		--validate-only
	local status=$?
	remove_fixture
	return "$status"
}

test_explicit_external_pair() {
	make_fixture
	run_script \
		--system-volume "GoldenGate" \
		--data-volume "GoldenGate - Data" \
		--require-external \
		--validate-only
	local status=$?
	remove_fixture
	return "$status"
}

test_system_name_matches_data_volume() {
	make_fixture
	run_script \
		--system-volume "GoldenGate" \
		--require-external \
		--validate-only
	local status=$?
	remove_fixture
	return "$status"
}

test_mismatched_volume_groups() {
	make_fixture
	DATA_GROUP_ID="OTHER-GROUP" run_script \
		--system-volume "GoldenGate" \
		--data-volume "GoldenGate - Data" \
		--require-external \
		--validate-only
	local status=$?
	remove_fixture
	return "$status"
}

test_rejects_data_volume_as_system() {
	make_fixture
	run_script \
		--system-volume "GoldenGate - Data" \
		--data-volume "GoldenGate" \
		--validate-only
	local status=$?
	remove_fixture
	return "$status"
}

test_missing_data_volume() {
	make_fixture
	rm -rf "$volumes_root/GoldenGate - Data"
	run_script \
		--system-volume "GoldenGate" \
		--data-volume "GoldenGate - Data" \
		--require-external \
		--validate-only
	local status=$?
	remove_fixture
	return "$status"
}

test_rejects_internal_target() {
	make_fixture
	SYSTEM_INTERNAL="true" SYSTEM_EXTERNAL_DEVICE="false" run_script \
		--system-volume "GoldenGate" \
		--data-volume "GoldenGate - Data" \
		--require-external \
		--validate-only
	local status=$?
	remove_fixture
	return "$status"
}

test_rejects_path_traversal() {
	make_fixture
	run_script \
		--system-volume "../GoldenGate" \
		--data-volume "GoldenGate - Data" \
		--validate-only
	local status=$?
	remove_fixture
	return "$status"
}

test_never_renames_volume() {
	make_fixture
	run_script \
		--system-volume "GoldenGate" \
		--data-volume "GoldenGate - Data" \
		--validate-only || {
		remove_fixture
		return 1
	}
	if grep -q '^rename ' "$diskutil_log"; then
		remove_fixture
		return 1
	fi
	remove_fixture
	return 0
}

test_password_is_visible() {
	grep -Fq 'read -p "Enter Temporary Password' "$SCRIPT" &&
		! grep -Fq 'read -s -p "Enter Temporary Password' "$SCRIPT" &&
		grep -Fq 'and password: ${YEL}$passw${NC}' "$SCRIPT"
}

test_all_discrete_choices_use_shared_menu() {
	grep -Fq 'choose_menu_option_with_back "Choose an action"' "$SCRIPT" &&
		grep -Fq 'choose_menu_option_with_back "User already exists"' "$SCRIPT" &&
		! grep -Fq 'select opt in' "$SCRIPT" &&
		! grep -Fq 'Do you want to use a different username? (y/n)' "$SCRIPT"
}

test_shared_arrow_menu_returns_selected_option() {
	local input_file
	local output_file
	local helpers_file
	local status=0

	# Load function definitions without running the script entry point.
	helpers_file=$(mktemp "${TMPDIR:-/tmp}/bypass-mdm-menu-helpers.XXXXXX")
	awk '$0 == "parse_arguments \"$@\"" {exit} {print}' "$SCRIPT" >"$helpers_file"
	source "$helpers_file"
	input_file=$(mktemp "${TMPDIR:-/tmp}/bypass-mdm-menu-input.XXXXXX")
	output_file=$(mktemp "${TMPDIR:-/tmp}/bypass-mdm-menu-output.XXXXXX")
	printf '\033[B\n' >"$input_file"

	BYPASS_MDM_FORCE_ARROW_MENU=1
	choose_menu_option "Test menu" "Choose an option." "First option" "Second option" <"$input_file" >"$output_file" || status=1
	[ "$SELECTED_MENU_INDEX" -eq 1 ] || status=1
	grep -Fq 'First option' "$output_file" || status=1
	grep -Fq 'Second option' "$output_file" || status=1

	rm -f "$input_file" "$output_file" "$helpers_file"
	return "$status"
}

test_arrow_menu_redraws_in_place_without_saved_cursor() {
	local helpers_file
	local output_file
	local status=0

	helpers_file=$(mktemp "${TMPDIR:-/tmp}/bypass-mdm-redraw-helpers.XXXXXX")
	awk '$0 == "parse_arguments \"$@\"" {exit} {print}' "$SCRIPT" >"$helpers_file"
	source "$helpers_file"
	output_file=$(mktemp "${TMPDIR:-/tmp}/bypass-mdm-redraw-output.XXXXXX")
	MENU_OPTIONS=("First option" "Second option")

	render_arrow_menu 0 "Test menu" "Choose an option." false >"$output_file"
	render_arrow_menu 1 "Test menu" "Choose an option." true >>"$output_file"

	grep -Fq $'\033[5A' "$output_file" || status=1
	if grep -Fq $'\033[s' "$output_file" || grep -Fq $'\033[u' "$output_file"; then
		status=1
	fi

	rm -f "$output_file" "$helpers_file"
	return "$status"
}

test_escape_returns_to_previous_step() {
	local input_file
	local output_file
	local helpers_file
	local menu_status
	local status=0

	helpers_file=$(mktemp "${TMPDIR:-/tmp}/bypass-mdm-menu-helpers.XXXXXX")
	awk '$0 == "parse_arguments \"$@\"" {exit} {print}' "$SCRIPT" >"$helpers_file"
	source "$helpers_file"
	input_file=$(mktemp "${TMPDIR:-/tmp}/bypass-mdm-menu-input.XXXXXX")
	output_file=$(mktemp "${TMPDIR:-/tmp}/bypass-mdm-menu-output.XXXXXX")
	printf '\033' >"$input_file"

	BYPASS_MDM_FORCE_ARROW_MENU=1
	choose_menu_option_with_back "Test menu" "Choose an option." "First option" "Second option" <"$input_file" >"$output_file"
	menu_status=$?
	[ "$menu_status" -eq 2 ] || status=1
	[ "$MENU_WENT_BACK" = true ] || status=1

	rm -f "$input_file" "$output_file" "$helpers_file"
	return "$status"
}

test_confirmation_summary_lists_all_information() {
	local output_file
	local helpers_file
	local status=0

	helpers_file=$(mktemp "${TMPDIR:-/tmp}/bypass-mdm-confirm-helpers.XXXXXX")
	awk '$0 == "parse_arguments \"$@\"" {exit} {print}' "$SCRIPT" >"$helpers_file"
	source "$helpers_file"
	output_file=$(mktemp "${TMPDIR:-/tmp}/bypass-mdm-confirm-output.XXXXXX")

	system_volume="GoldenGate"
	data_volume="GoldenGate - Data"
	system_path="/Volumes/GoldenGate"
	data_path="/Volumes/GoldenGate - Data"
	dscl_path="$data_path/private/var/db/dslocal/nodes/Default"
	target_volume_group_id="EXTERNAL-GROUP"
	realName="Apple Admin"
	username="apple"
	passw="visible-password"
	available_uid="501"
	print_confirmation_summary >"$output_file"

	grep -Fq 'System Volume: GoldenGate' "$output_file" || status=1
	grep -Fq 'Data Volume: GoldenGate - Data' "$output_file" || status=1
	grep -Fq 'APFS Volume Group: EXTERNAL-GROUP' "$output_file" || status=1
	grep -Fq 'Full Name: Apple Admin' "$output_file" || status=1
	grep -Fq 'Username: apple' "$output_file" || status=1
	grep -Fq 'Password: visible-password' "$output_file" || status=1
	grep -Fq 'UID: 501' "$output_file" || status=1
	grep -Fq 'Home Directory: /Users/apple' "$output_file" || status=1

	rm -f "$output_file" "$helpers_file"
	return "$status"
}

test_writes_are_gated_by_final_confirmation() {
	grep -Fq 'confirm_bypass_settings' "$SCRIPT" &&
		grep -Fq '"Confirm and Run"' "$SCRIPT" &&
		grep -Fq 'execute_bypass' "$SCRIPT" &&
		grep -Fq 'info "Changes are now being written and can no longer be taken back."' "$SCRIPT"
}

test_writes_use_data_volume_paths() {
	grep -Fq 'hosts_file="$data_path/private/etc/hosts"' "$SCRIPT" &&
		grep -Fq 'config_path="$data_path/private/var/db/ConfigurationProfiles/Settings"' "$SCRIPT" &&
		! grep -Fq 'hosts_file="$system_path/etc/hosts"' "$SCRIPT" &&
		! grep -Fq 'config_path="$system_path/var/db/ConfigurationProfiles/Settings"' "$SCRIPT"
}

test_demo_mode_previews_full_ui_without_system_access() {
	local demo_dir
	local demo_bin
	local forbidden_log
	local output_file
	local reboot_output_file
	local command_name
	local status=0

	demo_dir=$(mktemp -d "${TMPDIR:-/tmp}/bypass-mdm-demo.XXXXXX")
	demo_bin="$demo_dir/bin"
	forbidden_log="$demo_dir/forbidden.log"
	output_file="$demo_dir/output.log"
	reboot_output_file="$demo_dir/reboot-output.log"
	mkdir -p "$demo_bin"
	: >"$forbidden_log"

	for command_name in diskutil dscl id reboot mkdir touch rm; do
		cat >"$demo_bin/$command_name" <<'EOF'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$DEMO_FORBIDDEN_LOG"
exit 91
EOF
		chmod +x "$demo_bin/$command_name"
	done

	printf '2\n1\n\n\n\n1\n' | env \
		PATH="$demo_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
		DEMO_FORBIDDEN_LOG="$forbidden_log" \
		DISKUTIL_BIN="$demo_bin/diskutil" \
		/bin/bash "$SCRIPT" --demo >"$output_file" 2>&1 || status=1

	grep -Fq 'DEMO MODE - NO CHANGES WILL BE MADE' "$output_file" || status=1
	grep -Fq '1) Macintosh HD [Internal]' "$output_file" || status=1
	grep -Fq '2) GoldenGate [External]' "$output_file" || status=1
	grep -Fq 'System Volume: GoldenGate' "$output_file" || status=1
	grep -Fq 'Data Volume: GoldenGate - Data' "$output_file" || status=1
	grep -Fq 'Password: 1234' "$output_file" || status=1
	grep -Fq 'Demo completed; no changes were made.' "$output_file" || status=1
	[ ! -s "$forbidden_log" ] || status=1

	printf '2\n2\n1\n' | env \
		PATH="$demo_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
		DEMO_FORBIDDEN_LOG="$forbidden_log" \
		DISKUTIL_BIN="$demo_bin/diskutil" \
		/bin/bash "$SCRIPT" --demo >"$reboot_output_file" 2>&1 || status=1
	grep -Fq 'Demo reboot selected; no reboot was performed.' "$reboot_output_file" || status=1
	[ ! -s "$forbidden_log" ] || status=1

	/bin/rm -rf "$demo_dir"
	return "$status"
}

assert_success "selects a system volume interactively and matches its data volume" test_interactive_system_volume_selection
assert_success "supports down-arrow and Enter system-volume selection" test_arrow_key_system_volume_selection
assert_success "automatically uses the arrow menu on a real TTY" test_real_tty_uses_arrow_menu
assert_success "re-prompts after an invalid system-volume menu choice" test_invalid_menu_selection_retries
assert_success "accepts an explicit external APFS volume pair" test_explicit_external_pair
assert_success "matches the data volume when only the system name is provided" test_system_name_matches_data_volume
assert_failure "rejects volumes from different APFS volume groups" test_mismatched_volume_groups
assert_failure "rejects an APFS Data volume selected as the system volume" test_rejects_data_volume_as_system
assert_failure "rejects an unmounted or missing data volume" test_missing_data_volume
assert_failure "rejects an internal target when external media is required" test_rejects_internal_target
assert_failure "rejects volume names containing path traversal" test_rejects_path_traversal
assert_success "does not rename the selected data volume" test_never_renames_volume
assert_success "shows password input and prints the password after completion" test_password_is_visible
assert_success "uses the shared interactive menu for all discrete choices" test_all_discrete_choices_use_shared_menu
assert_success "shared arrow menu returns the selected option" test_shared_arrow_menu_returns_selected_option
assert_success "arrow menu redraws in place without saved-cursor sequences" test_arrow_menu_redraws_in_place_without_saved_cursor
assert_success "Escape returns to the previous menu step" test_escape_returns_to_previous_step
assert_success "confirmation summary lists target, account, UID, and plaintext password" test_confirmation_summary_lists_all_information
assert_success "disk writes are gated by final confirmation" test_writes_are_gated_by_final_confirmation
assert_success "writes hosts and configuration markers to the Data volume" test_writes_use_data_volume_paths
assert_success "demo mode previews the full UI without system access" test_demo_mode_previews_full_ui_without_system_access

if [ "$failures" -ne 0 ]; then
	printf '\n%d test(s) failed\n' "$failures" >&2
	exit 1
fi

printf '\nAll volume targeting tests passed\n'
