import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tj_earn/games/tj_racing/ad_coins.dart';
import 'package:tj_earn/games/tj_racing/coins_rs.dart';
import 'package:tj_earn/games/tj_racing/race_rewards.dart';
import 'package:tj_earn/games/tj_racing/unity_bridge.dart';
import 'package:tj_earn/services/remote_config_service.dart';
import 'package:tj_earn/services/validation.dart' show formatCoinsAsPkr;

void main() {
  group('TjRacingConfig.fromJson', () {
    test('defaults match plan §9 when games.tj_racing is absent', () {
      final config = RemoteConfig.fromJson({}).tjRacing;
      expect(config.enabled, isFalse);
      expect(config.title, 'TJ Racing 3D');
      expect(config.levelCoins.win, 10);
      expect(config.levelCoins.second, 5);
      expect(config.levelCoins.third, 0);
      expect(config.levelCoins.finish, 0);
      expect(config.levelCoins.dailyCap, 200);
      expect(config.levelCoins.coinsPerPkr, 100);
      expect(config.levelCoins.minWithdrawalCoins, 10000);
      expect(config.levelCoins.showRsValue, isTrue);
      expect(config.adCoins.perRewardedAd, 10);
      expect(config.adCoins.dailyCap, 100);
      expect(config.adCoins.cashConvertible, isFalse);
      expect(config.ads.interstitialEveryNRaces, 3);
      expect(config.ads.interstitialMinIntervalSecs, 180);
      expect(config.race.laps, 3);
      expect(config.race.aiOpponents, 5);
      expect(config.race.nitroEnabled, isTrue);
      expect(config.race.firstTrack.id, 'night_city_1');
      expect(config.cars.length, 5);
      expect(config.cars.last.adCoinsPrice, 1200);
      expect(config.cars.last.isLuxury, isTrue);
      expect(config.powerups.length, 2);
      // Unity runtime fields (Unity shipped defaults).
      expect(config.tiltDeadZoneDeg, 10);
      expect(config.tiltSensitivity, 1.0);
      expect(config.hardLevelThreshold, 3);
      expect(config.adsMinGapSecs, 90);
      expect(config.firstRaceAiSlowdownPct, 25);
    });

    test('car stats default to Unity CarCatalogue values', () {
      final config = RemoteConfig.fromJson({}).tjRacing;
      final king = config.carById('thunder_king')!;
      expect(king.topSpeedKmh, 232);
      expect(king.acceleration, 17);
      expect(king.handling, 1.2);
      expect(king.nitroCapacity, 130);
      expect(king.bodyColorHex, '#12C2A0');
      final hawk = config.carById('street_hawk')!;
      expect(hawk.topSpeedKmh, 178);
      // Stats differ per car — that IS the progression. If they
      // were all equal, Unity would drive every car at the same
      // speed (JsonUtility keeps C# defaults for missing keys).
      final speeds = config.cars.map((c) => c.topSpeedKmh).toSet();
      expect(speeds.length, 5);
    });

    test('parses the full plan §9 block', () {
      final config = RemoteConfig.fromJson({
        'games': {
          'tj_racing': {
            'enabled': true,
            'title': 'TJ Racing 3D',
            'level_coins': {
              'win': 10,
              'second': 5,
              'third': 0,
              'finish': 0,
              'daily_cap': 200,
              'coins_per_pkr': 100,
              'min_withdrawal_coins': 10000,
              'show_rs_value': true,
            },
            'ad_coins': {
              'per_rewarded_ad': 10,
              'daily_cap': 100,
              'cash_convertible': false,
            },
            'ads': {
              'banner_enabled': true,
              'interstitial_enabled': true,
              'interstitial_every_n_races': 3,
              'interstitial_min_interval_secs': 180,
              'rewarded_enabled': true,
            },
            'race': {
              'laps': 3,
              'ai_opponents': 5,
              'nitro_enabled': true,
              'tracks': [
                {'id': 'night_city_1', 'name': 'Night City', 'locked': false},
              ],
            },
            'cars': [
              {
                'id': 'street_hawk',
                'name': 'Street Hawk',
                'class': 'standard',
                'ad_coins_price': 0,
              },
              {
                'id': 'thunder_king',
                'name': 'Thunder King',
                'class': 'luxury',
                'ad_coins_price': 1200,
              },
            ],
            'powerups': [
              {
                'id': 'nitro_boost',
                'name': 'Nitro Boost',
                'ad_coins_price': 10,
              },
            ],
          },
        },
      }).tjRacing;
      expect(config.enabled, isTrue);
      expect(config.cars.length, 2);
      expect(config.carById('thunder_king')?.isLuxury, isTrue);
      expect(config.carById('thunder_king')?.topSpeedKmh, 232);
      expect(config.carById('street_hawk')?.isFree, isTrue);
      expect(config.powerupById('nitro_boost')?.adCoinsPrice, 10);
      expect(config.powerupById('missing'), isNull);
    });

    test('malformed values fall back to defaults, never crash', () {
      final config = TjRacingConfig.fromJson({
        'enabled': 'yes',
        'level_coins': {'win': 'ten', 'daily_cap': -5},
        'cars': 'not-a-list',
        'powerups': [
          {'id': '', 'name': '', 'ad_coins_price': 10},
        ],
      });
      expect(config.enabled, isFalse);
      expect(config.levelCoins.win, 10);
      expect(config.levelCoins.dailyCap, 1);
      expect(config.cars.length, 5);
      expect(config.powerups.length, 2);
    });

    test('clamps out-of-range values', () {
      final config = TjRacingConfig.fromJson({
        'level_coins': {'win': 9999, 'coins_per_pkr': 0},
        'ads': {
          'interstitial_every_n_races': 0,
          'interstitial_min_interval_secs': 99999,
        },
        'race': {'laps': 99, 'ai_opponents': 99},
      });
      expect(config.levelCoins.win, 100);
      expect(config.levelCoins.coinsPerPkr, 1);
      expect(config.ads.interstitialEveryNRaces, 1);
      expect(config.ads.interstitialMinIntervalSecs, 3600);
      expect(config.race.laps, 10);
      expect(config.race.aiOpponents, 11);
    });

    test('toJson emits Unity exact key shape, stats included', () {
      final json = RemoteConfig.fromJson({}).tjRacing.toJson();
      expect(json['level_coins']['win'], 10);
      expect(json['tiltDeadZoneDeg'], 10);
      expect(json['hardLevelThreshold'], 3);
      expect(json['adsMinGapSecs'], 90);
      expect(json['firstRaceAiSlowdownPct'], 25);
      final cars = json['cars'] as List;
      expect(cars.length, 5);
      final king = (cars.firstWhere(
            (c) => (c as Map<String, dynamic>)['id'] == 'thunder_king',
          )
          as Map<String, dynamic>);
      expect(king['topSpeedKmh'], 232);
      expect(king['class'], 'luxury');
      // Round-trip: parse the emitted JSON back.
      final reparsed = TjRacingConfig.fromJson(json);
      expect(reparsed.carById('thunder_king')?.topSpeedKmh, 232);
      expect(reparsed.tiltDeadZoneDeg, 10);
    });
  });

  group('raceLevelCoinsForPosition', () {
    test('win 10, second 5, third/finish 0 (user-confirmed)', () {
      int coins(int position) => raceLevelCoinsForPosition(
            position,
            win: 10,
            second: 5,
            third: 0,
            finish: 0,
          );
      expect(coins(1), 10);
      expect(coins(2), 5);
      expect(coins(3), 0);
      expect(coins(4), 0);
      expect(coins(6), 0);
      expect(coins(0), 0);
    });

    test('follows the config values, nothing hardcoded', () {
      expect(
        raceLevelCoinsForPosition(
          1,
          win: 20,
          second: 8,
          third: 3,
          finish: 1,
        ),
        20,
      );
      expect(
        raceLevelCoinsForPosition(
          3,
          win: 20,
          second: 8,
          third: 3,
          finish: 1,
        ),
        3,
      );
    });
  });

  group('levelForRacesFinished', () {
    test('level 1 for the first 3 races, +1 every 3', () {
      expect(levelForRacesFinished(0), 1);
      expect(levelForRacesFinished(2), 1);
      expect(levelForRacesFinished(3), 2);
      expect(levelForRacesFinished(5), 2);
      expect(levelForRacesFinished(6), 3);
      expect(levelForRacesFinished(30), 11);
    });
  });

  group('Rs display', () {
    test('race result label: "10 coins = Rs 0.10"', () {
      expect(coinsRsLabel(10), '10 coins = Rs 0.10');
      expect(coinsRsLabel(500), '500 coins = Rs 5.00');
      expect(coinsRsLabel(0), '0 coins = Rs 0.00');
    });

    test('short pill form trims trailing zeros', () {
      expect(formatRsShort(1240), 'Rs 12.40');
      expect(formatRsShort(1200), 'Rs 12');
      expect(formatRsShort(10000), 'Rs 100');
      expect(formatRsShort(3700), 'Rs 37');
      expect(formatRsShort(0), 'Rs 0');
    });

    test('shared formatter agrees: 100 coins = Rs 1.00', () {
      expect(formatCoinsAsPkr(100), 'Rs 1.00');
      expect(formatCoinsAsPkr(10000), 'Rs 100.00');
      expect(formatCoinsAsPkr(5), 'Rs 0.05');
    });
  });

  group('RaceResult.tryParse (Unity RaceResult.cs shape)', () {
    test('parses a valid Unity race_result message', () {
      final result = RaceResult.tryParse(
        '{"type":"race_result","race_id":"abcdef1234567890",'
        '"track_id":"night_city_1","car_id":"street_hawk",'
        '"position":2,"total_racers":6,"laps_completed":3,'
        '"race_time_secs":83.4,"best_lap_secs":27.1,'
        '"level_coins_earned":5,"is_first_race":false}',
      );
      expect(result, isNotNull);
      expect(result!.raceId, 'abcdef1234567890');
      expect(result.trackId, 'night_city_1');
      expect(result.carId, 'street_hawk');
      expect(result.position, 2);
      expect(result.isWin, isFalse);
      expect(result.lapsCompleted, 3);
      expect(result.totalRacers, 6);
      expect(result.raceTimeSecs, 83.4);
      expect(result.bestLapSecs, 27.1);
      expect(result.levelCoinsEarned, 5);
      expect(result.isFirstRace, isFalse);
    });

    test('win is position 1', () {
      final result = RaceResult.tryParse(
        '{"type":"race_result","race_id":"r","position":1,'
        '"laps_completed":3,"total_racers":6}',
      );
      expect(result!.isWin, isTrue);
      // level_coins_earned is absent here — the server re-derives
      // from position, so its absence must never block a claim.
      expect(result.levelCoinsEarned, isNull);
    });

    test('rejects anything else — no claim from garbage', () {
      expect(RaceResult.tryParse('touch'), isNull);
      expect(RaceResult.tryParse('not json'), isNull);
      expect(
        RaceResult.tryParse('{"type":"race_quit","race_id":"r"}'),
        isNull,
      );
      expect(
        RaceResult.tryParse(
          '{"type":"race_result","race_id":"","position":1,'
          '"laps_completed":3,"total_racers":6}',
        ),
        isNull,
      );
      expect(
        RaceResult.tryParse(
          '{"type":"race_result","race_id":"r","position":7,'
          '"laps_completed":3,"total_racers":6}',
        ),
        isNull,
      );
      expect(
        RaceResult.tryParse(
          '{"type":"race_result","race_id":"r","position":1,'
          '"laps_completed":-1,"total_racers":6}',
        ),
        isNull,
      );
    });
  });

  group('UnityEvent + detail parsers', () {
    test('race_started detail parses track + laps', () {
      final event = UnityEvent.tryParse(
        '{"type":"race_started","placement":"","race_id":"abc",'
        '"detail":"{\\"track\\":\\"night_city_1\\",\\"laps\\":3}"}',
      );
      expect(event, isNotNull);
      final detail = RaceStartedDetail.tryParse(event!.detail);
      expect(detail?.track, 'night_city_1');
      expect(detail?.laps, 3);
    });

    test('rewarded_completed detail carries the requestId', () {
      final event = UnityEvent.tryParse(
        '{"type":"rewarded_completed","placement":"BP_Rewarded_Android",'
        '"race_id":"","detail":"{\\"requestId\\":\\"ad-reward-abc123\\"}"}',
      );
      expect(event, isNotNull);
      final detail = RewardedDetail.tryParse(event!.detail);
      expect(detail?.requestId, 'ad-reward-abc123');
      expect(detail?.reason, isNull);
    });

    test('rewarded_failed detail carries requestId + reason', () {
      final detail = RewardedDetail.tryParse(
        '{"requestId":"ad-reward-xyz","reason":"SHOW_ERROR"}',
      );
      expect(detail?.requestId, 'ad-reward-xyz');
      expect(detail?.reason, 'SHOW_ERROR');
    });

    test('car_locked_tapped detail carries carId + price', () {
      final event = UnityEvent.tryParse(
        '{"type":"car_locked_tapped","placement":"","race_id":"",'
        '"detail":"{\\"carId\\":\\"night_falcon\\",\\"price\\":200}"}',
      );
      expect(event, isNotNull);
      final detail = CarLockedDetail.tryParse(event!.detail);
      expect(detail?.carId, 'night_falcon');
      expect(detail?.price, 200);
    });

    test('powerup_purchase_requested detail carries powerupId + price', () {
      final event = UnityEvent.tryParse(
        '{"type":"powerup_purchase_requested","placement":"",'
        '"race_id":"","detail":'
        '"{\\"powerupId\\":\\"nitro_boost\\",\\"price\\":10}"}',
      );
      expect(event, isNotNull);
      final detail = PowerupPurchaseDetail.tryParse(event!.detail);
      expect(detail?.powerupId, 'nitro_boost');
      expect(detail?.price, 10);
      // Rejects garbage — a malformed detail must never open a
      // purchase dialog.
      expect(PowerupPurchaseDetail.tryParse('not json'), isNull);
      expect(PowerupPurchaseDetail.tryParse('{"price":10}'), isNull);
      expect(
        PowerupPurchaseDetail.tryParse(
          '{"powerupId":"","price":10}',
        ),
        isNull,
      );
      expect(
        PowerupPurchaseDetail.tryParse(
          '{"powerupId":"shield","price":"15"}',
        ),
        isNull,
      );
    });

    test('race_powerup item id shape for spend-race-item', () {
      expect(racePowerupItemId('nitro_boost'), 'race_powerup_nitro_boost');
      expect(racePowerupItemId('shield'), 'race_powerup_shield');
    });

    test('race_result is not a UnityEvent; garbage is not either', () {
      expect(
        UnityEvent.tryParse(
          '{"type":"race_result","race_id":"r","position":1,'
          '"laps_completed":3,"total_racers":6}',
        ),
        isNull,
      );
      expect(UnityEvent.tryParse('hello'), isNull);
      expect(UnityEvent.tryParse('{"type":""}'), isNull);
    });
  });

  group('UnityIncoming.parse', () {
    test('routes every Unity message type', () {
      expect(
        UnityIncoming.parse(
          '{"type":"race_result","race_id":"r","position":1,'
          '"laps_completed":3,"total_racers":6}',
        ).kind,
        UnityIncomingKind.raceResult,
      );
      expect(
        UnityIncoming.parse(
          '{"type":"race_cancelled","race_id":"r","detail":"{}"}',
        ).kind,
        UnityIncomingKind.raceCancelled,
      );
      expect(
        UnityIncoming.parse(
          '{"type":"interstitial_shown",'
          '"placement":"BP_Interstitial_Android","detail":"{}"}',
        ).kind,
        UnityIncomingKind.interstitialShown,
      );
      expect(
        UnityIncoming.parse(
          '{"type":"car_locked_tapped","detail":'
          '"{\\"carId\\":\\"storm_rider\\",\\"price\\":800}"}',
        ).kind,
        UnityIncomingKind.carLockedTapped,
      );
      final powerup = UnityIncoming.parse(
        '{"type":"powerup_purchase_requested","detail":'
        '"{\\"powerupId\\":\\"shield\\",\\"price\\":15}"}',
      );
      expect(powerup.kind, UnityIncomingKind.powerupPurchaseRequested);
      expect(powerup.powerupPurchase?.powerupId, 'shield');
      expect(powerup.powerupPurchase?.price, 15);
      expect(
        UnityIncoming.parse('garbage').kind,
        UnityIncomingKind.unknown,
      );
      expect(
        UnityIncoming.parse('{"type":"something_new"}').kind,
        UnityIncomingKind.unknown,
      );
    });
  });

  group('UnityBridge.envelope', () {
    test('payload is a JSON string inside the envelope', () {
      final raw = UnityBridge.envelope('SetConfig', {
        'config': '{"enabled":true}',
        'level': 1,
        'levelCoins': 1240,
        'adCoins': 50,
        'rsValue': 'Rs 12',
        'totalEarnedRs': 'Rs 37',
      });
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['method'], 'SetConfig');
      // Unity's JsonUtility cannot parse a nested raw object — the
      // payload MUST be a string.
      expect(decoded['payload'], isA<String>());
      final payload =
          jsonDecode(decoded['payload'] as String) as Map<String, dynamic>;
      expect(payload['rsValue'], 'Rs 12');
      expect(payload['totalEarnedRs'], 'Rs 37');
      expect(
        (jsonDecode(payload['config'] as String) as Map)['enabled'],
        isTrue,
      );
    });

    test('PowerupGranted envelope carries powerupId as a JSON string', () {
      for (final id in ['nitro_boost', 'shield']) {
        final raw = UnityBridge.envelope('PowerupGranted', {'powerupId': id});
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        expect(decoded['method'], 'PowerupGranted');
        // Unity's JsonUtility cannot parse a nested raw object —
        // the payload MUST be a string (same as every method).
        expect(decoded['payload'], isA<String>());
        final payload =
            jsonDecode(decoded['payload'] as String) as Map<String, dynamic>;
        expect(payload['powerupId'], id);
      }
    });

    // Placement guarantee (verified by reading
    // `_showPowerupPurchaseDialog` — the dialog needs the Unity
    // widget + a server, so there is no widget test for it):
    // `sendPowerupGranted` is called ONLY inside the try block
    // after `spendRaceItem` returns. `spendRaceItem` throws on
    // 402 (not enough Ad Coins), 409 and every other non-200
    // before the send line, so a failed spend can never grant an
    // effect in Unity. A fresh spend AND an idempotent replay
    // both reach the send — either way the item IS granted.
  });

  group('AdCoins', () {
    test('grantable caps at the daily limit with partial grants', () {
      expect(
        AdCoins.grantable(earnedToday: 0, perAd: 10, dailyCap: 100),
        10,
      );
      expect(
        AdCoins.grantable(earnedToday: 95, perAd: 10, dailyCap: 100),
        5,
      );
      expect(
        AdCoins.grantable(earnedToday: 100, perAd: 10, dailyCap: 100),
        0,
      );
    });

    test('Ad Coins can never convert to Level Coins or cash', () {
      expect(
        () => AdCoins.toLevelCoins(100),
        throwsUnsupportedError,
      );
    });
  });
}
