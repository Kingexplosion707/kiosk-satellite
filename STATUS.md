# Kiosk Satellite Plus: status

Behnoud's personal build of Kiosk Satellite (jxlarrea/kiosk-satellite, CC BY-NC-ND 4.0). Personal use only.

## Changes from the original
- **Home screen** (`app/lib/ui/plus_home.dart`): a native home in front of the Home Assistant dashboard, which stays loaded underneath (Voice Satellite keeps working). Clock and date, At a Glance chips, the playing song's lyrics, the song with its controls, and tiles for Home Assistant, Music, Apps, Settings and Screensaver. Back over the dashboard returns home; so does 5 minutes without a touch. A wake word hides the home for the voice UI and brings it back after.
- **Spicy Lyrics Plus** (`app/lib/ui/plus_spicy.dart`, `BackgroundBridge.kt`): reads Spicy's now playing (its `NowPlayingProvider`).
  - Lyrics on the home, word by word in Spicy's manner; the kiosk's own synced lines when Spicy has none for the song.
  - The record's animated cover on the now-playing card, and the song's Spotify Canvas behind the home.
  - The screensaver is Spicy's always-on display (landscape layout, screen brightness kept). A tap closes it back to the home. Without Spicy installed the kiosk's own screensaver runs.
- **Builds**: `.github/workflows/plus-build.yml` builds on every push to main and publishes a release with the APK, signed with the `KIOSK_PLUS_KEYSTORE_BASE64` secret. Upstream's release and issue workflows were removed.
- **Updates**: `.github/workflows/upstream-sync.yml` merges jxlarrea/kiosk-satellite into main every six hours, then builds. A conflict opens an issue labelled upstream-sync.

## Installing
Uninstall the original Kiosk Satellite first (different signing key); the app ID is unchanged. Spicy Lyrics Plus needs to be installed before the kiosk for the now-playing permission (or reinstall the kiosk after).
