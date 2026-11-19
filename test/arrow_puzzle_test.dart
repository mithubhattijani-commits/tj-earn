import 'dart:math';

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
  group('level generation (path model)', () {
    test('levels 1-200 are all solvable by greedy play', () {
      for (var level = 1; level <= 200; level++) {
        final board = generateLevel(level);
        final game = ArrowPuzzleGame(board);
        var guard = 0;
        while (!game.isWon && guard < 1000) {
          guard++;
          final hint = game.findHint();
          expect(hint, isNotNull,
              reason: 'level $level deadlocked with '
                  '${game.arrowsLeft} paths left');
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
        expect(a.cols, b.cols);
        expect(a.rows, b.rows);
        expect(a.pathCount, b.pathCount);
        expect(a.paths, b.paths);
      }
    });

    test('daily level is deterministic per date', () {
      final date = DateTime(2026, 11, 18);
      final a = generateDailyLevel(date);
      final b = generateDailyLevel(date);
      expect(a.cols, b.cols);
      expect(a.rows, b.rows);
      expect(a.pathCount, b.pathCount);
      expect(a.paths, b.paths);
    });

    test('board sizes scale with level (L51 is the recording 26x50)',
        () {
      // Tall rectangle at every level: rows ~ cols / 0.52, the
      // recording's aspect (~0.52). Level 51 is exactly the
      // recording's lattice: 26 cols x 50 rows.
      expect(colsForLevel(1), 10);
      expect(rowsForLevel(1), 19);
      expect(colsForLevel(6), 12);
      expect(rowsForLevel(6), 23);
      expect(colsForLevel(16), 14);
      expect(rowsForLevel(16), 27);
      expect(colsForLevel(31), 17);
      expect(rowsForLevel(31), 33);
      expect(colsForLevel(41), 21);
      expect(rowsForLevel(41), 40);
      expect(colsForLevel(51), 26);
      expect(rowsForLevel(51), 50);
      expect(colsForLevel(61), 28);
      expect(rowsForLevel(61), 54);
      expect(colsForLevel(76), 30);
      expect(rowsForLevel(76), 58);
      expect(targetPathsForLevel(51), 152);
      expect(targetPathsForLevel(1), 22);
      expect(difficultyForLevel(1), 'Normal');
      expect(difficultyForLevel(31), 'Hard');
      expect(difficultyForLevel(61), 'Expert');
    });

    test('path-cover generation: coverage, segment lengths, L51 = 152',
        () {
      final l1 = generateLevel(1);
      expect(l1.cols, 10);
      expect(l1.rows, 19);
      // A maze, not a sparse grid: ~22 paths on L1, ~55% of cells
      // covered by path cells (the coverage varies with the sampled
      // path lengths, so the floor allows for that variance).
      expect(l1.pathCount, inInclusiveRange(20, 25));
      final l1Covered =
          l1.paths.fold<int>(0, (sum, p) => sum + p.length);
      expect(l1Covered / (l1.cols * l1.rows), greaterThanOrEqualTo(0.38));

      final l51 = generateLevel(51);
      expect(l51.cols, 26);
      expect(l51.rows, 50);
      // Level 51 matches the recording: 152 paths (the recording's
      // moves counter reads 152), ~55% coverage.
      expect(l51.pathCount, inInclusiveRange(145, 160));
      final l51Covered =
          l51.paths.fold<int>(0, (sum, p) => sum + p.length);
      expect(l51Covered / (l51.cols * l51.rows),
          inInclusiveRange(0.40, 0.65));
      // Segment lengths follow the recording's measured distribution:
      // median ~4 cells, mean ~4.6, most paths 1-10 cells long.
      final lens = l51.paths.map((p) => p.length).toList()..sort();
      final median = lens[lens.length ~/ 2];
      expect(median, inInclusiveRange(3, 5));
      final mean = lens.reduce((a, b) => a + b) / lens.length;
      expect(mean, inInclusiveRange(3.5, 6.0));
      expect(lens.first, greaterThanOrEqualTo(1));
      expect(lens.last, lessThanOrEqualTo(20));
    });

    test('every level 1-200 stays dense (no fallback boards)', () {
      // The generator must reach (or nearly reach) its target path
      // count at every level — never a tiny fallback board.
      for (var level = 1; level <= 200; level++) {
        final board = generateLevel(level);
        final target = targetPathsForLevel(level);
        expect(
          board.pathCount,
          greaterThanOrEqualTo((target * 0.95).round()),
          reason: 'level $level has only ${board.pathCount} paths '
              '(target $target)',
        );
        final covered =
            board.paths.fold<int>(0, (sum, p) => sum + p.length);
        expect(
          covered / (board.cols * board.rows),
          greaterThanOrEqualTo(0.35),
          reason: 'level $level coverage is too sparse',
        );
      }
    });

    test('paths are vertex-disjoint and well-formed', () {
      for (final level in [1, 25, 51, 100, 200]) {
        final board = generateLevel(level);
        final seen = <int>{};
        for (final path in board.paths) {
          // No cell belongs to two paths.
          for (final cell in path.cells) {
            expect(seen.add(cell), isTrue,
                reason: 'level $level: cell $cell in two paths');
          }
          // Consecutive cells are orthogonally adjacent.
          for (var i = 1; i < path.cells.length; i++) {
            final a = path.cells[i - 1];
            final b = path.cells[i];
            final ar = a ~/ board.cols;
            final ac = a % board.cols;
            final br = b ~/ board.cols;
            final bc = b % board.cols;
            expect((ar - br).abs() + (ac - bc).abs(), 1,
                reason: 'level $level: path cells $a -> $b not adjacent');
          }
          // The head direction points away from the body (or is a
          // free choice for a 1-cell path).
          if (path.length > 1) {
            final head = path.headCell;
            final prev = path.cells[path.cells.length - 2];
            final hr = head ~/ board.cols;
            final hc = head % board.cols;
            final pr = prev ~/ board.cols;
            final pc = prev % board.cols;
            expect(hr - pr, path.headDirection.dRow);
            expect(hc - pc, path.headDirection.dCol);
          }
        }
        // cellToPath agrees with the paths.
        expect(board.cellToPath.length, seen.length);
      }
    });

    test('rectangular board geometry: index math and exit rays', () {
      // 4x2 board: path A = cells (0,0)-(0,1), head at (0,1) facing
      // right (ray 2, 3, clear); path B = cell (1,1) facing up
      // (ray 1 — which holds A's head, so B is blocked).
      final board = ArrowBoard(
        cols: 4,
        rows: 2,
        paths: [
          const ArrowPath([0, 1], Direction.right),
          const ArrowPath([5], Direction.up),
        ],
      );
      expect(board.index(1, 1), 5);
      expect(board.index(0, 3), 3);
      expect(board.exitRay(0), <int>[2, 3]);
      expect(board.isClear(0), isTrue);
      expect(board.exitRay(1), <int>[1]);
      expect(board.isClear(1), isFalse,
          reason: 'A\'s head sits on B\'s ray');
      expect(board.pathIdForCell(0), 0);
      expect(board.pathIdForCell(5), 1);
      expect(board.pathIdForCell(2), isNull);
    });
  });

  group('path geometry', () {
    test('path polyline runs through cell centres and ends on the '
        'exit edge, with axis-aligned segments', () {
      // Path (1,1)-(1,2) on a 4-col board, head facing right.
      final pts = pathPolylinePoints(
        pathCells: [5, 6],
        headDirection: Direction.right,
        cols: 4,
      );
      // Centres (1.5,1.5), (2.5,1.5), then the tip on the exit
      // (right) edge of cell (1,2): x == 3.
      expect(pts.length, 3);
      expect(pts.last.x, closeTo(3.0, 1e-9));
      expect(pts.last.y, closeTo(1.5, 1e-9));
      for (var i = 1; i < pts.length; i++) {
        final a = pts[i - 1];
        final b = pts[i];
        expect(
          (a.x - b.x).abs() < 1e-9 || (a.y - b.y).abs() < 1e-9,
          isTrue,
          reason: 'segment $a -> $b is diagonal',
        );
      }
    });

    test('path polyline is deterministic per path', () {
      final a = pathPolylinePoints(
        pathCells: [5, 6, 10],
        headDirection: Direction.down,
        cols: 4,
      );
      final b = pathPolylinePoints(
        pathCells: [5, 6, 10],
        headDirection: Direction.down,
        cols: 4,
      );
      expect(a, b);
    });

    test('cell segments: tail starts at the centre, middle runs '
        'edge to edge, head ends at the centre', () {
      // Straight path (0,0)-(0,1)-(0,2) on a 4-col board.
      const cells = [0, 1, 2];
      // Tail cell (0,0): starts at the centre, exits right.
      final tail = cellSegmentPoints(
        pathCells: cells,
        cellIndex: 0,
        cols: 4,
      );
      expect(tail, [
        const Point(0.5, 0.5),
        const Point(1.0, 0.5),
      ]);
      // Middle cell (0,1): enters left, exits right.
      final mid = cellSegmentPoints(
        pathCells: cells,
        cellIndex: 1,
        cols: 4,
      );
      expect(mid, [
        const Point(0.0, 0.5),
        const Point(0.5, 0.5),
        const Point(1.0, 0.5),
      ]);
      // Head cell (0,2): enters left, ends at the centre (the
      // triangle is drawn from there to the tip).
      final head = cellSegmentPoints(
        pathCells: cells,
        cellIndex: 2,
        cols: 4,
      );
      expect(head, [
        const Point(0.0, 0.5),
        const Point(0.5, 0.5),
      ]);
    });

    test('cell segments turn at right angles and join at shared edges',
        () {
      // L-shaped path (0,0)-(1,0)-(1,1) on a 4-col board.
      const cells = [0, 4, 5];
      // Cell (1,0) turns: enters from the top, exits right.
      final turn = cellSegmentPoints(
        pathCells: cells,
        cellIndex: 4,
        cols: 4,
      );
      expect(turn, [
        const Point(0.5, 0.0),
        const Point(0.5, 0.5),
        const Point(1.0, 0.5),
      ]);
      // The exit midpoint of one cell is the entry midpoint of the
      // next (in board coordinates).
      for (var i = 0; i < cells.length - 1; i++) {
        final a = cellSegmentPoints(
          pathCells: cells,
          cellIndex: cells[i],
          cols: 4,
        ).last;
        final b = cellSegmentPoints(
          pathCells: cells,
          cellIndex: cells[i + 1],
          cols: 4,
        ).first;
        final ar = cells[i] ~/ 4;
        final ac = cells[i] % 4;
        final br = cells[i + 1] ~/ 4;
        final bc = cells[i + 1] % 4;
        expect(a.x + ac, closeTo(b.x + bc, 1e-9));
        expect(a.y + ar, closeTo(b.y + br, 1e-9));
      }
    });

    test('segments wind (most multi-cell paths have a turn)', () {
      var turning = 0;
      var total = 0;
      for (var level = 1; level <= 20; level++) {
        final board = generateLevel(level);
        for (final path in board.paths) {
          if (path.length < 3) continue;
          total++;
          var hasTurn = false;
          for (var i = 2; i < path.cells.length; i++) {
            final a = path.cells[i - 2];
            final b = path.cells[i - 1];
            final c = path.cells[i];
            final d1 = (b ~/ board.cols) - (a ~/ board.cols) != 0;
            final d2 = (c ~/ board.cols) - (b ~/ board.cols) != 0;
            if (d1 != d2) hasTurn = true;
          }
          if (hasTurn) turning++;
        }
      }
      expect(turning / total, greaterThan(0.5));
    });
  });

  group('tap rules (heads only block)', () {
    // 3x3 board: path A = cell (0,0) facing right (ray 1, 2);
    // path B = cell (0,1) facing right — B's HEAD sits on A's ray,
    // so A is blocked until B leaves.
    ArrowBoard manualBoard() => ArrowBoard(
          cols: 3,
          rows: 3,
          paths: [
            const ArrowPath([0], Direction.right),
            const ArrowPath([1], Direction.right),
          ],
        );

    test('clear tap removes the path, blocked tap costs a heart', () {
      final game = ArrowPuzzleGame(manualBoard());
      expect(game.findHint(), 1);
      expect(game.tap(0).kind, TapKind.blocked);
      expect(game.hearts, 2);
      expect(game.arrowsLeft, 2);
      expect(game.tap(1).kind, TapKind.cleared);
      expect(game.tap(0).kind, TapKind.cleared);
      expect(game.isWon, isTrue);
    });

    test('tapping any cell of a path removes the WHOLE path', () {
      final game = ArrowPuzzleGame(
        ArrowBoard(
          cols: 4,
          rows: 4,
          paths: [
            // A 5-cell winding path, head at (1,2) facing right.
            const ArrowPath([4, 5, 6, 10, 11], Direction.right),
            const ArrowPath([0], Direction.down),
          ],
        ),
      );
      expect(game.arrowsLeft, 2);
      // Tap the TAIL cell of the long path.
      final result = game.tap(4);
      expect(result.kind, TapKind.cleared);
      expect(result.exitedPathCells, [4, 5, 6, 10, 11]);
      expect(game.arrowsLeft, 1);
      // Every cell of the removed path is now empty.
      for (final cell in [4, 5, 6, 10, 11]) {
        expect(game.pathIdForCell(cell), isNull);
        expect(game.tap(cell).kind, TapKind.invalid);
      }
    });

    test('moves counter = path count (one move per path)', () {
      final game = ArrowPuzzleGame(generateLevel(51));
      expect(game.arrowsLeft, game.totalArrows);
      expect(game.totalArrows, inInclusiveRange(145, 160));
      while (!game.isWon) {
        game.tap(game.findHint()!);
      }
      expect(game.moves, game.totalArrows);
      expect(game.arrowsLeft, 0);
    });

    test('a shaft on the ray does NOT block (heads-only rule)', () {
      // Path A = cell (0,0) facing right (ray 1, 2). Path C is a
      // 2-cell path whose TAIL (cell (0,2)) sits on A's ray but
      // whose head (cell (1,2), facing down) does not. Under the
      // old full-ray rule A would be blocked; under heads-only it
      // is clear — this is what the recording shows (the rope
      // passes over shafts).
      final game = ArrowPuzzleGame(
        ArrowBoard(
          cols: 3,
          rows: 3,
          paths: [
            const ArrowPath([0], Direction.right),
            const ArrowPath([2, 5], Direction.down),
          ],
        ),
      );
      expect(game.isClear(0), isTrue);
      expect(game.tap(0).kind, TapKind.cleared);
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
    test('armed tap clears a blocked path with no heart lost', () {
      final game = ArrowPuzzleGame(
        ArrowBoard(
          cols: 3,
          rows: 3,
          paths: [
            const ArrowPath([0], Direction.right),
            const ArrowPath([1], Direction.right),
          ],
        ),
      );
      game.powerArmed = true;
      final result = game.tap(0);
      expect(result.kind, TapKind.powerCleared);
      expect(result.revealedPath, contains(1));
      expect(result.exitedPathCells, [0]);
      expect(game.hearts, 3);
      expect(game.powerArmed, isFalse);
      expect(game.arrowsLeft, 1);
    });

    test('power is consumed on the tap, next blocked tap costs a heart',
        () {
      final game = ArrowPuzzleGame(
        ArrowBoard(
          cols: 3,
          rows: 3,
          paths: [
            const ArrowPath([0], Direction.right),
            const ArrowPath([1], Direction.right),
            const ArrowPath([3], Direction.right),
            const ArrowPath([4], Direction.right),
          ],
        ),
      );
      // (0,0) is blocked by (0,1)'s head; (1,0) is blocked by
      // (1,1)'s head.
      game.powerArmed = true;
      expect(game.tap(0).kind, TapKind.powerCleared);
      expect(game.powerArmed, isFalse);
      expect(game.hearts, 3);
      expect(game.tap(3).kind, TapKind.blocked);
      expect(game.hearts, 2);
    });
  });

  group('navy monochrome (v1.0.29)', () {
    test('every path draws in the same navy', () {
      // The 6-colour palette is gone: every path draws navy.
      expect(arrowNavy, const Color(0xFF14122E));
      expect(
        PathSegmentPainter.colorFor(highlight: false),
        arrowNavy,
      );
    });

    test('hint highlight is bright blue, not amber', () {
      // The recording's exiting path is a vivid blue (#3584E2,
      // median trail pixel) — not the grey slate blue used before.
      expect(exitTrailBlue, const Color(0xFF3584E2));
      expect(
        PathSegmentPainter.colorFor(highlight: true),
        exitTrailBlue,
      );
      expect(exitTrailBlue, isNot(Colors.amber));
      expect(
        PathSegmentPainter.colorFor(highlight: true),
        isNot(Colors.amber.shade700),
      );
    });

    test('empty-cell dots are the recording\'s faint grey-blue', () {
      expect(emptyDotColor, const Color(0xFFDDDEE5));
    });

    test('arrow shafts and heads match the recording\'s proportions',
        () {
      // Shafts ~3px on a 19px pitch (0.16); heads ~12px on a 19px
      // pitch but small relative to a multi-cell path (0.55 long,
      // 0.56 wide).
      expect(PathSegmentPainter.strokeWidthFor(19), closeTo(3.0, 0.1));
      expect(PathSegmentPainter.headLengthFor(19), closeTo(10.45, 0.2));
      expect(
        PathSegmentPainter.headHalfWidthFor(19) * 2,
        closeTo(10.64, 0.2),
      );
    });

    test('power grid colour is the faint #D9DEEF from the recording',
        () {
      expect(powerGridColor, const Color(0xFFD9DEEF));
    });

    test('exit trail is set on a NORMAL exit, not just Power', () {
      final game = ArrowPuzzleGame(
        ArrowBoard(
          cols: 3,
          rows: 3,
          paths: [
            const ArrowPath([0], Direction.right),
            const ArrowPath([1], Direction.right),
          ],
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
          cols: 3,
          rows: 3,
          paths: [
            const ArrowPath([0], Direction.right),
            const ArrowPath([1], Direction.right),
          ],
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
              child: PowerGridOverlay(cols: 26, rows: 50),
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
      // And the fresh Level 51 board shows (the recording's 152
      // paths as the moves counter).
      expect(find.text('Level 51'), findsOneWidget);
    });
  });

  group('exit animation (pull-out)', () {
    test('path polyline ends on the exit edge, in board coordinates',
        () {
      final pts = pathPolylinePoints(
        pathCells: [5, 6], // row 1, cols 1-2 on a 4-col board
        headDirection: Direction.right,
        cols: 4,
      );
      // Last point on the exit (right) edge of cell (1,2): x == 3.
      expect(pts.last.x, closeTo(3.0, 1e-9));
      expect(pts.last.y, closeTo(1.5, 1e-9));
      // The head centre is the second-to-last point.
      expect(pts[pts.length - 2].x, closeTo(2.5, 1e-9));
      expect(pts[pts.length - 2].y, closeTo(1.5, 1e-9));
    });

    test('pullPolyline: no travel leaves the polyline unchanged', () {
      const pts = [
        Point(0.0, 0.0),
        Point(1.0, 0.0),
        Point(1.0, 1.0),
      ];
      final pulled = pullPolyline(
        points: pts,
        direction: Direction.down,
        headTravel: 0,
      );
      expect(pulled, pts);
    });

    test('pullPolyline: the head moves along the exit ray and the '
        'rope slides forward along its own path (no stretch)', () {
      // L-shaped polyline, head at (1,1), pulled down. A point at
      // arc-distance d from the head lands on the ray at
      // head + dir * (travel - d) once travel >= d; a point still
      // beyond the pulled length slides FORWARD along the rope by
      // travel (the tail follows the path the head took).
      const pts = [
        Point(0.0, 0.0),
        Point(1.0, 0.0),
        Point(1.0, 1.0),
      ];
      // Travel 0.5: head at (1,1.5); the middle point (distance 1)
      // slides to (1,0.5) — halfway along the head's old segment;
      // the tail (distance 2) slides to (0.5,0).
      var pulled = pullPolyline(
        points: pts,
        direction: Direction.down,
        headTravel: 0.5,
      );
      expect(pulled.last.x, closeTo(1.0, 1e-9));
      expect(pulled.last.y, closeTo(1.5, 1e-9));
      expect(pulled[1].x, closeTo(1.0, 1e-9));
      expect(pulled[1].y, closeTo(0.5, 1e-9));
      expect(pulled[0].x, closeTo(0.5, 1e-9));
      expect(pulled[0].y, closeTo(0.0, 1e-9));
      // Travel 1.5: the middle point (distance 1) is now on the ray,
      // 0.5 behind the head's start; the tail slides to (1,0.5).
      pulled = pullPolyline(
        points: pts,
        direction: Direction.down,
        headTravel: 1.5,
      );
      expect(pulled.last.y, closeTo(2.5, 1e-9));
      expect(pulled[1].x, closeTo(1.0, 1e-9));
      expect(pulled[1].y, closeTo(1.5, 1e-9));
      expect(pulled[0].x, closeTo(1.0, 1e-9));
      expect(pulled[0].y, closeTo(0.5, 1e-9));
      // Travel 2.5: the whole polyline is on the ray — a straight
      // vertical line from (1,1.5) to (1,3.5).
      pulled = pullPolyline(
        points: pts,
        direction: Direction.down,
        headTravel: 2.5,
      );
      expect(pulled.last.y, closeTo(3.5, 1e-9));
      expect(pulled[1].x, closeTo(1.0, 1e-9));
      expect(pulled[1].y, closeTo(2.5, 1e-9));
      expect(pulled[0].x, closeTo(1.0, 1e-9));
      expect(pulled[0].y, closeTo(1.5, 1e-9));
    });

    test('pullPolyline never stretches the rope (no long diagonal)', () {
      // A winding path: pulling it must not stretch any segment —
      // the joining segment between the pulled and sliding parts
      // stays short (the old snap version stretched it into a long
      // diagonal on winding paths). The discrete slide compresses
      // the rope slightly where the shift crosses a corner (the
      // chord cuts the corner), so the total may shrink a little —
      // but it never grows, and no single segment ever stretches.
      final pts = pathPolylinePoints(
        pathCells: [0, 1, 5, 6, 10],
        headDirection: Direction.down,
        cols: 4,
      );
      double arcLen(List<Point<double>> p) {
        var total = 0.0;
        for (var i = 1; i < p.length; i++) {
          final dx = p[i].x - p[i - 1].x;
          final dy = p[i].y - p[i - 1].y;
          total += sqrt(dx * dx + dy * dy);
        }
        return total;
      }

      final before = arcLen(pts);
      for (final travel in [0.5, 1.5, 2.5, 3.5, 4.5, 5.5]) {
        final pulled = pullPolyline(
          points: pts,
          direction: Direction.down,
          headTravel: travel,
        );
        // The rope never stretches overall.
        expect(arcLen(pulled), lessThanOrEqualTo(before + 1e-9));
        // No single segment stretches beyond its original length
        // (segments are 1.0 or 0.5 in the original).
        for (var i = 1; i < pulled.length; i++) {
          final dx = pulled[i].x - pulled[i - 1].x;
          final dy = pulled[i].y - pulled[i - 1].y;
          expect(sqrt(dx * dx + dy * dy), lessThanOrEqualTo(1.0 + 1e-9));
        }
      }
    });

    test('tap result carries the exited path and direction', () {
      final game = ArrowPuzzleGame(
        ArrowBoard(
          cols: 3,
          rows: 3,
          paths: [
            const ArrowPath([0], Direction.right),
            const ArrowPath([1], Direction.right),
          ],
        ),
      );
      final first = game.tap(1);
      expect(first.kind, TapKind.cleared);
      expect(first.exitedPathCells, [1]);
      expect(first.exitedDirection, Direction.right);
      final second = game.tap(0);
      expect(second.kind, TapKind.cleared);
      expect(second.exitedPathCells, [0]);
    });
  });

  group('hint', () {
    test('hint always points at a currently clear path', () {
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
        ArrowBoard(cols: 2, rows: 2, paths: []),
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
