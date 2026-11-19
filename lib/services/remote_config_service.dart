// Remote Config — server-driven in-app content (v1).
//
// Fail-soft: network -> cache -> bundled defaults. Never blocks startup,
// never an infinite spinner, never a crash — on any failure the app just
// uses what it has (APP ROBUSTNESS RULE, Jaani 2 Nov 2026).
//
// Config URL (live): https://nigraantv.xyz/apps/config/tj-earn.json
// Operator workflow: see ~/workspace/app-remote-config/REMOTE-CONFIG.md
//
// Polling (Task D, 12 Nov 2026): the old 6h TTL is gone — the config is
// re-fetched fresh on launch, on resume, and every ~60s (see
// [RemoteConfigService.refresh] / [RemoteConfigService.startPolling]).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Slim notice bar under the header. Shows only when enabled AND
/// the text is non-empty.
class AnnouncementConfig {
  const AnnouncementConfig({this.enabled = false, this.text = ''});

  final bool enabled;
  final String text;

  bool get show => enabled && text.trim().isNotEmpty;

  factory AnnouncementConfig.fromJson(Map<String, dynamic> j) {
    return AnnouncementConfig(
      enabled: j['enabled'] == true,
      text: (j['text'] ?? '').toString(),
    );
  }
}

/// Paid-ad slot card (image + title). Tap opens [actionUrl] in the
/// external browser. Never auto-opens, never blocks the app.
class SponsoredAdConfig {
  const SponsoredAdConfig({
    this.enabled = false,
    this.imageUrl = '',
    this.title = '',
    this.actionUrl = '',
  });

  final bool enabled;
  final String imageUrl;
  final String title;
  final String actionUrl;

  bool get show => enabled && imageUrl.trim().isNotEmpty;

  factory SponsoredAdConfig.fromJson(Map<String, dynamic> j) {
    return SponsoredAdConfig(
      enabled: j['enabled'] == true,
      imageUrl: (j['image_url'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      actionUrl: (j['action_url'] ?? '').toString(),
    );
  }
}

/// Kill-switch (plan app/src/main/AndroidManifest.xml `isUpdateRequired`
/// BUT for sideloaded FOSS apps the dialog has to sit in-app). When
/// [enabled] is true and the app's versionCode is below [minVersionCode],
/// the app shows the update dialog wired to the existing in-app updater.
class ForceUpdateConfig {
  const ForceUpdateConfig({this.enabled = false, this.minVersionCode = 0});
  final bool enabled;
  final int minVersionCode;

  factory ForceUpdateConfig.fromJson(Map<String, dynamic> j) {
    return ForceUpdateConfig(
      enabled: j['enabled'] == true,
      minVersionCode: (j['min_version_code'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Earn rates (compliant model, v1.0.25) — server-driven coin + ad
/// frequency tuning, so rates can change without a rebuild.
///
/// JSON shape in tj-earn.json (all optional — every key falls back to
/// the bundled default when missing or malformed):
///   "earn_rates": {
///     "read_reward_coins": 5,              // coins per unique article
///     "read_daily_cap": 200,               // unique articles/day
///     "interstitial_every_nth_article": 5, // show after every Nth open
///     "interstitial_min_gap_minutes": 3,   // min gap between shows
///     "checkin_coins": 10                  // daily check-in coins
///   }
///
/// Server truth: the Edge Functions enforce the same values from
/// app_config (`read_article_coins`, `read_article_daily_cap`,
/// `read_min_dwell_seconds`, `daily_checkin_coins`). These remote-config
/// values only drive the APP's display + ad frequency — the server
/// never trusts them.
class EarnRatesConfig {
  const EarnRatesConfig({
    this.readRewardCoins = 5,
    this.readDailyCap = 200,
    this.interstitialEveryNthArticle = 5,
    this.interstitialMinGapMinutes = 3,
    this.checkinCoins = 10,
  });

  final int readRewardCoins;
  final int readDailyCap;
  final int interstitialEveryNthArticle;
  final int interstitialMinGapMinutes;
  final int checkinCoins;

  static int _asInt(Object? v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  factory EarnRatesConfig.fromJson(Map<String, dynamic> j) {
    int clamp(int v, int min, int max) =>
        v < min ? min : (v > max ? max : v);
    return EarnRatesConfig(
      readRewardCoins:
          clamp(_asInt(j['read_reward_coins'], 5), 0, 100),
      readDailyCap: clamp(_asInt(j['read_daily_cap'], 200), 1, 1000),
      interstitialEveryNthArticle:
          clamp(_asInt(j['interstitial_every_nth_article'], 5), 1, 100),
      interstitialMinGapMinutes:
          clamp(_asInt(j['interstitial_min_gap_minutes'], 3), 0, 60),
      checkinCoins: clamp(_asInt(j['checkin_coins'], 10), 0, 100),
    );
  }
}


/// TJ Racing 3D game switch + economy (v1.0.31).
///
/// JSON shape in tj-earn.json (optional — every key falls back to the
/// bundled default when missing or malformed):
///   "games": {
///     "tj_racing": {
///       "enabled": true,                     // show the game tile
///       "title": "TJ Racing 3D",
///       "level_coins": {                     // CASH coins (race win)
///         "win": 10, "second": 5, "third": 0, "finish": 0,
///         "daily_cap": 200,
///         "coins_per_pkr": 100,              // 100 coins = Rs 1
///         "min_withdrawal_coins": 10000,     // = Rs 100
///         "show_rs_value": true              // always show the Rs value
///       },
///       "ad_coins": {                        // IN-GAME ONLY coins
///         "per_rewarded_ad": 10, "daily_cap": 100,
///         "cash_convertible": false          // NEVER true
///       },
///       "ads": {
///         "banner_enabled": true,
///         "interstitial_enabled": true,
///         "interstitial_every_n_races": 3,
///         "interstitial_min_interval_secs": 180,
///         "rewarded_enabled": true
///       },
///       "race": {
///         "laps": 3, "ai_opponents": 5, "nitro_enabled": true,
///         "tracks": [{ "id": "night_city_1", "name": "Night City",
///                      "locked": false }]
///       },
///       "cars": [
///         { "id": "street_hawk",    "name": "Street Hawk",
///           "class": "standard", "ad_coins_price": 0 },
///         { "id": "night_falcon",   "name": "Night Falcon",
///           "class": "sports",   "ad_coins_price": 200 },
///         { "id": "midnight_ghost", "name": "Midnight Ghost",
///           "class": "sports",   "ad_coins_price": 500 },
///         { "id": "storm_rider",    "name": "Storm Rider",
///           "class": "luxury",   "ad_coins_price": 800 },
///         { "id": "thunder_king",   "name": "Thunder King",
///           "class": "luxury",   "ad_coins_price": 1200 }
///       ],
///       "powerups": [
///         { "id": "nitro_boost", "name": "Nitro Boost",
///           "ad_coins_price": 10 },
///         { "id": "shield",      "name": "Shield",
///           "ad_coins_price": 15 }
///       ],
///       // Extra Unity runtime fields (NOT in plan §9 — added by the
///       // Unity agent as runtime config; defaults match Unity's
///       // shipped `tj-racing-default.json`):
///       "tiltDeadZoneDeg": 10, "tiltSensitivity": 1.0,
///       "hardLevelThreshold": 3, "adsMinGapSecs": 90,
///       "firstRaceAiSlowdownPct": 25
///     }
///   }
///
/// Server truth: the `claim-race-level` / `spend-race-item` /
/// `claim-ad-reward` Edge Functions enforce the same values from
/// app_config. These remote-config values only drive the APP's
/// display + ad frequency — the server never trusts them.
///
/// TWO CURRENCIES: Ad Coins (earned by watching ads, in-game only)
/// and Level Coins (earned by placing in a race, cash-redeemable)
/// never mix — Ad Coins can never become cash or Level Coins
/// (see `games/tj_racing/ad_coins.dart`). Level Coins are NEVER
/// spent in-game. Real-money car purchase is FUTURE (after the Play
/// Store upload) — no IAP in v1.
class TjRacingLevelCoinsConfig {
  const TjRacingLevelCoinsConfig({
    this.win = 10,
    this.second = 5,
    this.third = 0,
    this.finish = 0,
    this.dailyCap = 200,
    this.coinsPerPkr = 100,
    this.minWithdrawalCoins = 10000,
    this.showRsValue = true,
  });

  final int win;
  final int second;
  final int third;
  final int finish;
  final int dailyCap;
  final int coinsPerPkr;
  final int minWithdrawalCoins;
  final bool showRsValue;

  Map<String, dynamic> toJson() => {
        'win': win,
        'second': second,
        'third': third,
        'finish': finish,
        'daily_cap': dailyCap,
        'coins_per_pkr': coinsPerPkr,
        'min_withdrawal_coins': minWithdrawalCoins,
        'show_rs_value': showRsValue,
      };

  factory TjRacingLevelCoinsConfig.fromJson(Map<String, dynamic> j) {
    int clamp(int v, int min, int max) =>
        v < min ? min : (v > max ? max : v);
    return TjRacingLevelCoinsConfig(
      win: clamp(_asInt(j['win'], 10), 0, 100),
      second: clamp(_asInt(j['second'], 5), 0, 100),
      third: clamp(_asInt(j['third'], 0), 0, 100),
      finish: clamp(_asInt(j['finish'], 0), 0, 100),
      dailyCap: clamp(_asInt(j['daily_cap'], 200), 1, 1000),
      coinsPerPkr: clamp(_asInt(j['coins_per_pkr'], 100), 1, 10000),
      minWithdrawalCoins:
          clamp(_asInt(j['min_withdrawal_coins'], 10000), 1, 1000000),
      showRsValue: j['show_rs_value'] != false,
    );
  }

  static int _asInt(Object? v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }
}

class TjRacingAdCoinsConfig {
  const TjRacingAdCoinsConfig({
    this.perRewardedAd = 10,
    this.dailyCap = 100,
    this.cashConvertible = false,
  });

  final int perRewardedAd;
  final int dailyCap;

  /// Must stay false — Ad Coins can never become cash. Parsed but
  /// never honoured as true anywhere in the app.
  final bool cashConvertible;

  Map<String, dynamic> toJson() => {
        'per_rewarded_ad': perRewardedAd,
        'daily_cap': dailyCap,
        'cash_convertible': cashConvertible,
      };

  factory TjRacingAdCoinsConfig.fromJson(Map<String, dynamic> j) {
    int clamp(int v, int min, int max) =>
        v < min ? min : (v > max ? max : v);
    return TjRacingAdCoinsConfig(
      perRewardedAd: clamp(_asInt(j['per_rewarded_ad'], 10), 0, 100),
      dailyCap: clamp(_asInt(j['daily_cap'], 100), 1, 1000),
      cashConvertible: j['cash_convertible'] == true,
    );
  }

  static int _asInt(Object? v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }
}

class TjRacingAdsConfig {
  const TjRacingAdsConfig({
    this.bannerEnabled = true,
    this.interstitialEnabled = true,
    this.interstitialEveryNRaces = 3,
    this.interstitialMinIntervalSecs = 180,
    this.rewardedEnabled = true,
  });

  final bool bannerEnabled;
  final bool interstitialEnabled;
  final int interstitialEveryNRaces;
  final int interstitialMinIntervalSecs;
  final bool rewardedEnabled;

  Map<String, dynamic> toJson() => {
        'banner_enabled': bannerEnabled,
        'interstitial_enabled': interstitialEnabled,
        'interstitial_every_n_races': interstitialEveryNRaces,
        'interstitial_min_interval_secs': interstitialMinIntervalSecs,
        'rewarded_enabled': rewardedEnabled,
      };

  factory TjRacingAdsConfig.fromJson(Map<String, dynamic> j) {
    int clamp(int v, int min, int max) =>
        v < min ? min : (v > max ? max : v);
    return TjRacingAdsConfig(
      bannerEnabled: j['banner_enabled'] != false,
      interstitialEnabled: j['interstitial_enabled'] != false,
      interstitialEveryNRaces:
          clamp(_asInt(j['interstitial_every_n_races'], 3), 1, 100),
      interstitialMinIntervalSecs:
          clamp(_asInt(j['interstitial_min_interval_secs'], 180), 0, 3600),
      rewardedEnabled: j['rewarded_enabled'] != false,
    );
  }

  static int _asInt(Object? v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }
}

class TjRacingTrackConfig {
  const TjRacingTrackConfig({
    required this.id,
    required this.name,
    this.locked = false,
  });

  final String id;
  final String name;
  final bool locked;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'locked': locked,
      };

  factory TjRacingTrackConfig.fromJson(Map<String, dynamic> j) {
    return TjRacingTrackConfig(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      locked: j['locked'] == true,
    );
  }
}

class TjRacingRaceConfig {
  const TjRacingRaceConfig({
    this.laps = 3,
    this.aiOpponents = 5,
    this.nitroEnabled = true,
    this.tracks = const [
      TjRacingTrackConfig(id: 'night_city_1', name: 'Night City'),
    ],
  });

  final int laps;
  final int aiOpponents;
  final bool nitroEnabled;
  final List<TjRacingTrackConfig> tracks;

  Map<String, dynamic> toJson() => {
        'laps': laps,
        'ai_opponents': aiOpponents,
        'nitro_enabled': nitroEnabled,
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };

  /// First unlocked track (launch content is a single track).
  TjRacingTrackConfig get firstTrack =>
      tracks.firstWhere((t) => !t.locked, orElse: () => tracks.first);

  factory TjRacingRaceConfig.fromJson(Map<String, dynamic> j) {
    int clamp(int v, int min, int max) =>
        v < min ? min : (v > max ? max : v);
    final rawTracks = j['tracks'];
    final tracks = <TjRacingTrackConfig>[];
    if (rawTracks is List) {
      for (final entry in rawTracks) {
        if (entry is Map<String, dynamic>) {
          final track = TjRacingTrackConfig.fromJson(entry);
          if (track.id.isNotEmpty) tracks.add(track);
        }
      }
    }
    return TjRacingRaceConfig(
      laps: clamp(_asInt(j['laps'], 3), 1, 10),
      aiOpponents: clamp(_asInt(j['ai_opponents'], 5), 0, 11),
      nitroEnabled: j['nitro_enabled'] != false,
      tracks: tracks.isNotEmpty
          ? tracks
          : const [
              TjRacingTrackConfig(id: 'night_city_1', name: 'Night City'),
            ],
    );
  }

  static int _asInt(Object? v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }
}

class TjRacingCarConfig {
  const TjRacingCarConfig({
    required this.id,
    required this.name,
    required this.carClass,
    required this.adCoinsPrice,
    this.topSpeedKmh = 180,
    this.acceleration = 12,
    this.handling = 1.0,
    this.nitroCapacity = 100,
    this.bodyColorHex = '#E5484D',
  });

  final String id;
  final String name;

  /// 'standard' | 'sports' | 'luxury'.
  final String carClass;

  /// Ad Coins to unlock (0 = free). NEVER Level Coins, NEVER cash.
  final int adCoinsPrice;

  /// Physics tuning, sent to Unity in `SetConfig`. CRITICAL: Unity's
  /// `JsonUtility` keeps the C# field initializers (180/12/1.0/100)
  /// for any key Flutter omits — so if Flutter sent cars WITHOUT
  /// stats, EVERY car would drive at 180 km/h and the progression
  /// would be dead. Flutter therefore ALWAYS sends the stats below
  /// (defaults = Unity's shipped `CarCatalogue` table).
  final double topSpeedKmh;
  final double acceleration;
  final double handling;
  final double nitroCapacity;
  final String bodyColorHex;

  bool get isLuxury => carClass == 'luxury';
  bool get isFree => adCoinsPrice <= 0;

  /// Shipped per-car stats (Unity `CarCatalogue.DefaultCars`).
  static const Map<String, TjRacingCarConfig> defaultStats = {
    'street_hawk': TjRacingCarConfig(
      id: 'street_hawk',
      name: 'Street Hawk',
      carClass: 'standard',
      adCoinsPrice: 0,
      topSpeedKmh: 178,
      acceleration: 11,
      handling: 1.0,
      nitroCapacity: 100,
      bodyColorHex: '#E5484D',
    ),
    'night_falcon': TjRacingCarConfig(
      id: 'night_falcon',
      name: 'Night Falcon',
      carClass: 'sports',
      adCoinsPrice: 200,
      topSpeedKmh: 192,
      acceleration: 12.5,
      handling: 1.05,
      nitroCapacity: 100,
      bodyColorHex: '#2E6BFF',
    ),
    'midnight_ghost': TjRacingCarConfig(
      id: 'midnight_ghost',
      name: 'Midnight Ghost',
      carClass: 'sports',
      adCoinsPrice: 500,
      topSpeedKmh: 205,
      acceleration: 14,
      handling: 1.1,
      nitroCapacity: 110,
      bodyColorHex: '#7A4DFF',
    ),
    'storm_rider': TjRacingCarConfig(
      id: 'storm_rider',
      name: 'Storm Rider',
      carClass: 'luxury',
      adCoinsPrice: 800,
      topSpeedKmh: 218,
      acceleration: 15.5,
      handling: 1.15,
      nitroCapacity: 120,
      bodyColorHex: '#FFB020',
    ),
    'thunder_king': TjRacingCarConfig(
      id: 'thunder_king',
      name: 'Thunder King',
      carClass: 'luxury',
      adCoinsPrice: 1200,
      topSpeedKmh: 232,
      acceleration: 17,
      handling: 1.2,
      nitroCapacity: 130,
      bodyColorHex: '#12C2A0',
    ),
  };

  factory TjRacingCarConfig.fromJson(Map<String, dynamic> j) {
    final id = (j['id'] ?? '').toString();
    final fallback = defaultStats[id];
    return TjRacingCarConfig(
      id: id,
      name: (j['name'] ?? '').toString(),
      carClass: (j['class'] ?? 'standard').toString(),
      adCoinsPrice: _asInt(j['ad_coins_price'], 0),
      topSpeedKmh: _asDouble(
        j['topSpeedKmh'],
        fallback?.topSpeedKmh ?? 180,
      ),
      acceleration: _asDouble(
        j['acceleration'],
        fallback?.acceleration ?? 12,
      ),
      handling: _asDouble(j['handling'], fallback?.handling ?? 1.0),
      nitroCapacity: _asDouble(
        j['nitroCapacity'],
        fallback?.nitroCapacity ?? 100,
      ),
      bodyColorHex: (j['bodyColorHex'] as String?)?.isNotEmpty == true
          ? j['bodyColorHex'] as String
          : (fallback?.bodyColorHex ?? '#E5484D'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'class': carClass,
        'ad_coins_price': adCoinsPrice,
        'topSpeedKmh': topSpeedKmh,
        'acceleration': acceleration,
        'handling': handling,
        'nitroCapacity': nitroCapacity,
        'bodyColorHex': bodyColorHex,
      };

  static int _asInt(Object? v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  static double _asDouble(Object? v, double fallback) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? fallback;
    return fallback;
  }
}

class TjRacingPowerupConfig {
  const TjRacingPowerupConfig({
    required this.id,
    required this.name,
    required this.adCoinsPrice,
  });

  final String id;
  final String name;

  /// Ad Coins to buy. NEVER Level Coins, NEVER cash.
  final int adCoinsPrice;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ad_coins_price': adCoinsPrice,
      };

  factory TjRacingPowerupConfig.fromJson(Map<String, dynamic> j) {
    return TjRacingPowerupConfig(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      adCoinsPrice: _asInt(j['ad_coins_price'], 0),
    );
  }

  static int _asInt(Object? v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }
}

class TjRacingConfig {
  const TjRacingConfig({
    this.enabled = false,
    this.title = 'TJ Racing 3D',
    this.levelCoins = const TjRacingLevelCoinsConfig(),
    this.adCoins = const TjRacingAdCoinsConfig(),
    this.ads = const TjRacingAdsConfig(),
    this.race = const TjRacingRaceConfig(),
    this.cars = defaultCars,
    this.powerups = defaultPowerups,
    this.tiltDeadZoneDeg = 10,
    this.tiltSensitivity = 1.0,
    this.hardLevelThreshold = 3,
    this.adsMinGapSecs = 90,
    this.firstRaceAiSlowdownPct = 25,
  });

  final bool enabled;
  final String title;
  final TjRacingLevelCoinsConfig levelCoins;
  final TjRacingAdCoinsConfig adCoins;
  final TjRacingAdsConfig ads;
  final TjRacingRaceConfig race;
  final List<TjRacingCarConfig> cars;
  final List<TjRacingPowerupConfig> powerups;

  /// Unity runtime fields (Unity `RacingConfig`): ±10° tilt dead
  /// zone, tilt sensitivity 0.5–2.0, level at which lap-3 road
  /// traffic appears, minimum gap between any two ads, AI slowdown
  /// on the first race (must be winnable). Defaults match Unity's
  /// shipped `tj-racing-default.json`.
  final double tiltDeadZoneDeg;
  final double tiltSensitivity;
  final int hardLevelThreshold;
  final int adsMinGapSecs;
  final int firstRaceAiSlowdownPct;

  static const List<TjRacingCarConfig> defaultCars = [
    TjRacingCarConfig(
      id: 'street_hawk',
      name: 'Street Hawk',
      carClass: 'standard',
      adCoinsPrice: 0,
      topSpeedKmh: 178,
      acceleration: 11,
      handling: 1.0,
      nitroCapacity: 100,
      bodyColorHex: '#E5484D',
    ),
    TjRacingCarConfig(
      id: 'night_falcon',
      name: 'Night Falcon',
      carClass: 'sports',
      adCoinsPrice: 200,
      topSpeedKmh: 192,
      acceleration: 12.5,
      handling: 1.05,
      nitroCapacity: 100,
      bodyColorHex: '#2E6BFF',
    ),
    TjRacingCarConfig(
      id: 'midnight_ghost',
      name: 'Midnight Ghost',
      carClass: 'sports',
      adCoinsPrice: 500,
      topSpeedKmh: 205,
      acceleration: 14,
      handling: 1.1,
      nitroCapacity: 110,
      bodyColorHex: '#7A4DFF',
    ),
    TjRacingCarConfig(
      id: 'storm_rider',
      name: 'Storm Rider',
      carClass: 'luxury',
      adCoinsPrice: 800,
      topSpeedKmh: 218,
      acceleration: 15.5,
      handling: 1.15,
      nitroCapacity: 120,
      bodyColorHex: '#FFB020',
    ),
    TjRacingCarConfig(
      id: 'thunder_king',
      name: 'Thunder King',
      carClass: 'luxury',
      adCoinsPrice: 1200,
      topSpeedKmh: 232,
      acceleration: 17,
      handling: 1.2,
      nitroCapacity: 130,
      bodyColorHex: '#12C2A0',
    ),
  ];

  static const List<TjRacingPowerupConfig> defaultPowerups = [
    TjRacingPowerupConfig(
      id: 'nitro_boost',
      name: 'Nitro Boost',
      adCoinsPrice: 10,
    ),
    TjRacingPowerupConfig(
      id: 'shield',
      name: 'Shield',
      adCoinsPrice: 15,
    ),
  ];

  TjRacingCarConfig? carById(String id) {
    for (final car in cars) {
      if (car.id == id) return car;
    }
    return null;
  }

  TjRacingPowerupConfig? powerupById(String id) {
    for (final powerup in powerups) {
      if (powerup.id == id) return powerup;
    }
    return null;
  }

  factory TjRacingConfig.fromJson(Map<String, dynamic> j) {
    List<TjRacingCarConfig> parseCars(Object? raw) {
      final cars = <TjRacingCarConfig>[];
      if (raw is List) {
        for (final entry in raw) {
          if (entry is Map<String, dynamic>) {
            final car = TjRacingCarConfig.fromJson(entry);
            if (car.id.isNotEmpty && car.name.isNotEmpty) cars.add(car);
          }
        }
      }
      return cars.isNotEmpty ? cars : defaultCars;
    }

    List<TjRacingPowerupConfig> parsePowerups(Object? raw) {
      final powerups = <TjRacingPowerupConfig>[];
      if (raw is List) {
        for (final entry in raw) {
          if (entry is Map<String, dynamic>) {
            final powerup = TjRacingPowerupConfig.fromJson(entry);
            if (powerup.id.isNotEmpty && powerup.name.isNotEmpty) {
              powerups.add(powerup);
            }
          }
        }
      }
      return powerups.isNotEmpty ? powerups : defaultPowerups;
    }

    return TjRacingConfig(
      enabled: j['enabled'] == true,
      title: (j['title'] as String?)?.trim().isNotEmpty == true
          ? (j['title'] as String).trim()
          : 'TJ Racing 3D',
      levelCoins: j['level_coins'] is Map<String, dynamic>
          ? TjRacingLevelCoinsConfig.fromJson(
              j['level_coins'] as Map<String, dynamic>,
            )
          : const TjRacingLevelCoinsConfig(),
      adCoins: j['ad_coins'] is Map<String, dynamic>
          ? TjRacingAdCoinsConfig.fromJson(
              j['ad_coins'] as Map<String, dynamic>,
            )
          : const TjRacingAdCoinsConfig(),
      ads: j['ads'] is Map<String, dynamic>
          ? TjRacingAdsConfig.fromJson(j['ads'] as Map<String, dynamic>)
          : const TjRacingAdsConfig(),
      race: j['race'] is Map<String, dynamic>
          ? TjRacingRaceConfig.fromJson(
              j['race'] as Map<String, dynamic>,
            )
          : const TjRacingRaceConfig(),
      cars: parseCars(j['cars']),
      powerups: parsePowerups(j['powerups']),
      tiltDeadZoneDeg: _asDouble(j['tiltDeadZoneDeg'], 10),
      tiltSensitivity: _asDouble(j['tiltSensitivity'], 1.0),
      hardLevelThreshold: _asInt(j['hardLevelThreshold'], 3),
      adsMinGapSecs: _asInt(j['adsMinGapSecs'], 90),
      firstRaceAiSlowdownPct: _asInt(j['firstRaceAiSlowdownPct'], 25),
    );
  }

  static int _asInt(Object? v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  static double _asDouble(Object? v, double fallback) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  /// Serialises the block in Unity's EXACT shape (same keys as
  /// `tj-racing-default.json` / `RacingConfig`) for `SetConfig` —
  /// Unity parses it with `JsonUtility.FromJson<RacingConfig>`,
  /// which is case-sensitive and keeps C# defaults for missing
  /// keys (so car stats MUST be present — see [TjRacingCarConfig]).
  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'title': title,
        'level_coins': levelCoins.toJson(),
        'ad_coins': adCoins.toJson(),
        'ads': ads.toJson(),
        'race': race.toJson(),
        'cars': cars.map((c) => c.toJson()).toList(),
        'powerups': powerups.map((p) => p.toJson()).toList(),
        'tiltDeadZoneDeg': tiltDeadZoneDeg,
        'tiltSensitivity': tiltSensitivity,
        'hardLevelThreshold': hardLevelThreshold,
        'adsMinGapSecs': adsMinGapSecs,
        'firstRaceAiSlowdownPct': firstRaceAiSlowdownPct,
      };
}

/// Play & Earn wall switch (RapidoReach, v1.0.25).
///
/// JSON shape in tj-earn.json (optional — defaults to disabled):
///   "rapidoreach": { "enabled": true }
///
/// Enable ONLY after the `rapidoreach-wall-url` Edge Function is
/// deployed and RAPIDOREACH_APP_ID / RAPIDOREACH_APP_KEY are set as
/// function secrets. Until then the Games tile stays hidden (fail-soft)
/// — the wall cannot sign a UID without the server side in place.
class RapidoreachConfig {
  const RapidoreachConfig({this.enabled = false});

  final bool enabled;

  factory RapidoreachConfig.fromJson(Map<String, dynamic> j) {
    return RapidoreachConfig(enabled: j['enabled'] == true);
  }
}

class RemoteConfig {
  const RemoteConfig({
    this.displayName = 'TJ Earn',
    this.logoUrl = '',
    this.announcement = const AnnouncementConfig(),
    this.sponsoredAd = const SponsoredAdConfig(),
    this.forceUpdate = const ForceUpdateConfig(),
    this.earnRates = const EarnRatesConfig(),
    this.rapidoreach = const RapidoreachConfig(),
    this.tjRacing = const TjRacingConfig(),
  });

  final String displayName;
  final String logoUrl;
  final AnnouncementConfig announcement;
  final SponsoredAdConfig sponsoredAd;
  final ForceUpdateConfig forceUpdate;
  final EarnRatesConfig earnRates;
  final RapidoreachConfig rapidoreach;
  final TjRacingConfig tjRacing;

  factory RemoteConfig.fromJson(Map<String, dynamic> j) {
    final games = j['games'];
    final tjRacingJson = games is Map<String, dynamic> &&
            games['tj_racing'] is Map<String, dynamic>
        ? games['tj_racing'] as Map<String, dynamic>
        : null;
    return RemoteConfig(
      displayName: (j['display_name'] as String?)?.trim().isNotEmpty == true
          ? (j['display_name'] as String).trim()
          : 'TJ Earn',
      logoUrl: (j['logo_url'] ?? '').toString(),
      announcement: j['announcement'] is Map<String, dynamic>
          ? AnnouncementConfig.fromJson(
              j['announcement'] as Map<String, dynamic>,
            )
          : const AnnouncementConfig(),
      sponsoredAd: j['sponsored_ad'] is Map<String, dynamic>
          ? SponsoredAdConfig.fromJson(
              j['sponsored_ad'] as Map<String, dynamic>,
            )
          : const SponsoredAdConfig(),
      forceUpdate: j['force_update'] is Map<String, dynamic>
          ? ForceUpdateConfig.fromJson(
              j['force_update'] as Map<String, dynamic>,
            )
          : const ForceUpdateConfig(),
      earnRates: j['earn_rates'] is Map<String, dynamic>
          ? EarnRatesConfig.fromJson(
              j['earn_rates'] as Map<String, dynamic>,
            )
          : const EarnRatesConfig(),
      rapidoreach: j['rapidoreach'] is Map<String, dynamic>
          ? RapidoreachConfig.fromJson(
              j['rapidoreach'] as Map<String, dynamic>,
            )
          : const RapidoreachConfig(),
      tjRacing: tjRacingJson != null
          ? TjRacingConfig.fromJson(tjRacingJson)
          : const TjRacingConfig(),
    );
  }
}

/// Singleton service. UI listens to [notifier] so a fresh fetch updates
/// the screen without a restart.
class RemoteConfigService {
  RemoteConfigService._();

  static final RemoteConfigService instance = RemoteConfigService._();

  static const _cacheKey = 'remote_config_json_v1';
  static const _url = 'https://nigraantv.xyz/apps/config/tj-earn.json';
  static const Duration _fetchTimeout = Duration(seconds: 8);

  /// Poll interval (Task D, 12 Nov 2026): the old 6-hour TTL is gone.
  /// Remote config is small and admin-driven, so it is fetched fresh on
  /// launch, on resume, and every ~60s by [startPolling]. No connectivity
  /// plugin is used (none is in pubspec): a failed fetch keeps the last
  /// good cache, and the next poll / resume retry picks the config up as
  /// soon as the network is back — that is the reconnect path.
  static const Duration refreshInterval = Duration(seconds: 60);

  final ValueNotifier<RemoteConfig> notifier =
      ValueNotifier(const RemoteConfig());

  RemoteConfig get config => notifier.value;

  Timer? _pollTimer;
  bool _refreshing = false;

  /// Loads the cache first (fast), then ALWAYS fetches fresh from the
  /// network — no TTL gate anymore — and starts the ~60s poll. Never
  /// blocks the first frame; failures stay silent and keep the cache.
  Future<void> init() async {
    await _loadFromCache();
    // Fetch on each cold start. Fire-and-forget: the cached config is
    // already on screen; the network result lands via [notifier].
    unawaited(_refresh());
    startPolling();
  }

  /// Public refresh: fetch the config now. Called on app resume (by
  /// MainShell) and by the poll timer. Safe to call any time — a fetch
  /// already in flight is skipped instead of stacking.
  Future<void> refresh() => _refresh();

  /// Start the ~60s background poll. Idempotent: restarts the timer.
  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      refreshInterval,
      (_) => unawaited(_refresh()),
    );
  }

  /// Stop the background poll (called when the shell goes away).
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) {
        notifier.value = RemoteConfig.fromJson(parsed);
      }
    } catch (_) {
      // Corrupt cache is ignored: defaults survive.
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = _fetchTimeout;
      final request = await client.getUrl(Uri.parse(_url));
      final response = await request.close().timeout(_fetchTimeout);
      if (response.statusCode != HttpStatus.ok) return;
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_fetchTimeout);
      final parsed = jsonDecode(body);
      if (parsed is! Map<String, dynamic>) return;
      final remote = RemoteConfig.fromJson(parsed);
      notifier.value = remote;
      // Save the fresh config — survives the next cold start.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, body);
    } catch (_) {
      // Fail-soft: keep cache/defaults.
    } finally {
      _refreshing = false;
      client?.close(force: true);
    }
  }
}
