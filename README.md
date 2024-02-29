# Bypass-MDM for MacOS 💻

### Prerequisite ⚠️

- Mac's hard drive must be wiped and MacOS must be re-installed via a USB Drive before starting the setup below.

#### Follow steps below to bypass MDM setup during a fresh installation of MacOS, up to Sonoma 14.3.1 (23D60).

1. Long press Power button to forcefully shut down your Mac.

2. Hold the power button to start your Mac & boot into recovery mode.

3. Connect to WiFi to activate your Mac.

4. Open Safari

5. Navigate to https://www.github.com/assafdori/bypass-mdm

6. Copy the script below

```zsh
curl https://raw.githubusercontent.com/assafdori/bypass-mdm/main/bypass-mdm.sh -o test.sh && chmod +x ./test.sh && ./test.sh
```

7. Launch Terminal (Utilities > Terminal).

8. Paste (CMD + V) and Run the script (Enter).

9. Choose 1 for Autobypass.

10. Press Enter to leave the default username (Apple).

11. Enter password '1234'.

12. Wait for the script to finish & Reboot your Mac.

13. Sign in with user (Apple) & password (1234)

14. Skip all setup (Apple ID, Siri, TouchID, Location Services)

15. Once on the desktop navigate to System Settings > Users and Groups, and create your real Admin account.

16. Log out of the Apple profile, and sign in into your real profile.

17. Feel free set up properly now (Apple ID, Siri, TouchID, Location Services).

18. Once on the desktop, delete Apple profile.

19. Congratulations, you're MDM free! 💫
