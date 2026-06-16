# Bypass MDM for macOS 💻

A script to bypass Mobile Device Management (MDM) enrollment during macOS setup, with APFS System/Data volume targeting for internal and external macOS installations.

## 💽 APFS Volume Highlights

- **External macOS Support** - Select an external macOS installation without modifying the internal system
- **Real APFS Role Detection** - Only APFS System volumes appear in the menu; Data volumes cannot be selected manually
- **Automatic Data Volume Matching** - Matches the Data volume through the APFS Volume Group ID
- **Internal/External Labels** - Clearly identifies where each macOS System volume is located
- **SSV-Aware Writes** - Writes hosts and configuration markers to the selected Data volume paths used by modern macOS
- **Interactive Menus** - Use the Up/Down arrow keys and Enter for all fixed choices
- **Back Navigation** - Press Esc or choose Back to return before any target-volume changes begin
- **Final Review** - Review the selected volumes, account details, UID, and plaintext password before execution
- **Safe UI Demo** - Preview the complete workflow with simulated data and no disk, account, file, or reboot operations
- **External Drive Guard** - `--require-external` refuses to operate on an internal installation
- **Validation Mode** - `--validate-only` checks the selected volume pair without making changes
- **No Volume Renaming** - Keeps the original System and Data volume names

## ✨ Features

- Creates a temporary administrator account
- Validates usernames, passwords, system paths, and available UIDs
- Blocks MDM enrollment domains
- Configures setup and enrollment markers
- Detects duplicate users and conflicting UIDs
- Revalidates the selected System/Data pair before writing
- Shows clear progress, warning, and error messages
- Tested successfully on macOS Tahoe 26.5.1 with an external APFS System/Data volume pair

## ⚠️ Prerequisites

- Use only on a Mac you own or are explicitly authorized to manage
- Run the script from macOS Recovery Terminal
- Connect to the internet before downloading the script
- Ensure the target APFS System and Data volumes are mounted
- A fresh macOS installation is recommended

## 👀 Preview the UI Safely

Download the script and start the isolated demo mode from a normal macOS Terminal:

```bash
curl -fL https://raw.githubusercontent.com/assafdori/bypass-mdm/main/bypass-mdm-v2.sh -o bypass-mdm.sh && chmod +x bypass-mdm.sh && ./bypass-mdm.sh --demo
```

Demo mode shows the disk menu, Back navigation, account prompts, plaintext password, final review, execution messages, and reboot confirmation. It uses simulated `Macintosh HD` and `GoldenGate` volumes and does not inspect or modify the real Mac.

## 📋 Installation & Usage

### Step-by-Step Instructions

**1. Boot into Recovery Mode**

- **Apple Silicon Mac:** Hold the Power button until startup options appear
- **Intel Mac:** Hold <kbd>Command</kbd> + <kbd>R</kbd> during startup

**2. Connect to Wi-Fi**

**3. Open Terminal** from **Utilities > Terminal**

**4. Download and run the script**

For an external macOS installation:

```bash
curl -fL https://raw.githubusercontent.com/assafdori/bypass-mdm/main/bypass-mdm-v2.sh -o bypass-mdm.sh && chmod +x bypass-mdm.sh && ./bypass-mdm.sh --require-external
```

To allow either an internal or external installation, omit `--require-external`:

```bash
./bypass-mdm.sh
```

**5. Select the macOS System volume**

Use the Up/Down arrow keys to move the highlight and press Enter. Press Esc on later menus to return to the previous step:

```text
   Macintosh HD [Internal]
 > GoldenGate [External]
```

Only APFS System volumes are listed. The matching Data volume is detected automatically and verified through its APFS Volume Group ID.

**6. Choose "Bypass MDM from Recovery"**

**7. Create the temporary administrator account**

Press Enter to use the defaults:

- **Full name:** Apple
- **Username:** Apple
- **Password:** 1234

Password entry is visible.

**8. Review and confirm all settings**

Before any target-volume changes are made, the script displays:

- System and Data volume names and paths
- Internal/External location and APFS Volume Group ID
- Directory Services path
- Full name, username, and plaintext password
- Account status, UID, group ID, shell, and home directory
- A list of planned changes

From this page you can edit the account, change the System volume, return to the action menu, or exit without changes. Only **Confirm and Run** starts writing to the selected volumes. Once writing starts, the wizard cannot take those changes back.

**9. Reboot and sign in**

When the completion message appears, close Terminal and reboot the Mac.

## 🧪 Validate Without Changes

To verify external System/Data volume detection without modifying any files:

```bash
./bypass-mdm.sh --require-external --validate-only
```

The script stops safely if:

- The selected volume is not external
- The System or Data volume is not mounted
- The selected volume does not have the correct APFS role
- The System and Data volumes are not in the same APFS Volume Group
- The selected volume group changes before writing

## 🔄 Post-Installation Steps

1. Sign in with the temporary administrator account.
2. Skip the remaining Setup Assistant prompts if needed.
3. Open **System Settings > Users & Groups**.
4. Create your permanent administrator account.
5. Sign in to the permanent account.
6. Remove the temporary account when it is no longer needed.

## 🔧 Troubleshooting

### No System Volumes Listed

- Confirm the target macOS installation is mounted in Disk Utility
- Confirm the volume has the APFS System role
- Unlock encrypted volumes before running the script
- Do not select or rename the Data volume manually

### Matching Data Volume Not Found

- Mount the corresponding Data volume in Disk Utility
- Confirm macOS installation has completed on the target drive
- Verify the System and Data volumes belong to the same APFS Volume Group

### Permission Errors

- Confirm the script is running from macOS Recovery Terminal
- Make the script executable with `chmod +x bypass-mdm.sh`

### Invalid Username or Password

- Username must start with a letter or underscore
- Username may contain letters, numbers, underscores, and hyphens
- Password must contain at least four characters

## 📦 Versions

| File | Description | Status |
| --- | --- | --- |
| `bypass-mdm-v2.sh` | APFS role detection, external-drive support, SSV-aware Data-volume writes, validation, and interactive menus | Recommended |
| `bypass-mdm.sh` | Original legacy script with hardcoded volume names | Legacy |

## ⚖️ Legal Disclaimer

This project is intended for personal devices, authorized administration, and educational use. Do not use it to bypass legitimate organizational controls without permission. Use at your own risk.

## 📄 License

Released under the MIT License. The original copyright and permission notice are preserved in [LICENSE](LICENSE).
