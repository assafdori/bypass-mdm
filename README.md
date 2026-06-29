# Bypass MDM v3 — Hybrid Edition 💻

![mdm-screen](https://raw.githubusercontent.com/assafdori/bypass-mdm/main/mdm-screen.png)

An automated utility script designed to run from the macOS Recovery Environment to provision a local administrator account and bypass Mobile Device Management (MDM) / Automated Device Enrollment (ADE) configurations on macOS.

This third iteration merges the targeted volume logic of **v1**, the error-handling robustness of **v2**, and introduces a brand-new **interactive manual fallback interface** for complex storage setups.

---

## ⚡ What's New in Version 3?

* **Hybrid Volume Detection Engine (Three-Tier Priority Loop):**
    * **Priority 1 (Extended v1 Approach):** Scans instantly for default standard macOS installation paths (`Macintosh HD` or `Monterey HD`). Includes automatic system/data partition alignment and renaming rules.
    * **Priority 2 (v2 Logic):** If standard targets are missing, evaluates paths using smart heuristic auto-detection loops (looks for any path containing `/System`).
    * **Priority 3 (v3 Fallback):** If both fail, lists active directories under `/Volumes/` and opens an interactive, prompt-based input form for completely manual target definitions.
* **Safe Account Provisioning:** Integrates sanitization scripts to locate unassigned UIDs between `501` and `600` inside Directory Services (`dscl`) to prevent structural collisions.
* **Robust Pre-Flight Verifications:** Checks internal components (`/private/var/db/dslocal/...`) explicitly before editing files to eliminate silent terminal crashes.

---

## ✨ System Features

* **🔍 Smart Multi-Tier Volumes Engine** – Prevents pathing script failure regardless of customized drive labels or multi-drive topologies.
* **🛡️ Active Host Mitigation** – Implements direct host looping to bind explicit endpoint networks locally to `0.0.0.0`:
    * `deviceenrollment.apple.com`
    * `mdmenrollment.apple.com`
    * `iprofiles.apple.com`
* **🎯 Cloud Config Overrides** – Injects structural local completion markers (`.AppleSetupDone`) and forces configuration profile suppressions onto targeted root mount-points.
* **📊 Colorized Recovery Output** – Displays structural progress metrics, warnings, and prompt-helpers directly within standard Recovery terminal windows.

---

## ⚠️ Prerequisites

* **Clean starting point:** It is strongly recommended to erase your hard drive and perform a fresh macOS installation before running the script.
* **Language Selection:** Setting the recovery environment language to **English** is recommended to ensure matching character sets.
* **Storage Access:** Encrypted Target drives must be manually mounted/unlocked via **Disk Utility** prior to opening the terminal session.

---

## 📋 Installation & Usage

### Phase 1: Running the Recovery Tool

1.  **Shut Down Your Mac** completely.
2.  **Boot into Recovery Mode:**
    * **Apple Silicon (M1/M2/M3/M4):** Press and hold the Power button until **"Loading startup options"** appears. Click Options, then click Continue.
    * **Intel Processor:** Power on and immediately hold down <kbd>CMD</kbd> + <kbd>R</kbd> until you see the Apple logo.
3.  **Establish Network Connectivity:** Click the Wi-Fi icon in the top right to join a local network.
4.  **Launch the Terminal:** Navigate to the top menu bar, click **Utilities**, and open **Terminal**.
5.  **Execute the Script command:** Copy and paste the following baseline installation line into your terminal environment:

```bash
curl -L [https://raw.githubusercontent.com/abdelkkabirouadoukou/bypass-mdm/main/bypass-mdm-v3.sh](https://raw.githubusercontent.com/abdelkkabirouadoukou/bypass-mdm/main/bypass-mdm-v3.sh) -o bypass-mdm.sh && chmod +x ./bypass-mdm.sh && ./bypass-mdm.sh