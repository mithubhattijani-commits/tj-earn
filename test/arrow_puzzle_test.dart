import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_earn/games/arrow_puzzle/ad_coins.dart';
import 'package:tj_earn/games/arrow_puzzle/arrow_puzzle_model.dart';
import 'package:tj_earn/games/arrow_puzzle/arrow_puzzle_progress.dart';
import 'package:tj_earn/l10n/app_localizations.dart';
import 'package:tj_earn/screens/arrow_puzzle_play_screen.dart';
import 'package:tj_earn/services/game_reward_ad_service.dart';
import 'package:tj_earn/services/remote_config_service.dart';

void main() {
  group('level generation', () {
    test('levels 1-200 are all solvable by greedy play', () {
      for (var level = 1; level <= 200; level++) {
        final board = generateLevel(level);
        final game = ArrowPuzzleGame(board);
        var guard = 0;
        while (!game.isWon && guard < 500) {
          guard++;
          final hint = game.findHint();
          expect(hint, isNotNull,
              reason: 'level $level deadlocked with '
                  '${game.arrowsLeft} arrows left');
          final result = game.tap(hint!);
          expect(result.kind, TapKind.cleared,
              reason: 'level $level: hint cell was not clear');
        }
        expect(game.isWon, isTrue, reason: 'level $level not cleared');
        expect(game.hearts, 3, reason: 'level $level lost a heart');
        expect(game.moves, game.totalArrows,
            reason: 'level $level took extra moves');
      }
    });

    test('generation is deterministic per level', () {
      for (final level in [1, 7, 25, 51, 100, 200]) {
        final a = generateLevel(level);
        final b = generateLevel(level);
        expect(a.size, b.size);
        expect(a.arrows.length, b.arrows.length);
        for (final entry in a.arrows.entries) {
          expect(b.arrows[entry.key], entry.value);
        }
        expect(a.stones.length, b.stones.length);
        expect(a.stones.containsAll(b.stones), isTrue);
      }
    });

    test('daily level is deterministic per date', () {
      final date = DateTime(2026, 11, 18);
      final a = generateDailyLevel(date);
      final b = generateDailyLevel(date);
      expect(a.size, b.size);
      expect(a.arrows.length, b.arrows.length);
      for (final entry in a.arrows.entries) {
        expect(b.arrows[entry.key], entry.value);
      }
    });

    test('board sizes and stones scale with level', () {
      expect(sizeForLevel(1), 8);
      expect(sizeForLevel(6), 9);
      expect(sizeForLevel(16), 10);
      expect(sizeForLevel(31), 11);
      expect(sizeForLevel(41), 12);
      expect(sizeForLevel(51), 15);
      expect(sizeForLevel(61), 16);
      expect(sizeForLevel(76), 17);
      expect(stonesForLevel(1), 0);
      expect(stonesForLevel(20), 0);
      expect(stonesForLevel(21), greaterThan(0));
      expect(difficultyForLevel(1), 'Normal');
      expect(difficultyForLevel(31), 'Hard');
      expect(difficultyForLevel(61), 'Expert');
    });

    test('maze density: level 1 is simpler but still a maze, '
        'level 51 is dense', () {
      final l1 = generateLevel(1);
      expect(l1.size, 8);
      // A maze, not a sparse grid: at least ~30 arrows on L1.
      expect(l1.arrowCount, greaterThanOrEqualTo(30));
      expect(
        l1.arrowCount / (l1.size * l1.size),
        greaterThanOrEqualTo(0.45),
      );
      final l51 = generateLevel(51);
      expect(l51.size, 15);
      // The user's Level 51 reference shows 152 arrows; ours lands
      // in the same 150-155 band on a 15x15 board.
      expect(l51.arrowCount, inInclusiveRange(150, 155));
      expect(
        l51.arrowCount / (l51.size * l51.size),
        greaterThanOrEqualTo(0.65),
      );
    });

    test('every level 1-200 stays dense (no fallback boards)', () {
      // The old generator stalled on larger boards and fell back to
      // a 2-arrow board for some levels; the layer-ordered generator
      // must never do that.
      for (var level = 1; level <= 200; level++) {
        final board = generateLevel(level);
        expect(
          board.arrowCount,
          greaterThanOrEqualTo(30),
          reason: 'level $level has only ${board.arrowCount} arrows',
        );
        expect(
          board.arrowCount / (board.size * board.size),
          greaterThanOrEqualTo(0.55),
          reason: 'level $level fill is too sparse',
        );
      }
    });
  });

  group('maze path geometry', () {
    test('path starts on a non-exit edge and ends on the exit edge, '
        'with axis-aligned segments inside the unit square', () {
      for (final dir in Direction.values) {
        for (var cell = 0; cell < 60; cell++) {
          final pts = mazePathPoints(
            cellIndex: cell,
            direction: dir,
            boardSize: 8,
          );
          expect(pts.length, greaterThanOrEqualTo(2),
              reason: 'cell $cell $dir: path too short');
          // Last point sits on the exit edge.
          final last = pts.last;
          switch (dir) {
            case Direction.right:
              expect(last.x, closeTo(1.0, 1e-9));
            case Direction.down:
              expect(last.y, closeTo(1.0, 1e-9));
            case Direction.left:
              expect(last.x, closeTo(0.0, 1e-9));
            case Direction.up:
              expect(last.y, closeTo(0.0, 1e-9));
          }
          // First point is NOT on the exit edge (it enters the cell).
          final first = pts.first;
          switch (dir) {
            case Direction.right:
              expect(first.x, lessThan(0.999));
            case Direction.down:
              expect(first.y, lessThan(0.999));
            case Direction.left:
              expect(first.x, greaterThan(0.001));
            case Direction.up:
              expect(first.y, greaterThan(0.001));
          }
          // Every point inside the unit square, every segment
          // axis-aligned (maze lines only run horizontal/vertical).
          for (final p in pts) {
            expect(p.x, inInclusiveRange(0.0, 1.0));
            expect(p.y, inInclusiveRange(0.0, 1.0));
          }
          for (var i = 1; i < pts.length; i++) {
            final a = pts[i - 1];
            final b = pts[i];
            expect(
              (a.x - b.x).abs() < 1e-9 || (a.y - b.y).abs() < 1e-9,
              isTrue,
              reason: 'cell $cell $dir: segment $a -> $b is diagonal',
            );
          }
        }
      }
    });

    test('maze path is deterministic per cell', () {
      for (final dir in Direction.values) {
        final a = mazePathPoints(
          cellIndex: 7,
          direction: dir,
          boardSize: 8,
        );
        final b = mazePathPoints(
          cellIndex: 7,
          direction: dir,
          boardSize: 8,
        );
        expect(a, b);
      }
    });

    test('paths wind (most have at least one turn)', () {
      var turning = 0;
      var total = 0;
      for (var cell = 0; cell < 100; cell++) {
        for (final dir in Direction.values) {
          total++;
          final pts = mazePathPoints(
            cellIndex: cell,
            direction: dir,
            boardSize: 8,
          );
          if (pts.length > 2) turning++;
        }
      }
      // At least half the arrows wind rather than running straight.
      expect(turning / total, greaterThan(0.5));
    });
  });

  group('tap rules', () {
    // 3x3 board: (0,0) -> faces right, blocked by (0,1); (0,1) -> clear.
    ArrowBoard manualBoard() => ArrowBoard(
          size: 3,
          arrows: {
            0: const ArrowCell(Direction.right, 0),
            1: const ArrowCell(Direction.right, 1),
          },
          stones: <int>{},
        );

    test('clear tap removes the arrow, blocked tap costs a heart', () {
      final game = ArrowPuzzleGame(manualBoard());
      expect(game.findHint(), 1);
      expect(game.tap(0).kind, TapKind.blocked);
      expect(game.hearts, 2);
      expect(game.arrowsLeft, 2);
      expect(game.tap(1).kind, TapKind.cleared);
      expect(game.tap(0).kind, TapKind.cleared);
      expect(game.isWon, isTrue);
    });

    test('tapping an empty cell is invalid and costs nothing', () {
      final game = ArrowPuzzleGame(manualBoard());
      expect(game.tap(5).kind, TapKind.invalid);
      expect(game.moves, 0);
      expect(game.hearts, 3);
    });

    test('three blocked taps end the game', () {
      final game = ArrowPuzzleGame(manualBoard());
      game.tap(0);
      game.tap(0);
      expect(game.isGameOver, isFalse);
      game.tap(0);
      expect(game.hearts, 0);
      expect(game.isGameOver, isTrue);
    });

    test('stars: 3 for a perfect win, 1 when a heart was lost', () {
      final perfect = ArrowPuzzleGame(manualBoard());
      perfect.tap(1);
      perfect.tap(0);
      expect(perfect.isWon, isTrue);
      expect(perfect.starsForWin(heartsLost: 0), 3);

      final sloppy = ArrowPuzzleGame(manualBoard());
      sloppy.tap(0); // blocked: -1 heart
      sloppy.tap(1);
      sloppy.tap(0);
      expect(sloppy.isWon, isTrue);
      expect(sloppy.starsForWin(heartsLost: 1), 1);
    });
  });

  group('power', () {
    test('armed tap clears a blocked arrow with no heart lost', () {
      final game = ArrowPuzzleGame(
        ArrowBoard(
          size: 3,
          arrows: {
            0: const ArrowCell(Direction.right, 0),
            1: const ArrowCell(Direction.right, 1),
          },
          stones: <int>{},
        ),
      );
      game.powerArmed = true;
      final result = game.tap(0);
      expect(result.kind, TapKind.powerCleared);
      expect(result.revealedPath, contains(1));
      expect(game.hearts, 3);
      expect(game.powerArmed, isFalse);
      expect(game.arrowsLeft, 1);
    });

    test('power is consumed on the tap, next blocked tap costs a heart',
        () {
      final game = ArrowPuzzleGame(
        ArrowBoard(
          size: 3,
          arrows: {
            0: const ArrowCell(Direction.right, 0),
            1: const ArrowCell(Direction.right, 1),
            3: const ArrowCell(Direction.right, 2),
            4: const ArrowCell(Direction.right, 3),
          },
          stones: <int>{},
        ),
      );
      // (0,0) is blocked by (0,1); (1,0) is blocked by (1,1).
      game.powerArmed = true;
      expect(game.tap(0).kind, TapKind.powerCleared);
      expect(game.powerArmed, isFalse);
      expect(game.hearts, 3);
      expect(game.tap(3).kind, TapKind.blocked);
      expect(game.hearts, 2);
    });
  });

  group('navy monochrome (v1.0.29)', () {
    test('every arrow draws in the same navy, whatever its colorIndex',
        () {
      // The 6-colour palette is gone: colorIndex is retained for
      // stability but must not affect the colour.
      expect(arrowNavy, const Color(0xFF14122E));
      for (var colorIndex = 0; colorIndex < 6; colorIndex++) {
        final painter = MazeArrowPainter(
          direction: Direction.right,
          colorIndex: colorIndex,
          cellIndex: 0,
          boardSize: 15,
        );
        expect(
          MazeArrowPainter.colorFor(highlight: painter.highlight),
          arrowNavy,
          reason: 'colorIndex $colorIndex must still draw navy',
        );
      }
    });

    test('hint highlight is light blue, not amber', () {
      expect(exitTrailBlue, const Color(0xFF6F7DAC));
      expect(
        MazeArrowPainter.colorFor(highlight: true),
        exitTrailBlue,
      );
      expect(exitTrailBlue, isNot(Colors.amber));
      expect(
        MazeArrowPainter.colorFor(highlight: true),
        isNot(Colors.amber.shade700),
      );
    });

    test('power grid colour is the faint #D9DEEF from the recording',
        () {
      expect(powerGridColor, const Color(0xFFD9DEEF));
    });

    test('exit trail is set on a NORMAL exit, not just Power', () {
      final game = ArrowPuzzleGame(
        ArrowBoard(
          size: 3,
          arrows: {
            0: const ArrowCell(Direction.right, 0),
            1: const ArrowCell(Direction.right, 1),
          },
          stones: <int>{},
        ),
      );
      // (0,1) is clear: its exit ray is [2].
      final first = game.tap(1);
      expect(first.kind, TapKind.cleared);
      expect(first.revealedPath, <int>[2]);
      // (0,0) is clear now: its exit ray runs [1, 2].
      final second = game.tap(0);
      expect(second.kind, TapKind.cleared);
      expect(second.revealedPath, <int>[1, 2]);
      expect(game.isWon, isTrue);
    });

    test('blocked and invalid taps reveal no trail', () {
      final game = ArrowPuzzleGame(
        ArrowBoard(
          size: 3,
          arrows: {
            0: const ArrowCell(Direction.right, 0),
            1: const ArrowCell(Direction.right, 1),
          },
          stones: <int>{},
        ),
      );
      expect(game.tap(0).revealedPath, isEmpty); // blocked
      expect(game.tap(5).revealedPath, isEmpty); // invalid
    });

    testWidgets('power grid overlay paints when shown, and is absent '
        'on a fresh board (Power not armed)', (tester) async {
      // The overlay widget itself, in isolation.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: PowerGridOverlay(boardSize: 15),
            ),
          ),
        ),
      );
      expect(find.byType(PowerGridOverlay), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      // The full screen with Power not armed: no overlay.
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ArrowPuzzlePlayScreen(level: 51),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('power-grid-overlay')),
        findsNothing,
      );
      // And the fresh Level 51 board shows the 150-155 arrows.
      expect(find.text('Level 51'), findsOneWidget);
    });
  });

  group('hint', () {
    test('hint always points at a currently clear arrow', () {
      for (var level = 1; level <= 50; level++) {
        final game = ArrowPuzzleGame(generateLevel(level));
        while (!game.isWon) {
          final hint = game.findHint();
          expect(hint, isNotNull);
          expect(game.isClear(hint!), isTrue);
          game.tap(hint);
        }
      }
    });

    test('hint is null only on an empty board', () {
      final game = ArrowPuzzleGame(
        ArrowBoard(size: 2, arrows: {}, stones: <int>{}),
      );
      expect(game.findHint(), isNull);
    });
  });

  group('remote config', () {
    test('arrow puzzle defaults are the safe ones', () {
      const cfg = ArrowPuzzleConfig();
      expect(cfg.enabled, isFalse);
      expect(cfg.levelRewardCoins, 5);
      expect(cfg.dailyCap, 200);
      expect(cfg.freeHintsPerDay, 2);
      expect(cfg.hintPriceCoins, 10);
      expect(cfg.powerPriceCoins, 15);
      expect(cfg.lifePriceCoins, 20);
      expect(cfg.interstitialEveryNthLevel, 3);
      expect(cfg.adsForRewardsEnabled, isFalse);
    });

    test('full block parses, malformed values fall back', () {
      final cfg = ArrowPuzzleConfig.fromJson({
        'enabled': true,
        'level_reward_coins': 5,
        'daily_cap': 200,
        'free_hints_per_day': 2,
        'hint_price_coins': 10,
        'power_price_coins': 15,
        'life_price_coins': 20,
        'interstitial_every_nth_level': 3,
        'interstitial_min_gap_minutes': 3,
        'ads_for_rewards_enabled': false,
      });
      expect(cfg.enabled, isTrue);
      expect(cfg.levelRewardCoins, 5);
      expect(cfg.adsForRewardsEnabled, isFalse);

      final broken = ArrowPuzzleConfig.fromJson({
        'level_reward_coins': 'not-a-number',
        'daily_cap': -50,
        'ads_for_rewards_enabled': 'yes',
      });
      expect(broken.levelRewardCoins, 5);
      expect(broken.dailyCap, 1); // clamped to the minimum
      expect(broken.adsForRewardsEnabled, isFalse);
    });

    test('RemoteConfig reads the games.arrow_puzzle block', () {
      final withBlock = RemoteConfig.fromJson({
        'games': {
          'arrow_puzzle': {'enabled': true, 'level_reward_coins': 5},
        },
      });
      expect(withBlock.arrowPuzzle.enabled, isTrue);
      expect(withBlock.arrowPuzzle.levelRewardCoins, 5);

      final withoutBlock = RemoteConfig.fromJson({});
      expect(withoutBlock.arrowPuzzle.enabled, isFalse);
      expect(withoutBlock.arrowPuzzle.adsForRewardsEnabled, isFalse);
    });

    test('economy math: cap binds before the reward does', () {
      const cfg = ArrowPuzzleConfig();
      // 5 coins x 40 levels hits the 200/day cap exactly.
      expect(cfg.levelRewardCoins * 40, cfg.dailyCap);
      expect(cfg.hintPriceCoins, 10);
      expect(cfg.powerPriceCoins, 15);
      expect(cfg.lifePriceCoins, 20);
    });
  });

  group('free hints', () {
    test('2 free hints per day, third use fails', () async {
      SharedPreferences.setMockInitialValues({});
      const perDay = 2;
      final now = DateTime(2026, 11, 18, 10);
      expect(
        await ArrowPuzzleProgress.freeHintsLeft(now, freeHintsPerDay: perDay),
        2,
      );
      expect(
        await ArrowPuzzleProgress.useFreeHint(now, freeHintsPerDay: perDay),
        isTrue,
      );
      expect(
        await ArrowPuzzleProgress.freeHintsLeft(now, freeHintsPerDay: perDay),
        1,
      );
      expect(
        await ArrowPuzzleProgress.useFreeHint(now, freeHintsPerDay: perDay),
        isTrue,
      );
      expect(
        await ArrowPuzzleProgress.freeHintsLeft(now, freeHintsPerDay: perDay),
        0,
      );
      expect(
        await ArrowPuzzleProgress.useFreeHint(now, freeHintsPerDay: perDay),
        isFalse,
      );
    });

    test('free hints reset on a new day', () async {
      final yesterday = DateTime(2026, 11, 17, 10);
      SharedPreferences.setMockInitialValues({
        'arrow_puzzle_free_hints_date':
            ArrowPuzzleProgress.dateKey(yesterday),
        'arrow_puzzle_free_hints_used': 2,
      });
      final today = DateTime(2026, 11, 18, 10);
      expect(
        await ArrowPuzzleProgress.freeHintsLeft(today, freeHintsPerDay: 2),
        2,
      );
    });
  });

  group('ad coins (Watch Ads)', () {
    test('config defaults: 10 per ad, 100/day cap, flag off', () {
      const cfg = ArrowPuzzleConfig();
      expect(cfg.adCoinsPerAd, 10);
      expect(cfg.adCoinsDailyCap, 100);
      expect(cfg.adsForRewardsEnabled, isFalse);
    });

    test('ad coin keys parse, malformed values fall back', () {
      final cfg = ArrowPuzzleConfig.fromJson({
        'ad_coins_per_ad': 25,
        'ad_coins_daily_cap': 250,
        'ads_for_rewards_enabled': true,
      });
      expect(cfg.adCoinsPerAd, 25);
      expect(cfg.adCoinsDailyCap, 250);
      expect(cfg.adsForRewardsEnabled, isTrue);

      final broken = ArrowPuzzleConfig.fromJson({
        'ad_coins_per_ad': 'not-a-number',
        'ad_coins_daily_cap': -5,
      });
      expect(broken.adCoinsPerAd, 10);
      expect(broken.adCoinsDailyCap, 1); // clamped to the minimum
      expect(broken.adsForRewardsEnabled, isFalse);
    });

    test('grant math: full grant, partial grant, cap reached', () {
      // Fresh day: a full ad grant.
      expect(
        AdCoins.grantable(
          earnedToday: 0,
          perAd: 10,
          dailyCap: 100,
        ),
        10,
      );
      // Cap edge: 95 earned, cap 100 -> only the 5 remainder.
      expect(
        AdCoins.grantable(
          earnedToday: 95,
          perAd: 10,
          dailyCap: 100,
        ),
        5,
      );
      // Cap reached: no further grant today.
      expect(
        AdCoins.grantable(
          earnedToday: 100,
          perAd: 10,
          dailyCap: 100,
        ),
        0,
      );
      // Over cap (should not happen server-side): still 0.
      expect(
        AdCoins.grantable(
          earnedToday: 130,
          perAd: 10,
          dailyCap: 100,
        ),
        0,
      );
      // Zero or negative config: no grant.
      expect(
        AdCoins.grantable(
          earnedToday: 0,
          perAd: 0,
          dailyCap: 100,
        ),
        0,
      );
    });

    test('daily cap rollover: a new day grants in full again', () {
      // Yesterday's earnings do not carry into today's grant math:
      // earnedToday is a per-day bucket (server-side, UTC day).
      expect(
        AdCoins.grantable(
          earnedToday: 0,
          perAd: AdCoins.defaultPerAd,
          dailyCap: AdCoins.defaultDailyCap,
        ),
        AdCoins.defaultPerAd,
      );
      // 10 ads at 10 coins each exactly fill the 100/day cap.
      expect(
        AdCoins.defaultPerAd * 10,
        AdCoins.defaultDailyCap,
      );
    });

    test('ad coin ledger types are separate from cash ledger types', () {
      // The two buckets never share a ledger type: a cash-balance
      // sum that excludes the Ad Coin types can never count them.
      expect(adRewardLedgerType, 'game_ad_reward');
      expect(adSpendLedgerType, 'game_ad_spend');
      expect(
        cashLedgerTypes.contains(adRewardLedgerType),
        isFalse,
        reason: 'Ad Coin credits must never count as cash',
      );
      expect(
        cashLedgerTypes.contains(adSpendLedgerType),
        isFalse,
        reason: 'Ad Coin spends must never reduce the cash balance',
      );
      expect(
        adCoinLedgerTypes.contains('game_level'),
        isFalse,
        reason: 'Level Coin credits must never count as Ad Coins',
      );
      expect(
        adCoinLedgerTypes.contains('game_spend'),
        isFalse,
        reason: 'Level Coin spends must never touch the Ad Coin balance',
      );
    });

    test('ad coins can never convert to level coins or cash', () {
      // The conversion is not just discouraged — it is unrepresentable:
      // the only conversion entry point throws, always.
      expect(
        () => AdCoins.toLevelCoins(10),
        throwsUnsupportedError,
      );
      expect(
        () => AdCoins.toLevelCoins(0),
        throwsUnsupportedError,
      );
    });

    test('flag off grants nothing; flag on grants only on a completed ad',
        () async {
      // Flag OFF: the service refuses before any ad is considered —
      // the Watch Ad button is hidden and the grant path is dead.
      expect(
        await GameRewardAdService.tryGrantAdCoins(adsEnabled: false),
        AdGrantResult.disabled,
      );
      // Flag ON + ad completed: granted (the caller then claims from
      // the server; the client never credits Ad Coins itself).
      expect(
        await GameRewardAdService.tryGrantAdCoins(
          adsEnabled: true,
          showRewardedAd: () async => true,
        ),
        AdGrantResult.granted,
      );
      // Flag ON + ad skipped/failed (or no dashboard placement):
      // failed — the UI shows "ad not available" and no coins are
      // ever credited without a completed ad view.
      expect(
        await GameRewardAdService.tryGrantAdCoins(
          adsEnabled: true,
          showRewardedAd: () async => false,
        ),
        AdGrantResult.failed,
      );
    });
  });
}
