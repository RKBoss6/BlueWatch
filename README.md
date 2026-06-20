# BlueWatch
An open-source iOS app for watches like Bangle.js.
More info coming soon!


Bangle.js info: [https://banglejs.com/](https://banglejs.com/)

Find the related Bangle.js app that facilitates communications between the Bangle and this app [here](https://banglejs.com/apps/?id=bluewatch)!
## Quick-start
1. Open the app
2. Authorize required permissions for app to work properly
3. Select your device and follow prompts on-screen
4. Once device is selected, the app will begin scanning for that device near you. Ensure it is turned on, and BLE is powered on for both devices.
5. The app will initiate device pairing
6. Once device is paired, you're good to go!


## Privacy Policy
We do not collect, store, use, or sell any user data. All data is stored only on-device, and is not sent anywhere else.

## Support
BlueWatch is open-source! The entire codebase is in this GitHub Repository, feel free to take a look. For any questions or suggestions, feel free to [open an issue](https://github.com/RKBoss6/BlueWatch/issues/new).

## Legal Info
BlueWatch is developed and maintained with the knowing consent and authorization of Pur3 Ltd. Pur3 Ltd is the owner of the Espruino and Bangle.js software and trademarks, and have authorized the use of these trademarks and hardware for BlueWatch.

## Notes
- BlueWatch rate-limits WeatherKit API calls to 10 minutes. This means that if you request to push weather to your watch and it already has pushed it less than 10 minutes ago, it will ignore your request until you or the watch requests again after 10 minutes have elapsed.

- Currently, the Find My Phone feature requires your phone to be unmuted, and is not very stable (wil be fixed soon!)

Anyone can contribute and suggest changes! Just open an issue :)

