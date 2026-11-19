# TJ Racing 3D — Flutter ↔ Unity message contract (v1.0.31)

The single source of truth for what the Flutter side sends to Unity
and what Unity sends back. VERIFIED 19 Nov 2026 against the Unity
source (`~/workspace/tj-racing/Assets/Scripts/TJRacing/` —
`FlutterBridge.cs`, `RaceResult.cs`, `RaceManager.cs`,
`Ads/UnityAdsManager.cs`, `UI/MenuUI.cs`, `UI/ResultsUI.cs`,
`UI/RaceHUD.cs`, `Config/RacingConfig.cs`). The Flutter half is
built (`lib/screens/tj_racing_play_screen.dart`,
`lib/games/tj_racing/unity_bridge.dart`).

## UI ownership (read this first)

- **Unity owns ALL game UI**: MainMenu scene (menu, garage with
  hero car, coins pill, LEVEL pill, RACE button), Race_NightCity
  scene (race, HUD, pause menu, results screen), banner (auto on
  Unity Ads init), race interstitials (after Continue, never after
  a win), rewarded ad display.
- **Flutter owns**: the host screen, config/balances/unlocks sent
  over the bridge, every coin operation (server-side), the unlock /
  Watch Ad dialogs, the Flutter settings sheet (sensitivity,
  control mode, re-calibrate), and the Rs overlay on Unity's
  results screen (ResultsUI.cs: "The Rs value is FLUTTER's job").
- Flutter NEVER shows a race result screen of its own, NEVER shows
  a rewarded ad itself, NEVER triggers a race interstitial, and
  NEVER starts a race (Unity's own RACE button does).

## Versions (pinned — do not change without a Flutter rebuild)

- Unity **2022.3.62f2 or newer** (2022.3 LTS). The plugin
  (`flutter_embed_unity` 2.0.0 +
  `flutter_embed_unity_2022_3_android` 2.0.0) requires 2022.3.62f2+
  on Android (security advisory) and 2022.3.56+ for the Android 15
  16KB page-size rule. Do NOT use Unity 6000 for this build.
- Flutter 3.47.8, `flutter_embed_unity` 2.0.0.
- Unity project must import the `flutter_embed_unity_2022_3`
  package (FlutterEmbed scripts — `SendToFlutter.cs` is REQUIRED)
  from the plugin releases, and export via
  `Flutter Embed -> Export project to Flutter app` (android) into
  `<flutter project>/android/unityLibrary`.
- Player Settings: scripting backend IL2CPP, target architectures
  ARMv7 + ARM64, target API = the Flutter app's targetSdk.
- VERSION SKEW TO VERIFY AT WIRING: the Unity project vendors the
  flutter_embed_unity Unity-side scripts v1.4.0, while the Dart
  package is 2.0.0. The message channel (`SendToFlutter.Send` +
  `SendMessage("FlutterBridge","OnFlutterMessage",...)`) is the same
  mechanism in both, but confirm the 1.4.0 scripts work with the
  2.0.0 Dart package on the first wired build (if the exporter or
  the glue changed, upgrade the vendored scripts to the 2.0.0
  release asset).

## Transport (the doc's API names are stale — read this)

`docs/FLUTTER_INTEGRATION.md` names the OLD `flutter_unity_widget`
API (`UnityWidget.postMessage`, `onUnityMessage`). The real package
in this app is `flutter_embed_unity` 2.0.0, whose Dart API is the
`EmbedUnity` widget + top-level `sendToUnity(gameObject, method,
data)` (+ `pauseUnity`/`resumeUnity`). The Unity C# side is
UNAFFECTED: `sendToUnity("FlutterBridge", "OnFlutterMessage",
json)` delivers exactly
`SendMessage("FlutterBridge", "OnFlutterMessage", json)`, which is
what `FlutterBridge.OnFlutterMessage(string)` expects. Only the
Dart call shape differs — the wire protocol below is identical.

## Flutter → Unity

Envelope (EVERY message): `{"method": "<name>", "payload":
"<JSON string>"}` — `payload` MUST be a JSON-encoded string
(a nested object serialised to a string), because Unity's
`JsonUtility` cannot parse a nested raw object here.
`UnityBridge.send(method, payload)` builds it.

GameObject: **`FlutterBridge`**, method: **`OnFlutterMessage`**.

| Method | Payload | When |
|---|---|---|
| `SetConfig` | `{config: "<games.tj_racing JSON string>", level, levelCoins, adCoins, rsValue, totalEarnedRs}` | At Unity launch (staggered re-sends — see below) and on balance/config change. `config` is the FULL block from `TjRacingConfig.toJson()` (exact Unity key shape). `level` = Flutter's player level (1 + finished~/3; level ≥ 3 → lap-3 road traffic). `rsValue` e.g. "Rs 12", `totalEarnedRs` e.g. "Rs 37" — Unity displays them verbatim, never computes Rs. |
| `SetSelectedCar` | `{carId}` | At launch (Flutter's cached selection) + after an unlock. NOTE: garage selection changes inside Unity are local-only (MenuUI never tells Flutter). |
| `SetUnlockedCars` | `{carIds: [...]}` | At launch + after any unlock. Unlock state is decided by FLUTTER, never Unity. `street_hawk` always included. |
| `SetBalances` | `{levelCoins, adCoins, rsValue, totalEarnedRs}` | After any balance change (incl. after a race is credited server-side). |
| `SetSensitivity` | `{value}` 0.5–2.0 | Tilt sensitivity slider (Flutter settings sheet). Unity polls `FlutterBridge.TiltSensitivity` every frame. |
| `SetControlMode` | `{value: "tilt" \| "buttons" \| "both"}` | Control-mode switch. NOTE: the field is `value`, not `mode`. Unity default is `"both"`. |
| `RecalibrateTilt` | `{}` | Re-calibrate button (Flutter settings). Unity also auto-calibrates at every race start. |
| `StartRace` | `{carId, level}` | NOT sent by Flutter in v1 — Unity's own RACE button drives starts (`OnStartRaceRequested` also has no Unity subscriber yet — see gaps). |
| `QuitToMenu` | `{}` | Back button / close. Flutter pops the screen itself (see gaps). |
| `ShowRewardedAd` | `{requestId}` | Opt-in rewarded prompt (unlock dialog "Watch Ad"). Unity shows the ad; completion is reported back — Flutter credits afterwards, keyed by `requestId`. |

**SetConfig timing — no ready signal exists.** Unity sends
nothing when it finishes loading, so Flutter sends the trio
(`SetConfig` + `SetUnlockedCars` + `SetBalances`, plus
`SetSelectedCar`/`SetSensitivity`/`SetControlMode`) immediately
and re-sends at 0.5s / 2s / 5s after the screen opens, and again
on every balance change. `SetConfig` is idempotent; repeats are
harmless. (Messages sent before Unity loads are dropped silently
by the player — that is why the stagger exists.)

**CAR STATS TRAP (verified in `RacingConfig.cs`):** Unity parses
the config with `JsonUtility.FromJson<RacingConfig>`, which keeps
the C# field initializers (180 km/h / 12 / 1.0 / 100) for any key
Flutter omits. If Flutter sent cars WITHOUT stats, EVERY car would
drive at 180 km/h and the progression would be dead. Flutter
therefore ALWAYS sends the full stats per car
(`topSpeedKmh`, `acceleration`, `handling`, `nitroCapacity`,
`bodyColorHex` — defaults = Unity's `CarCatalogue` table) in
`TjRacingConfig.toJson()`. Never strip them.

## Unity → Flutter

Unity sends with `SendToFlutter.Send(jsonString)` (from the
`FlutterEmbed` package). ONE JSON object per message, parsed by
`UnityIncoming.parse` (see `unity_bridge.dart`).

| `type` | Fields | Flutter action |
|---|---|---|
| `race_result` | `race_id` (Unity Guid, no dashes), `track_id`, `car_id`, `position` (1–6), `total_racers` (6), `laps_completed`, `race_time_secs`, `best_lap_secs`, `level_coins_earned` (INFO ONLY: 10/5/0), `is_first_race` | Call server `claim-race-level` with `race_id` + `position` + `laps_completed`. **Re-derive the coins server-side; never trust `level_coins_earned`.** Credit once per `race_id`, enforce the 200/day cap server-side. Then refresh balances, send `SetBalances`, and show the Flutter Rs overlay on Unity's results screen. |
| `race_started` | `race_id`, `detail` (JSON string: `{"track":"night_city_1","laps":3}`) | Informational only (Flutter never starts races). |
| `race_cancelled` | `race_id`, `detail` `"{}"` | Player quit mid-race — no credit, no Flutter action (Unity is back at its menu). |
| `rewarded_completed` | `placement` = `BP_Rewarded_Android`, `detail` (JSON string: `{"requestId":"..."}`) | Claim Ad Coins server-side via `claim-ad-reward` keyed by `requestId` (idempotency). **Unity never credits anything.** Then refresh balances + `SetBalances`. |
| `rewarded_failed` | `placement`, `detail` (`{"requestId":"...","reason":"..."}`) | Show "ads unavailable, try later". |
| `interstitial_shown` | `placement`, `detail` `"{}"` | Analytics only (debug log). |
| `car_locked_tapped` | `detail` (JSON string: `{"carId":"night_falcon","price":200}`) | Player tapped a locked car in Unity's garage — Flutter shows the unlock dialog (Unlock with Ad Coins via `spend-race-item`, or Watch Ad → `ShowRewardedAd`). |

Any other message is ignored. A `race_result` for a duplicate
`race_id` or `laps_completed` below the configured laps is
ignored client-side too (the server also enforces once-per-race
and the daily cap — the client never trusts Unity's numbers for
anything but display + the claim call).

## Coins (the rule that must never break)

- **Level Coins** (cash): ONLY from the server `claim-race-level`
  response. Win 10, 2nd 5, 3rd/finish 0, daily cap 200
  (all from remote config `games.tj_racing.level_coins`).
  Never spent in-game. Never converted.
- **Ad Coins** (in-game only): ONLY from a completed rewarded ad
  via the server `claim-ad-reward`. Spent ONLY on cars/power-ups
  via the server `spend-race-item`. Never cash, never convertible.
- **Real-money purchase is FUTURE** (after the Play Store upload):
  do NOT build IAP in v1.

## Ads

- Game ID `800417967`; placements `BP_Banner_Android` (top strip,
  passive, auto on Unity Ads init), `BP_Interstitial_Android`,
  `BP_Rewarded_Android`.
- Interstitial rules live in Unity (`UnityAdsManager` +
  `ResultsUI`): every 3rd race, max 1 per 3 min, only after
  Continue on the results screen, 90 s gap from any ad. Flutter
  does NOT trigger race interstitials. Article interstitials,
  App Open and the shell banner stay Flutter-side
  (`UnityAdsService`).
- DUAL ADS INIT (verify on device once wired): the Flutter
  plugin init AND Unity's own `UnityAdsManager` init both
  initialise Unity Ads with the same Game ID. That is the design
  per the Unity contract; confirm both coexist and article
  interstitials still show after a game session.
- Rewarded ads only at the moment of need (unlock dialog "Watch
  Ad") — never forced, never mid-race. No ad at game start.

## KNOWN UNITY GAPS (found 19 Nov 2026 by reading the Unity source — Unity agent to fix)

1. **No subscribers for `OnRewardedAdRequested` /
   `OnStartRaceRequested` / `OnQuitToMenuRequested`.**
   `FlutterBridge` fires these events, but nothing in the Unity
   project listens: `UnityAdsManager.ShowRewarded(requestId)` is
   never called from a Flutter message, and neither is
   `LoadRaceScene` / `LoadMenuScene`. So Flutter's
   `ShowRewardedAd` (and `StartRace` / `QuitToMenu`) currently do
   NOTHING inside Unity. Flutter works around the rewarded gap
   with a 30 s timeout ("ad not available") instead of hanging.
   Fix (Unity): subscribe `UnityAdsManager` to
   `OnRewardedAdRequested`, bootstrap scene loads to the other
   two. Until then, Watch Ad in the unlock dialog cannot pay out.
2. **No power-up shop UI in Unity.** `RacingConfig` carries the
   `powerups` list and Flutter's config + `spend-race-item` are
   ready, but no Unity UI offers a power-up purchase. Nothing to
   wire on the Flutter side until Unity adds the trigger.
3. **No car-selected event to Flutter.** MenuUI calls
   `ApplySelectedCar` locally; Flutter's cached selection can go
   stale (harmless: claims use the `car_id` in `race_result`).
4. **ResultsUI text nit:** "No coins this time — 2nd place or
   better earns coins" is wrong (2nd DOES earn 5). One-line Unity
   fix ("Win or 2nd place earns coins").
5. **Unity scripts v1.4.0 vs Dart package 2.0.0** (see Versions).

## Open items (not Flutter's to close)

1. **Unity export (THE open item) — parent action required:**
   (1) create the PUBLIC repo `mithubhattijani-commits/tj-racing`
   via browser (GitHub App create failed 403), (2) push
   `~/workspace/tj-racing/` (main, e0b3e67), (3) add the 3 Unity
   secrets (`UNITY_LICENSE` / `UNITY_EMAIL` / `UNITY_PASSWORD` —
   the user's Unity account), (4) run the manual-only export
   workflow `.github/workflows/export-unitylibrary.yml` once
   (game-ci unity-builder, Unity 2022.3.62f2; public repo CI is
   free, $0.00), (5) stage the `unityLibrary` artifact at
   `~/workspace/tj-racing-export/unityLibrary`. Then the wiring
   is: unconditional `include(":unityLibrary")` in
   `android/settings.gradle.kts` (the conditional include is
   already there and activates automatically), add
   `implementation(project(":unityLibrary"))` to
   `android/app/build.gradle.kts`, the `flatDir` repo for
   `unityLibrary/libs`, and `unityStreamingAssets` in
   `android/gradle.properties` (value from the Unity console log
   after export). NDK is already fine (Flutter default 28.2 ≥
   Unity r23b); minSdk is already 22. Local release build cannot
   link until then (expected).
2. **Server functions** — `claim-race-level` (new, mirrors
   `claim-game-level`) and `spend-race-item` (new, mirrors
   `spend-game-item` with currency `ad_coins`) must exist before
   racing pays or sells anything; `claim-ad-reward` already exists
   (Arrow Puzzle). Until they exist, claims fail soft in the UI
   ("could not claim — try again") and nothing is credited.
3. **Owned-items GET** — no server endpoint lists the cars /
   power-ups a player owns, so Flutter caches ownership locally
   (`RaceSettings`). A reinstall loses the local list (the Ad Coin
   balance itself is server-side and safe). A `get-race-items`
   endpoint (or owned ids inside `claim-ad-reward` GET) would fix
   this properly.
4. **CI Unity export step** — the workflow needs a Unity export
   step before the Flutter build (only the browser can edit
   workflow files). Unity 2022.3 export needs Gradle 7.5.1 /
   AGP 7.4.2 / NDK r23b / JDK 11 in ITS OWN build.gradle, while
   the Flutter app uses AGP 9.1.0 / JDK 17 — verify the combination
   builds before the v1.0.31 CI run.
5. **Unity gaps above (§KNOWN UNITY GAPS)** — items 1–2 block the
   rewarded-ad payout and power-up purchases respectively.
