/// Race reward math + Unity message parsing for TJ Racing 3D
/// (v1.0.31).
///
/// Pure Dart, no Flutter imports (unit-testable). Nothing here
/// credits coins — the server (`claim-race-level`) is the only
/// credit; this file only computes what the UI may DISPLAY from the
/// remote config and parses what Unity sends over the plugin
/// message channel.
///
/// Message shapes are VERIFIED against the Unity source
/// (`~/workspace/tj-racing/Assets/Scripts/TJRacing/`):
/// - `RaceResult` — `Core/RaceResult.cs` (Unity generates the
///   `race_id` Guid; `level_coins_earned` is INFO ONLY — Flutter
///   MUST re-derive the coins server-side and never trust it).
/// - `UnityEvent` — `Core/RaceResult.cs` (`UnityEvent` class) plus
///   the send sites in `RaceManager.cs`, `Ads/UnityAdsManager.cs`,
///   `UI/MenuUI.cs`.
/// - Interstitials are UNITY-owned (ResultsUI Continue →
///   `MaybeShowInterstitialAfterContinue`); Flutter never triggers
///   a race interstitial, so there is no Flutter ad gate here.
/// - First race must be winnable (research §A.8): Unity slows the
///   AI by `firstRaceAiSlowdownPct` on the first race; Flutter's
///   `level` (below) only gates lap-3 road traffic.
/// - Direct unlocks only: every car / power-up has a fixed Ad Coin
///   price; no random rewards anywhere.
library;

import 'dart:convert';

/// Level Coins earned for a finishing position, from the remote
/// config (`games.tj_racing.level_coins`: win 10, second 5, third 0,
/// finish 0 — user-confirmed 19 Nov 2026). Positions are 1-based;
/// anything outside 1..totalRacers pays the finish rate.
///
/// This is what Flutter DISPLAYS and what the server re-derives
/// from `position` in `claim-race-level`. Unity's
/// `level_coins_earned` field is never used for either.
int raceLevelCoinsForPosition(
  int position, {
  required int win,
  required int second,
  required int third,
  required int finish,
}) {
  return switch (position) {
    1 => win,
    2 => second,
    3 => third,
    _ => finish,
  };
}

/// Player level sent to Unity in `SetConfig` (and shown as the
/// "LEVEL n" pill in Unity's menu). Unity uses it for one thing:
/// lap-3 road traffic appears when `level >= hardLevelThreshold`
/// (default 3). Definition (Flutter-owned): level 1 for the first
/// 3 finished races, then +1 every 3 finished races.
int levelForRacesFinished(int finished) => 1 + (finished ~/ 3);

/// A race result as sent by Unity (`RaceResult.cs`):
/// `{"type":"race_result","race_id":"Guid-no-dashes","track_id":
/// "night_city_1","car_id":"street_hawk","position":1,
/// "total_racers":6,"laps_completed":3,"race_time_secs":83.4,
/// "best_lap_secs":27.1,"level_coins_earned":10,
/// "is_first_race":false}`.
/// Returns null for any other message type or malformed payload —
/// the caller ignores those (no claim is ever made from them).
class RaceResult {
  const RaceResult({
    required this.raceId,
    required this.trackId,
    required this.carId,
    required this.position,
    required this.totalRacers,
    required this.lapsCompleted,
    this.raceTimeSecs,
    this.bestLapSecs,
    this.levelCoinsEarned,
    this.isFirstRace = false,
  });

  /// Unity-generated Guid (no dashes), unique per race. The server
  /// credits once per race id — replays return `already: true`.
  final String raceId;
  final String trackId;
  final String carId;
  final int position;
  final int totalRacers;
  final int lapsCompleted;
  final double? raceTimeSecs;
  final double? bestLapSecs;

  /// INFO ONLY (Unity's own calc: win 10 / 2nd 5 / else 0).
  /// NEVER used for credit or display of the credited amount.
  final int? levelCoinsEarned;
  final bool isFirstRace;

  bool get isWin => position == 1;

  static RaceResult? tryParse(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['type'] != 'race_result') return null;
      final raceId = decoded['race_id'];
      final position = decoded['position'];
      final laps = decoded['laps_completed'];
      final total = decoded['total_racers'];
      if (raceId is! String || raceId.isEmpty) return null;
      if (position is! int || laps is! int || total is! int) return null;
      if (position < 1 || position > total || total < 1) return null;
      if (laps < 0) return null;
      final time = decoded['race_time_secs'];
      final best = decoded['best_lap_secs'];
      final earned = decoded['level_coins_earned'];
      return RaceResult(
        raceId: raceId,
        trackId: (decoded['track_id'] ?? '').toString(),
        carId: (decoded['car_id'] ?? '').toString(),
        position: position,
        lapsCompleted: laps,
        totalRacers: total,
        raceTimeSecs: time is num ? time.toDouble() : null,
        bestLapSecs: best is num ? best.toDouble() : null,
        levelCoinsEarned: earned is num ? earned.toInt() : null,
        isFirstRace: decoded['is_first_race'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A Unity event message (`UnityEvent` in `RaceResult.cs`):
/// `{"type":"TYPE","placement":"PLACEMENT",
/// "race_id":"ID","detail":"JSON-STRING"}`.
/// `detail` is itself a JSON-encoded string — parse it with the
/// typed detail parsers below, never as a nested object.
class UnityEvent {
  const UnityEvent({
    required this.type,
    this.placement = '',
    this.raceId = '',
    this.detail = '',
  });

  final String type;
  final String placement;
  final String raceId;
  final String detail;

  static UnityEvent? tryParse(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map<String, dynamic>) return null;
      final type = decoded['type'];
      if (type is! String || type.isEmpty) return null;
      if (type == 'race_result') return null;
      return UnityEvent(
        type: type,
        placement: (decoded['placement'] ?? '').toString(),
        raceId: (decoded['race_id'] ?? '').toString(),
        detail: (decoded['detail'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Parses [detail] (a JSON string) into a map, or null when it
  /// is empty / malformed. Callers read only the keys they need.
  Map<String, dynamic>? get detailJson {
    if (detail.isEmpty) return null;
    try {
      final decoded = jsonDecode(detail);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }
}

/// `race_started` detail (RaceManager.cs):
/// `{"track":"night_city_1","laps":3}`.
class RaceStartedDetail {
  const RaceStartedDetail({required this.track, required this.laps});

  final String track;
  final int laps;

  static RaceStartedDetail? tryParse(String detail) {
    try {
      final decoded = jsonDecode(detail);
      if (decoded is! Map<String, dynamic>) return null;
      final track = decoded['track'];
      final laps = decoded['laps'];
      if (track is! String || laps is! int) return null;
      return RaceStartedDetail(track: track, laps: laps);
    } catch (_) {
      return null;
    }
  }
}

/// `rewarded_completed` / `rewarded_failed` detail
/// (UnityAdsManager.cs): `{"requestId":"..."}`, failed adds
/// `{"requestId":"...","reason":"..."}`. The `requestId` is the
/// idempotency key Flutter sent in `ShowRewardedAd` — the server
/// claim is keyed by it.
class RewardedDetail {
  const RewardedDetail({required this.requestId, this.reason});

  final String requestId;
  final String? reason;

  static RewardedDetail? tryParse(String detail) {
    try {
      final decoded = jsonDecode(detail);
      if (decoded is! Map<String, dynamic>) return null;
      final requestId = decoded['requestId'];
      if (requestId is! String || requestId.isEmpty) return null;
      final reason = decoded['reason'];
      return RewardedDetail(
        requestId: requestId,
        reason: reason is String ? reason : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// `car_locked_tapped` detail (MenuUI.cs):
/// `{"carId":"night_falcon","price":200}`. Flutter shows the
/// unlock / Watch Ad prompt; Unity never sells anything itself.
class CarLockedDetail {
  const CarLockedDetail({required this.carId, required this.price});

  final String carId;
  final int price;

  static CarLockedDetail? tryParse(String detail) {
    try {
      final decoded = jsonDecode(detail);
      if (decoded is! Map<String, dynamic>) return null;
      final carId = decoded['carId'];
      final price = decoded['price'];
      if (carId is! String || carId.isEmpty) return null;
      if (price is! num) return null;
      return CarLockedDetail(carId: carId, price: price.toInt());
    } catch (_) {
      return null;
    }
  }
}

/// `powerup_purchase_requested` detail (RaceHUD.cs pause panel):
/// `{"powerupId":"nitro_boost","price":10}`. Flutter shows its
/// own purchase dialog and spends Ad Coins server-side via
/// `spend-race-item` (item `race_powerup_<id>`). Unity never
/// spends anything itself — but after a successful spend Flutter
/// sends `PowerupGranted` (`{powerupId}`) and Unity applies the
/// effect in the race (nitro: full meter; shield: 20 s traffic
/// pass-through) or holds it for the next race.
class PowerupPurchaseDetail {
  const PowerupPurchaseDetail({required this.powerupId, required this.price});

  final String powerupId;
  final int price;

  static PowerupPurchaseDetail? tryParse(String detail) {
    try {
      final decoded = jsonDecode(detail);
      if (decoded is! Map<String, dynamic>) return null;
      final powerupId = decoded['powerupId'];
      final price = decoded['price'];
      if (powerupId is! String || powerupId.isEmpty) return null;
      if (price is! num) return null;
      return PowerupPurchaseDetail(
        powerupId: powerupId,
        price: price.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Server item id for a power-up spend: `race_powerup_<id>`.
/// Pure helper so the spend call shape is unit-testable.
String racePowerupItemId(String powerupId) => 'race_powerup_$powerupId';
