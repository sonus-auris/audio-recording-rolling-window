# Audio Dashcam

Flutter Android/iOS app for continuous rolling audio capture. It records short `.m4a` segments, keeps the most recent local window on-device, and uploads segments to an S3-compatible bucket for a longer cloud window.

## Defaults

- Local retention: 50 hours
- Cloud retention: 500 hours
- Segment length: 1 minute
- Encoding: AAC-LC `.m4a`, mono, 16 kHz, 64 kbps
- Provider support: AWS S3 / S3-compatible PUT and DELETE is implemented. Google Drive, OneDrive, and iCloud Drive are selectable in the UI as saved configuration targets, but upload adapters are still placeholders.

## Storage Math

Audio size is controlled by bitrate:

```text
bytes = bitrate_bits_per_second / 8 * seconds
```

At the default 64 kbps:

- 1 minute is about 480 KB before container overhead.
- 50 hours is about 1.44 GB.
- 500 hours is about 14.4 GB.

At 128 kbps, 500 hours is about 28.8 GB.

## Runtime Notes

- Android uses a foreground microphone service while recording. The app asks for microphone permission and notification permission; it does not request storage, location, contacts, or battery optimization permissions.
- On Android 11+, microphone capture must be started while the app is foregrounded. After the foreground microphone service is running, the app can move to the background and continue recording under the visible notification. The app does not try to auto-start microphone capture from boot or from a background-only state.
- Android app backup is disabled so app-local audio and cloud configuration are not copied into device backups.
- iOS uses microphone permission and the `audio` background mode. iOS will still stop capture if the user force-quits the app or the OS terminates it.
- Local files are stored inside the app support directory. The segment index is written atomically, and corrupt index files are quarantined instead of crashing startup. Old local files are deleted only after they are uploaded, so failed uploads do not silently discard audio.
- Cloud retention deletes S3 objects older than the configured cloud window when credentials are available.
- Direct AWS S3 uploads require HTTPS and lowercase DNS-safe bucket names using letters, numbers, and hyphens. Custom S3-compatible endpoints must also use HTTPS.
- S3 uploads and deletes time out instead of hanging the queue indefinitely.
- S3 access keys, secret keys, and session tokens are stored with Flutter Secure Storage using Android secure storage and non-migrating iOS keychain accessibility.
- For production, prefer temporary scoped credentials or a presigned-upload broker over long-lived AWS keys on the device.

## S3 IAM Shape

Use a bucket/prefix scoped principal. The app needs:

- `s3:PutObject` for uploads
- `s3:DeleteObject` for cloud retention deletion

If a later cloud playback browser needs listing, add `s3:ListBucket` scoped to the app prefix.

## Development

Flutter was installed locally at:

```sh
/Users/maca5/development/flutter
```

Run checks:

```sh
/Users/maca5/development/flutter/bin/flutter analyze
/Users/maca5/development/flutter/bin/flutter test
```

Run on a configured device:

```sh
/Users/maca5/development/flutter/bin/flutter run
```

This machine currently needs Android SDK setup for Android builds, and full Xcode plus CocoaPods for iOS builds.

## Emulator Validation

An Android API 36 ARM64 emulator named `audio_dashcam_api36` was created with microphone input enabled.

Verified on that emulator:

- Debug APK builds and installs.
- `RECORD_AUDIO`, `POST_NOTIFICATIONS`, `FOREGROUND_SERVICE`, and `FOREGROUND_SERVICE_MICROPHONE` are declared/granted.
- Starting capture from the foreground creates an Android foreground service with microphone type `0x00000080`.
- After sending the app Home, the foreground service remained alive past multiple one-minute segment rotations.
- `.m4a` segment files were written under the app sandbox at roughly 489 KB per minute, matching the default 64 kbps encoding.
- `segments.v1.json` was updated with closed segment metadata.

Observed emulator limitation:

- The Android emulator audio HAL logged repeated `pcm_readi` I/O errors. Android's own MediaRecorder documentation says emulator audio recording is not a substitute for a real recording device, so final audio-quality validation still needs a physical Android phone.
