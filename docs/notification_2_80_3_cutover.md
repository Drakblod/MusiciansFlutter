# Notification V2 cutover for 2.80.3+256

This plan is for review. The release uses one controlled cutover, with the final RTDB rules from `database.rules.json` and the exact 26 Functions in `firebase_functions/scripts/notification_2_80_3_manifest.json`. That file distinguishes the 58 discovered endpoints from the selected deployment targets. Both existing rules files already contain final notification denials. Keep the deployed rules in place until the final rules step below. Historical release manifests remain evidence for their own releases.

Unsupported clients, including iOS 2.66 and Web 2.80.2, lose new notifications, the legacy Notification Center, and notification badges at cutover. The owner accepted this impact until those clients upgrade. There is no enrollment phase against legacy producers for upgraded installations.

## macOS handoff

Use the reviewed source for this candidate and Flutter 3.35.1, the SDK pinned by Pages. On the Mac, select Xcode 26 or later with the iOS 26 SDK and use the release team's existing signing assets. Runner's bundle identifier is `com.musiciansonly.musicians`. Runner and CocoaPods target iOS 15, the minimum of the locked FlutterFire plugins. [Apple upload requirements](https://developer.apple.com/news/upcoming-requirements/)

```sh
xcode-select -p
xcodebuild -version
xcodebuild -showsdks
flutter --version
flutter doctor -v
pod --version
security find-identity -v -p codesigning
flutter pub get
flutter build ios --release --config-only --no-codesign --build-name 2.80.3 --build-number 256
(cd ios && pod install)
open ios/Runner.xcworkspace
```

In Xcode, select the Runner scheme and the intended Apple Developer team for Runner. Verify the App ID and Push Notifications capability, the distribution certificate and its provisioning profile, and the approved Firebase configuration. Record the resolved `Podfile.lock` and tool versions with the Mac build evidence. If CocoaPods reports stale specs, retry with `pod install --repo-update` and review the resulting lockfile. Use `pod install` for subsequent builds with that lockfile.

Build and export locally once signing is configured. Leave `ENABLE_MAP_VIEW` and `ENABLE_LIVE_BROADCASTS` unset.

```sh
flutter build ios --release --no-codesign --build-name 2.80.3 --build-number 256
flutter build ipa --release --build-name 2.80.3 --build-number 256 --export-method app-store
```

Inspect the archive and exported IPA from the same run. These checks require a valid signature, the expected version and bundle ID, exactly one copy of each cue at the root of each native bundle, and the reviewed bytes.

```sh
set -eu
archive_app=build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app
set -- build/ios/ipa/*.ipa
test "$#" -eq 1
test -f "$1"
inspect_dir="$(mktemp -d)"
unzip -q "$1" -d "$inspect_dir"
export_app="$inspect_dir/Payload/Runner.app"
for app in "$archive_app" "$export_app"; do
  codesign --verify --deep --strict "$app"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")" = com.musiciansonly.musicians
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist")" = 2.80.3
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist")" = 256
  while read -r hash wav; do
    test -f "$app/$wav"
    test "$(find "$app" -type f -name "$wav" -print | wc -l | tr -d ' ')" -eq 2
    printf '%s  %s\n' "$hash" "$app/$wav" | shasum -a 256 -c -
    printf '%s  %s\n' "$hash" "$app/Frameworks/App.framework/flutter_assets/assets/audio/$wav" | shasum -a 256 -c -
  done <<'WAV_HASHES'
fa847191acb4c6b3ce73f0a985d87ac76734a0031039365195abd37eb093680d notification_gig_request_v2.wav
5df676f51c9707dc92734de2f95e22134e1fbc1af39a957aab108cf9c7ebed4f notification_gig_response_v2.wav
a08a50704999a843bbbdd40c374889e8c8b66f2852979bd1ffecdaa688a5d4b5 notification_event_rsvp_v2.wav
8ff200758efcabfbc7ef3084b648fc60829c6d251216de6d4897c548708c0f45 notification_gig_confirmed_v2.wav
WAV_HASHES
done
codesign -d --entitlements :- "$export_app" > "$inspect_dir/signed-entitlements.plist"
security cms -D -i "$export_app/embedded.mobileprovision" > "$inspect_dir/profile.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :aps-environment' "$inspect_dir/signed-entitlements.plist")" = production
test "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:aps-environment' "$inspect_dir/profile.plist")" = production
signed_app_id="$(/usr/libexec/PlistBuddy -c 'Print :application-identifier' "$inspect_dir/signed-entitlements.plist")"
test "$signed_app_id" = "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$inspect_dir/profile.plist")"
case "$signed_app_id" in *.com.musiciansonly.musicians) ;; *) exit 1 ;; esac
codesign -dv --verbose=4 "$export_app"
shasum -a 256 "$1"
```

Each cue is present once as a native sound and once as a Flutter tester preview. Compare the displayed signing team and certificate with the approved distribution identity, and verify the provisioning profile is current. Keep the archive, IPA, checksums, and signing evidence locally. For later authorized TestFlight submission, open the archive in Xcode Organizer and use **Distribute App → App Store Connect**, or use the verified IPA in Transporter. Confirm the existing app record, version 2.80.3, and build 256 before upload. The local preparation stops before upload. [Apple upload options](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)

Complete physical-device sound and notification QA using an approved test environment. Check ownership after account switching and deletion, the four custom cues and the Band Section system fallback, locked/background delivery, cold-start and foreground routing, and badges. The Android APK built by the repository's current Gradle configuration uses debug signing for local QA. Use the approved Android distribution signing process for a distributable artifact.

## Release window

The four owner-polish updates are commitUserCity, onCatalogueUserWritten, onBandEventReadModelWritten, and onBandMemberWritten. Offline discovery must report 58 endpoints. The filtered Firebase planner must report four creates, 22 updates, and zero deletes or replacements, all in europe-west1. The generated target list is the source for the eventual authorized deployment.

From a clean candidate checkout with Node 22.13.1, run the snapshot check with paths to the installed npm and Firebase CLI JavaScript entry points.

```sh
python firebase_functions/scripts/prepare_preview_snapshot.py build/notification-cutover --npm-cli "$NPM_CLI" --firebase-cli "$FIREBASE_CLI"
```

Review `deployment-actions.json` and `deployment-plan.json` from the snapshot. Generate each later `--only` selector by prefixing its exact target with `functions:`. Stop if the production deployment proposes any other identity, region, removal or replacement.

The owner can rename or clear the Music Snippet title and URL together. Older clients that clear only the URL may be denied once a saved title exists. Untitled clips display Music snippet. No migration or backfill is needed.

Account deletion keeps the existing band discovery and departure flow. It revokes the deleting account's Notification V2 bindings before clearing its V2 feed, routes, and signal. Auth deletion remains last. The revocation transaction preserves any installation already transferred to a different account. The two reviewed rules variants check the revocation at commit for the restricted server writer on the existing V2 feed, route and signal paths. A delayed V2 writer cannot repopulate them after revocation. Historical legacy notification rows remain stored. The V2 cleanup is repeatable and the legacy account and band operations retain their existing retry limits.

1. Confirm the compatible signed iOS and Android artifacts and the matching Web build. Confirm the 26 reviewed names, region, rules file, and expected cutover impact.
2. Deploy only the 26 named Functions in the reviewed cutover manifest. Exclude `checkEventReminders`. Leave its existing scheduler paused and create no replacement.
3. Verify every selected Function is ACTIVE and healthy on the reviewed revision before moving to rules.
4. Deploy only `database.rules.json` as the final active RTDB rules. The new V2 writer fails closed against the earlier rules. Keep the Functions-to-rules interval short and expect a notification-delivery gap during that interval. Complete write-path smoke tests after final rules are active.
5. Push the approved versioned Web client to main and verify the Pages deployment reports 2.80.3 build 256.
6. Enroll test installations and smoke-test Android, iOS, and Web. Confirm neutral native alerts, correct sound and fallback, exact routing, badges, and account-deletion revocation. Verify Map and Live remain disabled.
7. Leave historical legacy rows stored behind denied reads. There is no cleanup, backfill, migration, or data reset.

If an earlier gate fails, stop the window before advancing. Resolve a partial Functions deployment with the reviewed V2 revisions. After final rules are active, preserve the legacy feed and token denials. If delivery fails, pause or disable affected sends through a separately authorized V2-compatible revision. Restore only a verified V2-compatible client or a Function revision that preserves the V2 revocation write fence. Keep the paused reminder scheduler out of rollback.

## ACCOUNT-DELETION-LIFECYCLE-HARDENING-02 — DEFERRED

Resolve this separate security and privacy task before broad public launch. The 2.80.3 Notification V2 preview retains the following pre-existing risks.

- An interruption after canonical deletion of a sole-member band can leave band room, section conversation, or membership operation ledger data orphaned.
- A delayed `onBandMemberWritten` can recreate membership indexes and band room membership after retirement.
- A delayed `onCatalogueBandWritten` can recreate the public band projection.
- Delayed `onBandEventReadModelWritten`, `onLegacyBandCalendarEventWritten`, and `onBandEventWritten` can recreate derived Event or Calendar data.
- A comprehensive repair requires coordinated commit-time fencing or a schema redesign across the Admin writers. A database reset cannot prevent future deletion races.

The 26-target preview includes onBandMemberWritten and onBandEventReadModelWritten for readiness checks only. Their existing deletion races remain deferred. mutateBandMembership, deleteBand, onCatalogueBandWritten, onLegacyBandCalendarEventWritten, and onBandEventWritten stay outside the cutover.
