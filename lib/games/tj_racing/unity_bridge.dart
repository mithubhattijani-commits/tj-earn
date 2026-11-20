import 'dart:convert';

import 'package:flutter_embed_unity/flutter_embed_unity.dart';

import 'coins_rs.dart';
import 'race_rewards.dart';
import 'race_settings.dart';
import '../../services/remote_config_service.dart';

/// Flutter ↔ Unity message protocol for TJ Racing 3D (v1.0.31).
///
/// VERIFIED against the Unity source
/// (`~/workspace/tj-racing/Assets/Scripts/TJRacing/`):
/// - `Core/FlutterBridge.cs` — GameObject `FlutterBridge`, method
///   `OnFlutterMessage(string)`, envelope `{method, payload}` where
///   `payload` is a JSON-encoded STRING (Unity's `JsonUtility`
///   cannot parse a nested raw object here).
/// - `Core/RaceResult.cs` — `RaceResult` + `UnityEvent` shapes.
/// - `Ads/UnityAdsManager.cs`, `Core/RaceManager.cs`,
///   `UI/MenuUI.cs`, `UI/ResultsUI.cs` — the send sites.
///
/// TRANSPORT NOTE: the integration doc names the old
/// `flutter_unity_widget` API (`UnityWidget.postMessage`,
/// `onUnityMessage`). The real package in this app is
/// `flutter_embed_unity` 2.0.0, whose API is the `EmbedUnity`
/// widget + top-level `sendToUnity(gameObject, method, data)`.
/// The Unity C# side is unaffected: `sendToUnity` delivers exactly
/// `SendMessage("FlutterBridge", "OnFlutterMessage", json)`, which
/// is what `FlutterBridge.OnFlutterMessage` expects. Only the Dart
/// call shape differs — the wire protocol below is identical.
///
/// Unity NEVER credits any coin. Every credit is a server call
/// from Flutter (`claim-race-level` / `claim-ad-reward` /
/// `spend-race-item`) after a Unity event arrives.
class UnityBridge {
  UnityBridge._();

  /// GameObject in the Unity scene that receives Flutter messages.
  static const String bridgeObject = 'FlutterBridge';

  /// Unity method that dispatches the `{method, payload}` envelope.
  static const String bridgeMethod = 'OnFlutterMessage';

  /// Builds the wire envelope: `{"method": ..., "payload": "<JSON
  /// string>"}`. Pure (unit-testable) — [send] is the only part
  /// that touches the platform channel.
  static String envelope(String method, Map<String, dynamic> payload) {
    return jsonEncode({
      'method': method,
      'payload': jsonEncode(payload),
    });
  }

  static void send(String method, Map<String, dynamic> payload) {
    sendToUnity(bridgeObject, bridgeMethod, envelope(method, payload));
  }

  /// `SetConfig` — the full `games.tj_racing` block (as a JSON
  /// string, per `FlutterBridge.ConfigPayload`) plus the player's
  /// live state. Unity applies it on `OnConfigApplied` (menu
  /// refreshes its car list) and `OnBalancesChanged` (coins pill
  /// "● 1,240 • Rs 12" + "LEVEL n" pill).
  ///
  /// `rsValue` is pre-formatted ("Rs 12") and `totalEarnedRs`
  /// ("Rs 37") — Unity displays exactly what Flutter sends and
  /// never computes Rs itself.
  static void sendConfig({
    required TjRacingConfig config,
    required int level,
    required int levelCoins,
    required int adCoins,
    required String rsValue,
    required String totalEarnedRs,
  }) {
    send('SetConfig', {
      'config': jsonEncode(config.toJson()),
      'level': level,
      'levelCoins': levelCoins,
      'adCoins': adCoins,
      'rsValue': rsValue,
      'totalEarnedRs': totalEarnedRs,
    });
  }

  /// `SetSelectedCar` — `{carId}`. Sent at launch (Flutter's
  /// cached selection) and after an unlock. NOTE: garage selection
  /// changes made INSIDE Unity's menu are local-only (MenuUI never
  /// tells Flutter), so Flutter's cached selection can go stale —
  /// Unity's choice wins until the next launch.
  static void sendSelectedCar(String carId) {
    send('SetSelectedCar', {'carId': carId});
  }

  /// `SetUnlockedCars` — `{carIds: [...]}`. Unlock state is
  /// decided by FLUTTER, never Unity. `street_hawk` is always
  /// included (Unity adds it back if missing).
  static void sendUnlockedCars(Iterable<String> carIds) {
    final ids = carIds.toSet()..add('street_hawk');
    send('SetUnlockedCars', {'carIds': ids.toList()});
  }

  /// `SetBalances` — `{levelCoins, adCoins, rsValue,
  /// totalEarnedRs}`. Sent after any balance change (including
  /// after a race is credited server-side) so Unity's pills update.
  static void sendBalances({
    required int levelCoins,
    required int adCoins,
    required String rsValue,
    required String totalEarnedRs,
  }) {
    send('SetBalances', {
      'levelCoins': levelCoins,
      'adCoins': adCoins,
      'rsValue': rsValue,
      'totalEarnedRs': totalEarnedRs,
    });
  }

  /// `SetSensitivity` — `{value}` 0.5–2.0 (tilt slider).
  static void sendSensitivity(double value) {
    send('SetSensitivity', {'value': value});
  }

  /// `SetControlMode` — `{value: "tilt" | "buttons" | "both"}`.
  static void sendControlMode(String mode) {
    send('SetControlMode', {'value': mode});
  }

  /// `RecalibrateTilt` — `{}`. Unity re-runs the neutral
  /// auto-calibration now (it also does this at every race start).
  static void sendRecalibrateTilt() {
    send('RecalibrateTilt', {});
  }

  /// `QuitToMenu` — `{}`. Sent when Flutter leaves the game
  /// (back button / close). Unity's bootstrap subscribes to
  /// `OnQuitToMenuRequested` (fixed 19 Nov 2026 — it loads the
  /// menu scene); Flutter still pops the screen itself.
  static void sendQuitToMenu() {
    send('QuitToMenu', {});
  }

  /// `ShowRewardedAd` — `{requestId}`. Opt-in rewarded prompt
  /// (garage / "need Ad Coins?"). Unity shows the ad and reports
  /// `rewarded_completed` / `rewarded_failed` with the same
  /// `requestId`, which Flutter uses as the idempotency key for
  /// the server claim. Unity's `UnityAdsManager` subscribes to
  /// `OnRewardedAdRequested` (fixed 19 Nov 2026); the 30 s
  /// timeout in the play screen stays as a safety net.
  static void sendShowRewardedAd(String requestId) {
    send('ShowRewardedAd', {'requestId': requestId});
  }

  /// `PowerupGranted` — `{powerupId}`. Sent after Flutter spends
  /// Ad Coins server-side for a power-up (`spend-race-item`,
  /// item `race_powerup_<id>`) — on a fresh spend AND on an
  /// idempotent replay (the item WAS granted, so Unity still
  /// applies the effect). NEVER sent on a failed spend (402 /
  /// any error): nothing was granted, so Unity must apply
  /// nothing. Unity applies the effect in the race (nitro: full
  /// meter; shield: 20 s traffic pass-through) or holds it as a
  /// pending grant for the next race if no race is active.
  static void sendPowerupGranted(String powerupId) {
    send('PowerupGranted', {'powerupId': powerupId});
  }
}

/// What a string from Unity means, after parsing.
enum UnityIncomingKind {
  raceResult,
  raceStarted,
  raceCancelled,
  rewardedCompleted,
  rewardedFailed,
  interstitialShown,
  carLockedTapped,
  powerupPurchaseRequested,
  menuReady,
  loadingProgress,
  unknown,
}

/// One parsed Unity→Flutter message. Exactly one of [raceResult]
/// / [event] is non-null for known types; [carLocked] /
/// [rewarded] / [powerupPurchase] carry the parsed `detail`
/// payloads; [loadingPct] carries the `loading_progress` % (0-100).
class UnityIncoming {
  const UnityIncoming({
    required this.kind,
    this.raceResult,
    this.event,
    this.carLocked,
    this.rewarded,
    this.raceStarted,
    this.powerupPurchase,
    this.loadingPct,
  });

  final UnityIncomingKind kind;
  final RaceResult? raceResult;
  final UnityEvent? event;
  final CarLockedDetail? carLocked;
  final RewardedDetail? rewarded;
  final RaceStartedDetail? raceStarted;
  final PowerupPurchaseDetail? powerupPurchase;
  final int? loadingPct;

  /// Parses any string from `EmbedUnity.onMessageFromUnity`.
  /// Never throws; unknown / malformed input parses as
  /// [UnityIncomingKind.unknown] (the caller ignores it).
  static UnityIncoming parse(String message) {
    final result = RaceResult.tryParse(message);
    if (result != null) {
      return UnityIncoming(kind: UnityIncomingKind.raceResult, raceResult: result);
    }
    final event = UnityEvent.tryParse(message);
    if (event == null) {
      return const UnityIncoming(kind: UnityIncomingKind.unknown);
    }
    switch (event.type) {
      case 'race_started':
        return UnityIncoming(
          kind: UnityIncomingKind.raceStarted,
          event: event,
          raceStarted: RaceStartedDetail.tryParse(event.detail),
        );
      case 'race_cancelled':
        return UnityIncoming(kind: UnityIncomingKind.raceCancelled, event: event);
      case 'rewarded_completed':
        return UnityIncoming(
          kind: UnityIncomingKind.rewardedCompleted,
          event: event,
          rewarded: RewardedDetail.tryParse(event.detail),
        );
      case 'rewarded_failed':
        return UnityIncoming(
          kind: UnityIncomingKind.rewardedFailed,
          event: event,
          rewarded: RewardedDetail.tryParse(event.detail),
        );
      case 'interstitial_shown':
        return UnityIncoming(
          kind: UnityIncomingKind.interstitialShown,
          event: event,
        );
      case 'car_locked_tapped':
        return UnityIncoming(
          kind: UnityIncomingKind.carLockedTapped,
          event: event,
          carLocked: CarLockedDetail.tryParse(event.detail),
        );
      case 'powerup_purchase_requested':
        return UnityIncoming(
          kind: UnityIncomingKind.powerupPurchaseRequested,
          event: event,
          powerupPurchase: PowerupPurchaseDetail.tryParse(event.detail),
        );
      case 'menu_ready':
        return UnityIncoming(
          kind: UnityIncomingKind.menuReady,
          event: event,
        );
      case 'loading_progress':
        final pct = event.detailJson?['pct'];
        return UnityIncoming(
          kind: UnityIncomingKind.loadingProgress,
          event: event,
          loadingPct: pct is num ? pct.toInt().clamp(0, 100) : null,
        );
      default:
        return UnityIncoming(kind: UnityIncomingKind.unknown, event: event);
    }
  }
}

/// Current player state assembled for `SetConfig` / `SetBalances`.
/// Pure value object so the play screen can build both messages
/// from one load.
class RacingPlayerState {
  const RacingPlayerState({
    required this.level,
    required this.levelCoins,
    required this.adCoins,
    required this.rsValue,
    required this.totalEarnedRs,
    required this.selectedCarId,
    required this.unlockedCarIds,
    required this.sensitivity,
    required this.controlMode,
  });

  final int level;
  final int levelCoins;
  final int adCoins;
  final String rsValue;
  final String totalEarnedRs;
  final String selectedCarId;
  final Set<String> unlockedCarIds;
  final double sensitivity;
  final String controlMode;

  /// Loads everything from the server (balances) + local settings.
  /// Fail-soft: a failed balance load yields 0/empty strings rather
  /// than blocking the game from opening (Unity falls back to its
  /// own defaults until a later re-send).
  static Future<RacingPlayerState> load({
    required TjRacingConfig config,
    required Future<int> Function() getLevelCoins,
    required Future<Map<String, dynamic>> Function() getAdCoins,
    required Future<int> Function() getTotalEarned,
  }) async {
    final results = await Future.wait([
      RaceSettings.racesFinished,
      getLevelCoins().then<int>((v) => v).catchError((_) => 0),
      getAdCoins().then<Map<String, dynamic>>((v) => v).catchError(
            (_) => const <String, dynamic>{},
          ),
      getTotalEarned().then<int>((v) => v).catchError((_) => 0),
      RaceSettings.selectedCarId,
      RaceSettings.ownedCarIds,
      RaceSettings.tiltSensitivity,
      RaceSettings.controlMode,
    ]);
    final finished = results[0] as int;
    final levelCoins = results[1] as int;
    final adCoinsMap = results[2] as Map<String, dynamic>;
    final totalEarned = results[3] as int;
    final perPkr = config.levelCoins.coinsPerPkr;
    return RacingPlayerState(
      level: levelForRacesFinished(finished),
      levelCoins: levelCoins,
      adCoins: (adCoinsMap['ad_coins_balance'] as num?)?.toInt() ?? 0,
      rsValue: formatRsShort(levelCoins, coinsPerPkr: perPkr),
      totalEarnedRs: formatRsShort(totalEarned, coinsPerPkr: perPkr),
      selectedCarId: results[4] as String,
      unlockedCarIds: results[5] as Set<String>,
      sensitivity: results[6] as double,
      controlMode: results[7] as String,
    );
  }
}
