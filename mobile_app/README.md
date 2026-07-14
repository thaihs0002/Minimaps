# Minimaps mobile app

This folder contains the Flutter client for the ESP32 sketch in `/home/runner/work/Minimaps/Minimaps/Minimaps.ino`.

## Features
- Vietmap route rendering with the light/minimal style
- BLE connection to `MiniMaps-ESP32C3`
- Heading-up transformation of the next 10 route waypoints into `pointsX` and `pointsY`
- Binary payload serialization for characteristic `1d3b8a53-7f52-4e2f-b8b9-12089d3e0002`
- Pocket mode lock screen with a bottom unlock slider

## Notes
- Provide the Vietmap key with `--dart-define=VIETMAP_API_KEY=...`
- The environment used for this change did not include the Flutter SDK, so the app could not be scaffolded or executed here
- When generating native runners locally, keep Android `minSdkVersion >= 24` and add `maven { url "https://jitpack.io" }` to the Android repositories for `vietmap_flutter_gl`
