# PortaBill for iOS

A native SwiftUI rebuild of the Android **PortaBill** field meter-reading app (the APK was a .NET MAUI app).
iOS 17+, Swift 5.9+, Xcode 15.3+. No third-party dependencies.

## Run it

**Option A – XcodeGen (one command)**
```
brew install xcodegen
cd PortaBill-iOS && xcodegen generate && open PortaBill.xcodeproj
```

**Option B – manually**
1. Xcode → File → New → Project → iOS App (SwiftUI, Swift), name it `PortaBill`, minimum iOS 17.
2. Delete the generated `ContentView.swift` and `PortaBillApp.swift`.
3. Drag the `PortaBill/` folder from this repo into the project (copy items, create groups).
4. Target → Info, add these keys:
   - `NSCameraUsageDescription` – "PortaBill uses the camera to photograph meters as proof of reading."
   - `NSPhotoLibraryAddUsageDescription` – "PortaBill saves meter photos to your photo library."
   - `NSPhotoLibraryUsageDescription` – "PortaBill lets you attach an existing photo of a meter."
5. Run on an iPhone (the camera and torch need a real device).

**Demo mode** is on by default (`AppConfig.useMockApi = true`): sign in with any staff ID and any password except `wrong`.
Entering a reading of exactly `0` is rejected by the fake server so you can see the "Needs correction" flow.

## What was ported

| Android screen / feature | iOS |
|---|---|
| Login (staff ID + password, show/hide) | `LoginView` |
| Assigned areas: greeting, day strip, progress hero, area cards | `AreasView` |
| Accounts in an area: progress, alert messages, Elec/Water/Net chips | `AccountsView` (+ search, added) |
| Reading entry: category tabs, previous reading, validation, total/avg per day, margin alert, photo (camera/gallery/torch), quick comment, contacts (call/SMS), bill history, "save & next" | `ReadingEntryView` |
| Offline queue: waiting / needs-correction states, sync now, auto-retry | `QueueView`, `SyncService` |
| Sign out blocked while unsynced readings exist | `SignOutView` |
| SQLite storage | JSON files in Application Support (`DataStore`), photos stored as files |
| Connectivity checks, background sync | `NetworkMonitor`, `SyncService` (every 60 s + on reconnect) |

Differences by design: icons are SF Symbols (not the Phosphor font), the STELCO logo/branding assets are **not** included
(there's a placeholder bolt on the login screen), and an unsynced reading now survives a server refresh of an area.

## Things to verify (inferred, not read from source)

I rebuilt this from the structure, strings, endpoints and constants found in the APK, not from the original source,
so a few behaviours are my best reading and should be checked against the Android app:

1. **Margin alert** – flags per-day consumption more than 35 % (constant from the APK) above/below the average of the last
   6 bills (falls back to the previous period). The exact formula in the original may differ.
2. **Per-category rules** – X-factor applies to all categories, margin alert to electricity and water, decimals (3 places) to water only (`MeterCategory`).
3. **Live API JSON shapes** – endpoint paths and field names come from the APK, but request/response bodies are parsed
   leniently and unverified: login body, `PostSaveNewReading` (sent as JSON with the photo as base64 `FilBytes`),
   the `en_Type` value per category, and the `dbM` / `fmode` parameters of the bill-history call.
4. Status codes: 200 = accepted, 423 and 306 = rejected (from the APK).

## Going live

Edit `Config/AppConfig.swift`: set `useMockApi = false`, `apiBaseURL` and `appId`.
I deliberately did **not** copy the production URL or the app ID out of the APK; take them from your own configuration.
The app ID is sent with every reading, so keep it out of public repos.

## Status

Written without access to a Swift compiler, so it has not been built or run yet. I checked brace balance and cross-file
references, but expect to fix a few small compile errors on first build. Also add an app icon before shipping.
