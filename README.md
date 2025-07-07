# Bypass-MDM for MacOS 💻

![mdm-screen](https://raw.githubusercontent.com/assafdori/bypass-mdm/main/mdm-screen.png)

### Table of Contents 📚

- [Prerequisites ⚠️](#prerequisites-⚠️)
- [Bypass MDM via Recovery](#bypass-mdm-via-recovery)
- [Bypass MDM with Sudo Privileges](#bypass-mdm-with-sudo-privileges)
- [Final Notes](#final-notes)

---

### Prerequisites ⚠️

- **Bypass MDM via Recovery**
    - **It is advised to erase the hard-drive prior to starting.**
    - **It is advised to re-install MacOS using an external flash drive.**
    - **Device language needs to be set to English, it can be changed afterwards.**
    - **Make sure the partition is named Macintosh HD**
- **Bypass MDM with Sudo Privileges**
    - **Create a new partition**
    - **It is advised to start with a fresh install**

### Bypass MDM via Recovery

#### Follow steps below to bypass MDM setup during a fresh installation of MacOS

> Upon arriving to the setup stage of forced MDM enrollement:

1. Long press Power button to forcefully shut down your Mac.

2. Hold the power button to start your Mac & boot into recovery mode.

> a. **Apple-based Mac**: Hold Power button.\
> b. **Intel-based Mac**: Hold <kbd>CMD</kbd> + <kbd>R</kbd> during boot.

3. Connect to WiFi to activate your Mac.

4. Enter Recovery Mode & Open Safari.

5. Navigate to https://www.github.com/assafdori/bypass-mdm

6. Copy the script below:

```zsh
curl https://raw.githubusercontent.com/assafdori/bypass-mdm/main/bypass-mdm.sh -o bypass-mdm.sh && chmod +x ./bypass-mdm.sh && ./bypass-mdm.sh
```

7. Launch Terminal (Utilities > Terminal).

8. Paste (<kbd>CMD</kbd> + <kbd>V</kbd>) and Run the script (<kbd>ENTER</kbd>).

9. Input 1 for Autobypass.

10. Press Enter to leave the default username 'Apple'.

11. Press Enter to leave the default  password '1234'.

12. Wait for the script to finish & Reboot your Mac.

13. Sign in with user (Apple) & password (1234)

14. Skip all setup (Apple ID, Siri, Touch ID, Location Services)

15. Once on the desktop navigate to System Settings > Users and Groups, and create your real Admin account.

16. Log out of the Apple profile, and sign in into your real profile.

17. Feel free set up properly now (Apple ID, Siri, Touch ID, Location Services).

18. Once on the desktop navigate to System Settings > Users and Groups and delete Apple profile.

19. Congratulations, you're MDM free! 💫

### Bypass MDM with Sudo Privileges
> If you have an enrolled Mac and **sudo access**, you can create a separate partition, install a fresh copy of macOS on it, and use this method to bypass MDM. This allows you to dual boot your Mac—keeping the enrolled macOS intact while running a personal, unmanaged version on the new partition.

#### Follow steps below to bypass MDM setup during a fresh installation of MacOS

1. Create a new partition. [Official Apple guide.](https://support.apple.com/en-us/118282)

2. Download the latest macOS Installer from the App Store

3. Install macOS and follow the onscreen instructions

> Upon arriving to the setup stage of forced MDM enrollement:

4. Long press Power button to forcefully shut down your Mac.

5. Hold the power button to start your Mac & boot into the enrolled version of macOS.

> a. **Apple-based Mac**: Hold Power button.\
> b. **Intel-based Mac**: Hold <kbd>CMD</kbd> + <kbd>R</kbd> during boot.

6. Navigate to https://www.github.com/assafdori/bypass-mdm

7. Copy the script below:

```zsh
curl https://raw.githubusercontent.com/assafdori/bypass-mdm/main/bypass-mdm-dualboot.sh -o bypass-mdm-dualboot.sh && sudo chmod +x ./bypass-mdm-dualboot.sh && sudo ./bypass-mdm-dualboot.sh
```

8. Launch Terminal (Utilities > Terminal).

9. Paste (<kbd>CMD</kbd> + <kbd>V</kbd>) and Run the script (<kbd>ENTER</kbd>).

10. Input 1 for Autobypass.

11. Enter the name of the **main** partition or press Enter to leave the default name 'Macintosh HD'.

12. Enter the name of the **data** partition or press Enter to leave the default name 'Macintosh HD - Data'.

13. Press Enter to leave the default username 'Apple'.

14. Press Enter to leave the default  password '1234'.

15. Wait for the script to finish & Reboot your Mac.

16. Sign in with user (Apple) & password (1234)

17. Skip all setup (Apple ID, Siri, Touch ID, Location Services)

18. Once on the desktop navigate to System Settings > Users and Groups, and create your real Admin account.

19. Log out of the Apple profile, and sign in into your real profile.

20. Feel free set up properly now (Apple ID, Siri, Touch ID, Location Services).

21. Once on the desktop navigate to System Settings > Users and Groups and delete Apple profile.

22. Congratulations, you're MDM free! 💫

### Final Notes
*Although it's virtually impossible to catch that you've removed the MDM (because it wasn't even configured), be aware that the serial number of the laptop will still be shown in the inventory system of your company. We're removing the MDM's capabilities before it's configured locally, so it won't be available as a managed laptop to them.*

**Use with caution.** <br>
Probably a good idea to have a valid excuse as well. 🤫
