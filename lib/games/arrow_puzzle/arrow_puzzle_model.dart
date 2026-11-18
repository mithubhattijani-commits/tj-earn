/// Arrow Puzzle — pure game model (no Flutter imports).
///
/// Board: an N x N grid. Each cell holds an arrow (with a fixed
/// direction), a stone (blocker, never moves), or nothing. Tapping an
/// arrow slides it out along its facing direction if the straight line
/// to the board edge is clear; a blocked tap costs one heart.
///
/// LOOK (navy rebuild v1.0.29, from the user's Level 51 screen
/// recording): the board renders as a DENSE MAZE of thin NAVY
/// (#14122E) arrow paths on a white background — one colour for every
/// arrow, no palette. Each arrow is drawn as a winding polyline
/// (see [mazePathPoints]) that starts on one cell edge, turns once or
/// twice at right angles, and ends with an arrowhead on the exit
/// edge. Adjacent lines meet at shared edges, so the board reads as
/// interlocking tangled paths, not tiles. The maze is purely visual:
/// the rules above still run on the grid. Level 1 is simpler/sparser
/// than Level 51 but the SAME style; density grows with level.
///
/// Solvability by construction: pick the level's arrow cells, order
/// them by "onion layer" (distance to the nearest edge, border
/// first, random order within a layer), then give each cell a
/// direction whose exit ray holds no stone and no arrow that is
/// still on the board when this arrow is removed — i.e. every arrow
/// on its ray comes earlier in the order. Such a direction always
/// exists for border cells (facing out has an empty ray) and almost
/// always for interior cells (facing the nearest edge runs through
/// earlier layers only); a cell with no fitting direction is left
/// empty — dropping a cell can only open rays, so the kept arrows
/// stay solvable. Removing arrows can only open paths, so that
/// removal order stays valid for the board and a solvable move always
/// exists until the board is empty. (The pre-v1.0.29 generator placed
/// arrows in random order and stalled at ~53% fill on a 15x15 board
/// — too sparse for the 152-arrow Level 51 reference; a full-board
/// peel deadlocks for the same reason, so the order is built first
/// and the directions are chosen to fit it.)
library;

import 'dart:math';

/// The four directions an arrow can face.
enum Direction { up, down, left, right }

extension DirectionDelta on Direction {
  int get dRow => switch (this) {
        Direction.up => -1,
        Direction.down => 1,
        _ => 0,
      };
  int get dCol => switch (this) {
        Direction.left => -1,
        Direction.right => 1,
        _ => 0,
      };
}

/// One arrow on the board. [colorIndex] is 0..5, retained for
/// stability/determinism only — since the v1.0.29 navy rebuild the
/// renderer draws every arrow in the same navy
/// ([MazeArrowPainter.arrowColor]) and ignores this field for colour.
class ArrowCell {
  const ArrowCell(this.direction, this.colorIndex);

  final Direction direction;
  final int colorIndex;

  @override
  bool operator ==(Object other) =>
      other is ArrowCell &&
      other.direction == direction &&
      other.colorIndex == colorIndex;

  @override
  int get hashCode => Object.hash(direction, colorIndex);
}

/// A generated level: board size, arrow cells and stone cells.
///
/// Cells are stored flat, row-major: index = row * size + col.
/// [arrows] maps a cell index to its arrow (null = no arrow).
/// [stones] holds the indices of stone cells.
class ArrowBoard {
  ArrowBoard({
    required this.size,
    required this.arrows,
    required this.stones,
  });

  final int size;
  final Map<int, ArrowCell> arrows;
  final Set<int> stones;

  int get arrowCount => arrows.length;

  int index(int row, int col) => row * size + col;

  bool inBounds(int row, int col) =>
      row >= 0 && row < size && col >= 0 && col < size;

  /// Cells on the straight exit ray of the arrow at [cellIndex],
  /// excluding the arrow's own cell, in exit order.
  List<int> exitRay(int cellIndex) {
    final arrow = arrows[cellIndex];
    if (arrow == null) return const [];
    final row = cellIndex ~/ size;
    final col = cellIndex % size;
    final out = <int>[];
    var r = row + arrow.direction.dRow;
    var c = col + arrow.direction.dCol;
    while (inBounds(r, c)) {
      out.add(index(r, c));
      r += arrow.direction.dRow;
      c += arrow.direction.dCol;
    }
    return out;
  }

  /// True when the arrow at [cellIndex] can slide out right now:
  /// every cell on its exit ray is empty (no arrow, no stone).
  bool isClear(int cellIndex) {
    if (!arrows.containsKey(cellIndex)) return false;
    for (final i in exitRay(cellIndex)) {
      if (arrows.containsKey(i) || stones.contains(i)) return false;
    }
    return true;
  }

  /// First arrow (row-major order) that can exit right now, or null
  /// when the board is empty. Never null on a non-empty generated
  /// board (see the construction guarantee in the file doc).
  int? findHint() {
    final keys = arrows.keys.toList()..sort();
    for (final i in keys) {
      if (isClear(i)) return i;
    }
    return null;
  }

  /// A mutable working copy (the game mutates this during play).
  ArrowBoard copy() => ArrowBoard(
        size: size,
        arrows: Map<int, ArrowCell>.of(arrows),
        stones: Set<int>.of(stones),
      );
}

/// Board size for a level (maze redesign 18 Nov 2026, navy rebuild
/// v1.0.29): the board is dense from level 1 — 8x8 at L1, growing to
/// 17x17 — so it reads as a tangled maze like the user's Level 51
/// reference (152 arrows), not a sparse tile grid. Level 51 is
/// 15x15 = 225 cells, so ~152 arrows fit at ~68% fill. Level 1 is
/// still simpler: fewer cells and a lower fill than the late levels.
int sizeForLevel(int level) {
  if (level <= 5) return 8;
  if (level <= 15) return 9;
  if (level <= 30) return 10;
  if (level <= 40) return 11;
  if (level <= 50) return 12;
  if (level <= 60) return 15;
  if (level <= 75) return 16;
  return 17;
}

/// Stone blockers for a level (none before L21).
int stonesForLevel(int level) {
  if (level < 21) return 0;
  if (level <= 35) return 1 + (level % 2);
  if (level <= 60) return 2 + (level % 3);
  return 3 + (level % 3);
}

/// Difficulty label for a level.
String difficultyForLevel(int level) {
  if (level <= 30) return 'Normal';
  if (level <= 60) return 'Hard';
  return 'Expert';
}

/// Maze-path geometry for one arrow cell, in unit-cell coordinates
/// (0..1 on both axes). The path is a thin winding polyline: it
/// starts on one edge of the cell, turns once or twice at right
/// angles, and ends on the exit edge — the edge the arrow faces —
/// where the renderer draws the arrowhead. Neighbouring cells' lines
/// meet at shared edges, so the board reads as interlocking tangled
/// paths (the user's Level 51 reference), not tiles.
///
/// Deterministic per (cell, direction, board size): the same level
/// always draws the same maze. Pure Dart (dart:math [Point]s only)
/// so tests can verify the winding: every point lies inside the unit
/// square, consecutive segments are axis-aligned, the first point is
/// on a non-exit edge and the last point is on the exit edge.
List<Point<double>> mazePathPoints({
  required int cellIndex,
  required Direction direction,
  required int boardSize,
}) {
  final rng = Random(
    cellIndex * 2654435761 ^ direction.index * 97 ^ boardSize * 13,
  );
  double pick(double lo, double hi) =>
      lo + rng.nextDouble() * (hi - lo);

  // Build in "exit-right" space, then rotate into the real direction.
  // Exit point on the right edge.
  final yE = pick(0.35, 0.65);
  // Entry edge: 0 = left (opposite the exit), 1 = top, 2 = bottom.
  // Weighted towards the opposite edge so lines run on through the
  // cell and join their neighbours into long winding paths.
  final roll = rng.nextDouble();
  final entry = roll < 0.4 ? 0 : (roll < 0.7 ? 1 : 2);
  final twoTurns = rng.nextBool();
  final pts = <Point<double>>[];
  if (entry == 0) {
    final yS = pick(0.15, 0.85);
    final x1 = pick(0.30, 0.70);
    if ((yS - yE).abs() < 0.06) {
      // Nearly straight through: run flat at the exit height.
      pts.add(Point(0.0, yE));
      pts.add(Point(1.0, yE));
    } else if (!twoTurns) {
      pts.add(Point(0.0, yS));
      pts.add(Point(x1, yS));
      pts.add(Point(x1, yE));
      pts.add(Point(1.0, yE));
    } else {
      final yM = pick(0.20, 0.80);
      final x2 = pick(0.30, 0.70);
      pts.add(Point(0.0, yS));
      pts.add(Point(x1, yS));
      pts.add(Point(x1, yM));
      pts.add(Point(x2, yM));
      pts.add(Point(x2, yE));
      pts.add(Point(1.0, yE));
    }
  } else if (entry == 1) {
    final xS = pick(0.15, 0.85);
    pts.add(Point(xS, 0.0));
    if (!twoTurns) {
      pts.add(Point(xS, yE));
      pts.add(Point(1.0, yE));
    } else {
      final y1 = pick(0.25, 0.60);
      final x1 = pick(0.30, 0.75);
      pts.add(Point(xS, y1));
      pts.add(Point(x1, y1));
      pts.add(Point(x1, yE));
      pts.add(Point(1.0, yE));
    }
  } else {
    final xS = pick(0.15, 0.85);
    pts.add(Point(xS, 1.0));
    if (!twoTurns) {
      pts.add(Point(xS, yE));
      pts.add(Point(1.0, yE));
    } else {
      final y1 = pick(0.40, 0.75);
      final x1 = pick(0.30, 0.75);
      pts.add(Point(xS, y1));
      pts.add(Point(x1, y1));
      pts.add(Point(x1, yE));
      pts.add(Point(1.0, yE));
    }
  }
  // Drop any zero-length segment (two equal consecutive points).
  final deduped = <Point<double>>[pts.first];
  for (var i = 1; i < pts.length; i++) {
    final p = pts[i];
    final prev = deduped.last;
    if ((p.x - prev.x).abs() > 1e-9 || (p.y - prev.y).abs() > 1e-9) {
      deduped.add(p);
    }
  }
  return deduped
      .map((p) => _rotateMazePoint(p, direction))
      .toList(growable: false);
}

/// Rotates a unit-square point from "exit-right" space into the
/// space of [direction], around the cell centre (0.5, 0.5).
Point<double> _rotateMazePoint(Point<double> p, Direction direction) {
  final cx = p.x - 0.5;
  final cy = p.y - 0.5;
  return switch (direction) {
    Direction.right => p,
    Direction.down => Point(0.5 - cy, 0.5 + cx),
    Direction.left => Point(0.5 - cx, 0.5 - cy),
    Direction.up => Point(0.5 + cy, 0.5 - cx),
  };
}

/// Deterministic level generation. Same [level] (and [seedOverride])
/// always produces the same board.
ArrowBoard generateLevel(int level, {int? seedOverride}) {
  final seed = seedOverride ?? level;
  var rng = Random(seed);
  for (var attempt = 0; attempt < 25; attempt++) {
    final board = _tryGenerate(level, rng);
    if (board != null) return board;
    rng = Random(seed + attempt + 1);
  }
  // Extremely unlikely fallback: a sparse, trivially solvable board.
  return _fallbackBoard(level);
}

/// Maze density: fraction of free cells holding arrows. ~0.60 at L1,
/// rising to ~0.69-0.72 by L200, so the board reads as a dense tangle
/// of arrows at every level and Level 51 lands at ~0.68 of its 223
/// free cells — about 152 arrows, matching the user's reference.
double _densityForLevel(int level, Random rng) =>
    0.60 + rng.nextDouble() * 0.03 + (level * 0.0015).clamp(0, 0.09);

ArrowBoard? _tryGenerate(int level, Random rng) {
  final size = sizeForLevel(level);
  final total = size * size;
  final stones = <int>{};
  final stoneCount = stonesForLevel(level);

  // Stones never sit on the border ring: an edge stone would seal a
  // whole row/column and shrink the playable board.
  var placedStones = 0;
  var guard = 0;
  while (placedStones < stoneCount && guard < 200) {
    guard++;
    final r = 1 + rng.nextInt(size - 2);
    final c = 1 + rng.nextInt(size - 2);
    if (stones.add(r * size + c)) placedStones++;
  }

  final free = total - stones.length;
  final target = (free * _densityForLevel(level, rng)).round();
  if (target < 4) return null;

  // Choose the arrow cells: a random subset of the free cells.
  final freeCells = <int>[];
  for (var i = 0; i < total; i++) {
    if (!stones.contains(i)) freeCells.add(i);
  }
  freeCells.shuffle(rng);
  final targetCells = freeCells.take(target).toSet();

  // Removal order: onion layers, border first, random order within
  // each layer. (Grouped explicitly so the order never depends on
  // sort stability.)
  int layerOf(int idx) {
    final r = idx ~/ size;
    final c = idx % size;
    return [r, c, size - 1 - r, size - 1 - c]
        .reduce((a, b) => a < b ? a : b);
  }

  final byLayer = <int, List<int>>{};
  for (final idx in targetCells) {
    (byLayer[layerOf(idx)] ??= <int>[]).add(idx);
  }
  final ordered = <int>[];
  for (var layer = 0; layer <= size ~/ 2; layer++) {
    final cells = byLayer[layer];
    if (cells == null) continue;
    cells.shuffle(rng);
    ordered.addAll(cells);
  }

  // Give each cell, in removal order, a direction whose exit ray
  // holds no stone and no arrow that is still on the board when
  // this arrow is removed (i.e. every arrow on the ray was assigned
  // earlier in the order and is gone by then).
  final arrows = <int, ArrowCell>{};
  final assigned = <int>{};
  for (final idx in ordered) {
    final row = idx ~/ size;
    final col = idx % size;
    final dirs = List<Direction>.of(Direction.values)..shuffle(rng);
    Direction? chosen;
    for (final dir in dirs) {
      var r = row + dir.dRow;
      var c = col + dir.dCol;
      var ok = true;
      while (r >= 0 && r < size && c >= 0 && c < size) {
        final j = r * size + c;
        if (stones.contains(j)) {
          ok = false;
          break;
        }
        if (targetCells.contains(j) && !assigned.contains(j)) {
          ok = false;
          break;
        }
        r += dir.dRow;
        c += dir.dCol;
      }
      if (ok) {
        chosen = dir;
        break;
      }
    }
    // No direction fits (a stone sits on every ray, or every ray
    // crosses an arrow that is still on the board at this point):
    // leave this cell empty instead of failing the whole attempt —
    // dropping a cell can only open rays, so the kept arrows stay
    // solvable. The level ends up a few arrows under target, which
    // the density formula's headroom absorbs.
    if (chosen == null) continue;
    arrows[idx] = ArrowCell(chosen, (idx % 6 + chosen.index) % 6);
    assigned.add(idx);
  }
  return ArrowBoard(size: size, arrows: arrows, stones: stones);
}

ArrowBoard _fallbackBoard(int level) {
  final size = sizeForLevel(level);
  final arrows = <int, ArrowCell>{
    0: const ArrowCell(Direction.right, 0),
    size: const ArrowCell(Direction.down, 1),
  };
  return ArrowBoard(size: size, arrows: arrows, stones: <int>{});
}

/// Daily Challenge level: same board for every user on a given date.
/// Seed is YYYYMMDD; the size band cycles 5x5-7x7 by day of year.
ArrowBoard generateDailyLevel(DateTime date) {
  final seed = date.year * 10000 + date.month * 100 + date.day;
  final dayOfYear =
      date.difference(DateTime(date.year, 1, 1)).inDays + 1;
  final pseudoLevel = 11 + (dayOfYear % 50); // 9x9..12x12 band
  return generateLevel(pseudoLevel, seedOverride: seed);
}

/// Result of one tap on the board.
class TapResult {
  const TapResult({
    required this.kind,
    this.revealedPath = const [],
  });

  final TapKind kind;

  /// When an arrow exits — by a normal tap ([TapKind.cleared]) or a
  /// Power tap ([TapKind.powerCleared]) — the exit ray it travelled,
  /// in exit order. The UI highlights it in light blue, fading over
  /// ~700ms. Empty for blocked/invalid taps.
  final List<int> revealedPath;
}

enum TapKind {
  /// Arrow exited; the board changed.
  cleared,

  /// Arrow was blocked; one heart lost.
  blocked,

  /// Arrow exited via Power (blocking ignored, no heart lost).
  powerCleared,

  /// Tapped cell holds no arrow (empty or stone): no move, no heart.
  invalid,
}

/// Mutable play state for one level attempt. Pure logic — the UI only
/// renders this and forwards taps.
class ArrowPuzzleGame {
  ArrowPuzzleGame(ArrowBoard board, {this.hearts = 3})
      : _board = board.copy(),
        totalArrows = board.arrowCount;

  final ArrowBoard _board;
  final int totalArrows;

  int hearts;
  int moves = 0;
  bool powerArmed = false;
  DateTime? startedAt;

  int get size => _board.size;
  Map<int, ArrowCell> get arrows => _board.arrows;
  Set<int> get stones => _board.stones;
  int get arrowsLeft => _board.arrows.length;
  bool get isWon => _board.arrows.isEmpty;
  bool get isGameOver => hearts <= 0;

  bool isClear(int cellIndex) => _board.isClear(cellIndex);

  int? findHint() => _board.findHint();

  List<int> exitRay(int cellIndex) => _board.exitRay(cellIndex);

  /// Stars for a finished level: 1 for completing, +1 for no hearts
  /// lost, +1 for finishing in par moves (par == arrow count).
  int starsForWin({required int heartsLost}) {
    var stars = 1;
    if (heartsLost == 0) stars++;
    if (heartsLost == 0 && moves <= totalArrows) stars++;
    return stars;
  }

  TapResult tap(int cellIndex) {
    startedAt ??= DateTime.now();
    if (!_board.arrows.containsKey(cellIndex)) {
      return const TapResult(kind: TapKind.invalid);
    }
    moves++;
    if (powerArmed) {
      powerArmed = false;
      final path = _board.exitRay(cellIndex);
      _board.arrows.remove(cellIndex);
      return TapResult(kind: TapKind.powerCleared, revealedPath: path);
    }
    if (_board.isClear(cellIndex)) {
      final path = _board.exitRay(cellIndex);
      _board.arrows.remove(cellIndex);
      return TapResult(kind: TapKind.cleared, revealedPath: path);
    }
    hearts--;
    return const TapResult(kind: TapKind.blocked);
  }
}
