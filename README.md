# Bypass-MDM for MacOS 💻

#### Prerequisite ⚠️

- **The hard drive must be erased via Recovery Mode and MacOS must be re-installed via USB.**

#### Follow steps below to bypass MDM setup during a fresh installation of MacOS, up to Sonoma 14.3.1 (23D60).

> Upon arriving to the setup stage of forced MDM enrollement:

1. Long press Power button to forcefully shut down your Mac.

2. Hold the power button to start your Mac & boot into recovery mode.

> a. **Apple-based Mac**: Hold Power button.\
> b. **Intel-based Mac**: Hold CMD+R during boot.

3. Connect to WiFi to activate your Mac.

4. Enter Recovery Mode & Open Safari.

5. Navigate to https://www.github.com/assafdori/bypass-mdm

6. Copy the script below:

```zsh
curl https://raw.githubusercontent.com/assafdori/bypass-mdm/main/bypass-mdm.sh -o bypass-mdm.sh && chmod +x ./bypass-mdm.sh && ./bypass-mdm.sh
```

7. Launch Terminal (Utilities > Terminal).

8. Paste (CMD + V) and Run the script (Enter).

9. Choose 1 for Autobypass.

10. Press Enter to leave the default username 'Apple'.

11. Press Enter to leave the default  password '1234'.

12. Wait for the script to finish & Reboot your Mac.

13. Sign in with user (Apple) & password (1234)

14. Skip all setup (Apple ID, Siri, Touch ID, Location Services)

15. Once on the desktop navigate to System Settings > Users and Groups, and create your real Admin account.

16. Log out of the Apple profile, and sign in into your real profile.

17. Feel free set up properly now (Apple ID, Siri, Touch ID, Location Services).

18. Once on the desktop, delete Apple profile.

19. Congratulations, you're MDM free! 💫

20. #### I take zero responsibility if anything happens to your computer or if you get caught trying to bypass the MDM system, although it's virtually impossible to catch, as we're removing the MDM's capabilities before it's even configured. Still, use with caution. This was developed solely as Proof of Concept.
