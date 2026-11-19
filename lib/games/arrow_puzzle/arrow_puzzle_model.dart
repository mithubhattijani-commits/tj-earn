/// Arrow Puzzle — pure game model (no Flutter imports).
///
/// PATH MODEL (v6, from the user's Level 51 screen recording).
///
/// The board is a set of vertex-disjoint POLYLINES on a fine
/// lattice — one arrow = one long winding path, not one arrow per
/// cell. Each path is a thin navy shaft with a SMALL triangular head
/// at one end. The board is a TALL RECTANGLE (Level 51 is 26 cols x
/// 50 rows, pitch ~19px on the 576px-wide recording frame, aspect
/// ~0.52). The recording's board is dense: ~152 paths, ~55% of
/// cells covered, path lengths median ~3.8 cells, mean ~4.6 (measured
/// frame-by-frame from the recording's t16 board by skeletonising
/// the navy mask; see the v6 work notes). Empty cells show a faint
/// grey dot (#DDDEE5). There are no stone blockers in the recording.
///
/// THE RULE — heads only block. A path can exit iff no OTHER
/// remaining path's HEAD cell lies on its head-ray (the straight
/// line from its head to the board edge, in its head direction).
/// Shafts NEVER block: the recording's exit frames (t32.2-t33.4)
/// show the tapped path turning bright blue and pulling out like a
/// rope along its ray, passing OVER the other navy shafts — so a
/// path's body cannot be what stops it. The earlier full-ray rule
/// (the whole ray must be empty of arrows) is REFUTED by the
/// recording: on the recording's own board only ~8 of 153 paths had
/// a clear full ray, yet the user removes 15+ paths in 45 seconds
/// with no heart lost, and a dense board of long paths cannot be
/// fully solvable under the full-ray rule at all (Hamiltonian-cut
/// prototypes deadlocked after 14-46 of 152 removals, and the
/// recording's own board deadlocks after ~14). Heads-only is the
/// rule the recording actually shows, and it is what makes the
/// board playable.
///
/// GENERATION — grow-from-head, in removal order. Paths are placed
/// one at a time, in the order they will be removed. Each new path
/// picks a head cell UNIFORMLY at random from the empty cells that
/// lie on no earlier path's ray (a shortest-ray preference for the
/// head cell concentrates heads near the edges and leaves a hollow
/// middle — the board must be uniformly dense like the recording),
/// takes the SHORTEST-ray direction as its head direction, and grows
/// its body as a randomised walk through empty cells, with length
/// sampled from the recording's measured length distribution. The
/// head's ray is then forbidden for later paths' heads. Because every
/// later path's head avoids every earlier path's ray, the placement
/// order IS a valid removal order: the earliest-placed remaining path
/// is always clear, so greedy play always has a move and empties the
/// board. Validated in a Python prototype over many seeds and board
/// sizes (5/5 fully solvable at L1, mid, L51 and high sizes).
///
/// L51 USES GENERATED PATHS, not the recording's own layout.
/// Reconstructing the recording's own L51 paths was attempted and
/// is NOT reliably feasible: the t16 skeleton is fragmented (71/153
/// components have spurs/junctions, heads identified for only
/// 114/153 routes), the lattice fit is weak (x inliers only 70% at
/// ~19.5px pitch), t16 is already mid-game (moves 150, not 152, plus
/// one path mid-exit), and the t8 frame is a DIFFERENT board
/// instance (mask overlap with t16 only ~27% in the shared band).
/// So L51 is generated to the recording's measured statistics
/// (152 paths, 26x50, ~55% coverage, median length ~4) rather than
/// traced arrow-for-arrow.
///
/// LOOK (from the recording): every path is the single navy
/// #14122E; shafts are ~0.16 of the pitch thick; heads are small
/// triangles (~0.55 of the pitch long — the recording's heads are
/// ~12px on a 19px pitch, i.e. ~0.63, but they read as small because
/// each path is several cells long, not one); the exiting path turns
/// bright blue #3584E2 and pulls out like a rope; while Power is
/// armed a faint light-blue grid (#D9DEEF) overlays the board,
/// spanning the full screen width.
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

/// One arrow = one polyline path on the board.
///
/// [cells] are row-major cell indices, stored HEAD-LAST: [cells.last]
/// is the head cell, [cells.first] is the tail. Consecutive cells
/// are orthogonally adjacent (the path turns at right angles at cell
/// centres). [headDirection] is the direction the head points —
/// outward, away from the body — and the direction the path exits
/// along when tapped.
class ArrowPath {
  const ArrowPath(this.cells, this.headDirection);

  final List<int> cells;
  final Direction headDirection;

  int get headCell => cells.last;
  int get tailCell => cells.first;
  int get length => cells.length;

  @override
  bool operator ==(Object other) =>
      other is ArrowPath &&
      other.headDirection == headDirection &&
      _listEquals(other.cells, cells);

  @override
  int get hashCode => Object.hash(headDirection, Object.hashAll(cells));

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A generated level: board size and its paths.
///
/// Paths are stored in a map keyed by a stable path id (0..n-1 at
/// generation); [cellToPath] maps every occupied cell to its path
/// id. The game mutates a copy during play (see [ArrowBoard.copy]
/// and [removePath]).
class ArrowBoard {
  ArrowBoard({
    required this.cols,
    required this.rows,
    required List<ArrowPath> paths,
  })  : _paths = {
          for (var i = 0; i < paths.length; i++) i: paths[i],
        },
        cellToPath = {
          for (var i = 0; i < paths.length; i++)
            for (final cell in paths[i].cells) cell: i,
        };

  ArrowBoard._(this.cols, this.rows, this._paths, this.cellToPath);

  /// Board width in cells.
  final int cols;

  /// Board height in cells. The board is a tall rectangle
  /// (rows ~ cols / 0.52) matching the user's recording.
  final int rows;

  final Map<int, ArrowPath> _paths;

  /// Cell index -> path id, for every cell a path occupies.
  final Map<int, int> cellToPath;

  /// Paths remaining — the moves counter (one move per path).
  int get pathCount => _paths.length;

  /// Backwards-compatible alias: the number of arrows left.
  int get arrowCount => _paths.length;

  /// All remaining paths, in id order.
  List<ArrowPath> get paths {
    final ids = _paths.keys.toList()..sort();
    return [for (final id in ids) _paths[id]!];
  }

  int index(int row, int col) => row * cols + col;

  bool inBounds(int row, int col) =>
      row >= 0 && row < rows && col >= 0 && col < cols;

  /// The path id occupying [cellIndex], or null for an empty cell.
  int? pathIdForCell(int cellIndex) => cellToPath[cellIndex];

  ArrowPath? pathById(int pathId) => _paths[pathId];

  /// Cells on the straight exit ray of the path [pathId], excluding
  /// the head cell itself, in exit order (head -> board edge).
  List<int> exitRay(int pathId) {
    final path = _paths[pathId];
    if (path == null) return const [];
    final headRow = path.headCell ~/ cols;
    final headCol = path.headCell % cols;
    final out = <int>[];
    var r = headRow + path.headDirection.dRow;
    var c = headCol + path.headDirection.dCol;
    while (inBounds(r, c)) {
      out.add(index(r, c));
      r += path.headDirection.dRow;
      c += path.headDirection.dCol;
    }
    return out;
  }

  /// True when the path [pathId] can slide out right now: no OTHER
  /// remaining path's HEAD cell lies on its exit ray. Shafts never
  /// block (see the file doc — the recording's rope passes over
  /// them). A path's own head is the ray's start, never a blocker.
  bool isClear(int pathId) {
    final path = _paths[pathId];
    if (path == null) return false;
    for (final cell in exitRay(pathId)) {
      final owner = cellToPath[cell];
      if (owner != null && owner != pathId) {
        final other = _paths[owner]!;
        if (other.headCell == cell) return false;
      }
    }
    return true;
  }

  /// Head cell of the first clear path (in id order), or null when
  /// the board is empty. Never null on a non-empty generated board
  /// (see the construction guarantee in the file doc).
  int? findHint() {
    final ids = _paths.keys.toList()..sort();
    for (final id in ids) {
      if (isClear(id)) return _paths[id]!.headCell;
    }
    return null;
  }

  /// Removes a whole path (and all its cells) from the board.
  void removePath(int pathId) {
    final path = _paths.remove(pathId);
    if (path == null) return;
    for (final cell in path.cells) {
      cellToPath.remove(cell);
    }
  }

  /// A mutable working copy (the game mutates this during play).
  ArrowBoard copy() => ArrowBoard._(
        cols,
        rows,
        {
          for (final e in _paths.entries)
            e.key: ArrowPath(
              List<int>.of(e.value.cells),
              e.value.headDirection,
            ),
        },
        Map<int, int>.of(cellToPath),
      );
}

/// Board width in cells for a level (tall-rectangle path model, from
/// the user's Level 51 recording: 26 cols x 50 rows, aspect ~0.52).
/// The board grows with the level so early levels are smaller and
/// quicker and Level 51 lands exactly on the recording's lattice.
int colsForLevel(int level) {
  if (level <= 5) return 10;
  if (level <= 15) return 12;
  if (level <= 30) return 14;
  if (level <= 40) return 17;
  if (level <= 50) return 21;
  if (level <= 60) return 26;
  if (level <= 75) return 28;
  return 30;
}

/// Board height in cells for a level: rows ~ cols / 0.52, so the
/// board keeps the recording's tall aspect (~0.52) at every level.
/// Level 51 is 26x50.
int rowsForLevel(int level) => (colsForLevel(level) / 0.52).round();

/// Number of paths (arrows, i.e. moves) for a level: the recording's
/// board covers ~55% of its 26x50 cells with paths of mean length
/// ~4.7 cells, which is 152 paths at Level 51. The same ratio at
/// every level keeps the density and the look constant.
int targetPathsForLevel(int level) {
  final cols = colsForLevel(level);
  final rows = rowsForLevel(level);
  return (cols * rows * 0.55 / 4.7).round().clamp(8, 100000);
}

/// Difficulty label for a level.
String difficultyForLevel(int level) {
  if (level <= 30) return 'Normal';
  if (level <= 60) return 'Hard';
  return 'Expert';
}

/// Path length sampler: the recording's measured length distribution
/// (skeleton lengths of the t16 board, in cells) — 1-2: 55, 3-5: 46,
/// 6-7: 28, 8-10: 15, 11-13: 5, 14-15: 2, 16-20: 2 (153 paths).
int _samplePathLength(Random rng) {
  const bins = <(int, int, int)>[
    (1, 2, 55),
    (3, 5, 46),
    (6, 7, 28),
    (8, 10, 15),
    (11, 13, 5),
    (14, 15, 2),
    (16, 20, 2),
  ];
  var total = 0;
  for (final b in bins) {
    total += b.$3;
  }
  var x = rng.nextInt(total);
  for (final (lo, hi, w) in bins) {
    if (x < w) return lo + rng.nextInt(hi - lo + 1);
    x -= w;
  }
  return 4;
}

/// Length of the straight ray from [headCell] in [dir] to the board
/// edge, in cells (excluding the head cell itself).
int _rayLength(int headCell, Direction dir, int cols, int rows) {
  var r = headCell ~/ cols + dir.dRow;
  var c = headCell % cols + dir.dCol;
  var n = 0;
  while (r >= 0 && r < rows && c >= 0 && c < cols) {
    n++;
    r += dir.dRow;
    c += dir.dCol;
  }
  return n;
}

/// A randomised walk of [length] cells starting at [start],
/// avoiding [blocked] cells and never revisiting a cell. Restarts
/// the walk (up to 30 times) when it runs into a dead end. Returns
/// null when no walk of that length could be found. A length of 0
/// returns an empty walk (a 1-cell path: head only, no body).
List<int>? _greedyWalk(
  int start,
  int length,
  Set<int> blocked,
  int cols,
  int rows,
  Random rng,
) {
  if (length <= 0) return <int>[];
  for (var restart = 0; restart < 30; restart++) {
    final path = <int>[start];
    final used = <int>{start};
    var ok = true;
    while (path.length < length) {
      final cur = path.last;
      final r = cur ~/ cols;
      final c = cur % cols;
      final neighbours = <int>[];
      for (final d in Direction.values) {
        final nr = r + d.dRow;
        final nc = c + d.dCol;
        if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) continue;
        final j = nr * cols + nc;
        if (!blocked.contains(j) && !used.contains(j)) {
          neighbours.add(j);
        }
      }
      if (neighbours.isEmpty) {
        ok = false;
        break;
      }
      neighbours.shuffle(rng);
      final next = neighbours.first;
      used.add(next);
      path.add(next);
    }
    if (ok) return path;
  }
  return null;
}

/// Grows one board by the grow-from-head construction (see the file
/// doc): paths are placed in removal order, each head on a uniformly
/// chosen empty cell that is on no earlier path's ray, with the
/// shortest-ray direction as its head direction. Returns null when
/// placement gets stuck before reaching [target] paths (the caller
/// retries with a new seed).
List<ArrowPath>? _tryGrowBoard(
  int cols,
  int rows,
  int target,
  Random rng,
) {
  final total = cols * rows;
  final occupied = <int>{};
  final forbiddenHead = <int>{};
  final paths = <ArrowPath>[];
  for (var pi = 0; pi < target; pi++) {
    final length = _samplePathLength(rng);
    var placed = false;
    for (var attempt = 0; attempt < 80 && !placed; attempt++) {
      // Sample a few empty, non-forbidden cells and pick one UNIFORMLY
      // at random as the head. (Picking the shortest-ray cell instead
      // concentrates heads near the edges and leaves a hollow middle
      // — the board must be uniformly dense like the recording.)
      // The head DIRECTION is still the shortest ray, which keeps
      // the forbidden set small.
      final candidates = <(int, Direction)>[];
      for (var s = 0; s < 8; s++) {
        final cell = rng.nextInt(total);
        if (occupied.contains(cell) || forbiddenHead.contains(cell)) {
          continue;
        }
        Direction? bestDir;
        var bestRay = 1 << 30;
        for (final d in Direction.values) {
          final rl = _rayLength(cell, d, cols, rows);
          if (rl < bestRay) {
            bestRay = rl;
            bestDir = d;
          }
        }
        if (bestDir != null) candidates.add((cell, bestDir));
      }
      if (candidates.isEmpty) continue;
      final (bestHead, bestDir) =
          candidates[rng.nextInt(candidates.length)];
      // The body starts one step opposite the head direction, so
      // the head points away from the body.
      final hr = bestHead ~/ cols;
      final hc = bestHead % cols;
      final br = hr - bestDir.dRow;
      final bc = hc - bestDir.dCol;
      if (br < 0 || br >= rows || bc < 0 || bc >= cols) continue;
      final startCell = br * cols + bc;
      if (occupied.contains(startCell)) continue;
      final body = _greedyWalk(
        startCell,
        length - 1,
        {...occupied, bestHead},
        cols,
        rows,
        rng,
      );
      if (body == null) continue;
      // Cells head-last: the walk runs head-adjacent -> tail, so
      // reverse it and append the head.
      final cells = <int>[...body.reversed, bestHead];
      paths.add(ArrowPath(cells, bestDir));
      occupied.addAll(cells);
      var r = hr + bestDir.dRow;
      var c = hc + bestDir.dCol;
      while (r >= 0 && r < rows && c >= 0 && c < cols) {
        forbiddenHead.add(r * cols + c);
        r += bestDir.dRow;
        c += bestDir.dCol;
      }
      placed = true;
    }
    if (!placed) return null;
  }
  return paths;
}

/// Deterministic level generation. Same [level] (and [seedOverride])
/// always produces the same board. Tries successive seeds until a
/// board reaches the target path count (placement is validated in
/// the Python prototype to succeed on the first seed for every
/// level band, but the retries make generation robust); falls back
/// to the best board found rather than an empty one.
ArrowBoard generateLevel(int level, {int? seedOverride}) {
  final cols = colsForLevel(level);
  final rows = rowsForLevel(level);
  final target = targetPathsForLevel(level);
  final seed = seedOverride ?? level;
  List<ArrowPath>? best;
  for (var attempt = 0; attempt < 25; attempt++) {
    final paths = _tryGrowBoard(cols, rows, target, Random(seed + attempt));
    if (paths == null) continue;
    if (best == null || paths.length > best.length) best = paths;
    if (paths.length >= target) {
      return ArrowBoard(cols: cols, rows: rows, paths: paths);
    }
  }
  if (best != null && best.length >= 8) {
    return ArrowBoard(cols: cols, rows: rows, paths: best);
  }
  // Extremely unlikely fallback: a tiny, trivially solvable board.
  return ArrowBoard(
    cols: cols,
    rows: rows,
    paths: [
      ArrowPath([0, 1], Direction.right),
      ArrowPath([cols, cols + 1], Direction.down),
    ],
  );
}

/// Daily Challenge level: same board for every user on a given date.
/// Seed is YYYYMMDD; the size band cycles by day of year.
ArrowBoard generateDailyLevel(DateTime date) {
  final seed = date.year * 10000 + date.month * 100 + date.day;
  final dayOfYear =
      date.difference(DateTime(date.year, 1, 1)).inDays + 1;
  final pseudoLevel = 11 + (dayOfYear % 50);
  return generateLevel(pseudoLevel, seedOverride: seed);
}

/// Result of one tap on the board.
class TapResult {
  const TapResult({
    required this.kind,
    this.revealedPath = const [],
    this.exitedPathCells = const [],
    this.exitedDirection,
  });

  final TapKind kind;

  /// When a path exits — by a normal tap ([TapKind.cleared]) or a
  /// Power tap ([TapKind.powerCleared]) — the exit ray it travelled,
  /// in exit order. The UI highlights it in light blue, fading over
  /// ~700ms. Empty for blocked/invalid taps.
  final List<int> revealedPath;

  /// The cells of the exited path (head-last, see [ArrowPath]),
  /// empty unless the tap exited a path. The UI uses it to draw the
  /// exit animation: the whole path's polyline, in bright blue,
  /// pulled out along [exitedDirection].
  final List<int> exitedPathCells;

  /// The direction the exited path faced (null unless the tap exited
  /// a path).
  final Direction? exitedDirection;
}

enum TapKind {
  /// Path exited; the board changed.
  cleared,

  /// Path was blocked (another head on its ray); one heart lost.
  blocked,

  /// Path exited via Power (blocking ignored, no heart lost).
  powerCleared,

  /// Tapped cell holds no path: no move, no heart.
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

  int get cols => _board.cols;
  int get rows => _board.rows;
  int get arrowsLeft => _board.arrowCount;
  int get pathsLeft => _board.pathCount;
  bool get isWon => _board.pathCount == 0;
  bool get isGameOver => hearts <= 0;

  int? pathIdForCell(int cellIndex) => _board.pathIdForCell(cellIndex);
  ArrowPath? pathById(int pathId) => _board.pathById(pathId);

  /// True when the path occupying [cellIndex] can exit right now
  /// (heads-only rule). False for an empty cell.
  bool isClear(int cellIndex) {
    final id = _board.pathIdForCell(cellIndex);
    return id != null && _board.isClear(id);
  }

  /// Head cell of a currently clear path, or null on an empty board.
  int? findHint() => _board.findHint();

  /// The exit ray of the path occupying [cellIndex].
  List<int> exitRay(int cellIndex) {
    final id = _board.pathIdForCell(cellIndex);
    if (id == null) return const [];
    return _board.exitRay(id);
  }

  /// Stars for a finished level: 1 for completing, +1 for no hearts
  /// lost, +1 for finishing in par moves (par == path count).
  int starsForWin({required int heartsLost}) {
    var stars = 1;
    if (heartsLost == 0) stars++;
    if (heartsLost == 0 && moves <= totalArrows) stars++;
    return stars;
  }

  TapResult tap(int cellIndex) {
    startedAt ??= DateTime.now();
    final pathId = _board.pathIdForCell(cellIndex);
    if (pathId == null) {
      return const TapResult(kind: TapKind.invalid);
    }
    final path = _board.pathById(pathId)!;
    moves++;
    if (powerArmed) {
      powerArmed = false;
      final ray = _board.exitRay(pathId);
      _board.removePath(pathId);
      return TapResult(
        kind: TapKind.powerCleared,
        revealedPath: ray,
        exitedPathCells: List<int>.of(path.cells),
        exitedDirection: path.headDirection,
      );
    }
    if (_board.isClear(pathId)) {
      final ray = _board.exitRay(pathId);
      _board.removePath(pathId);
      return TapResult(
        kind: TapKind.cleared,
        revealedPath: ray,
        exitedPathCells: List<int>.of(path.cells),
        exitedDirection: path.headDirection,
      );
    }
    hearts--;
    return const TapResult(kind: TapKind.blocked);
  }
}

/// The polyline of one PATH in BOARD-cell coordinates (x = column +
/// fraction across the cell, y = row + fraction down the cell). The
/// points run through the CELL CENTRES of the path (tail first, head
/// last), and the last point is the arrowhead tip: the head cell
/// centre + 0.5 in the head direction (on the exit edge of the head
/// cell). Pure Dart so the exit animation can be unit-tested.
List<Point<double>> pathPolylinePoints({
  required List<int> pathCells,
  required Direction headDirection,
  required int cols,
}) {
  final pts = <Point<double>>[];
  for (final cell in pathCells) {
    final row = cell ~/ cols;
    final col = cell % cols;
    pts.add(Point(col + 0.5, row + 0.5));
  }
  final head = pts.last;
  pts.add(
    Point(
      head.x + headDirection.dCol * 0.5,
      head.y + headDirection.dRow * 0.5,
    ),
  );
  return pts;
}

/// The shaft segment of a path drawn inside ONE cell, in unit-cell
/// coordinates (0..1 on both axes). The segment runs from the
/// midpoint of the entry edge (the edge shared with the previous
/// path cell), through the cell centre (0.5, 0.5), to the midpoint
/// of the exit edge (the edge shared with the next path cell). The
/// tail cell has no entry — its shaft starts at the centre (round
/// cap). The head cell's shaft ends at the centre; the renderer
/// draws the head triangle from there to the tip (centre + 0.5 in
/// the head direction). Entry/exit edge midpoints are shared with
/// the neighbouring cells, so the segments join into one continuous
/// winding path. Pure Dart so the renderer can be unit-tested.
List<Point<double>> cellSegmentPoints({
  required List<int> pathCells,
  required int cellIndex,
  required int cols,
}) {
  final pos = pathCells.indexOf(cellIndex);
  if (pos < 0) return const [];
  final row = cellIndex ~/ cols;
  final col = cellIndex % cols;

  Point<double> edgeMidpoint(int otherCell) {
    final orow = otherCell ~/ cols;
    final ocol = otherCell % cols;
    // Midpoint of the edge shared with [otherCell]: the shared edge
    // is the one in the direction of the neighbour.
    if (ocol < col) return const Point(0.0, 0.5); // left edge
    if (ocol > col) return const Point(1.0, 0.5); // right edge
    if (orow < row) return const Point(0.5, 0.0); // top edge
    return const Point(0.5, 1.0); // bottom edge
  }

  const centre = Point(0.5, 0.5);
  final pts = <Point<double>>[];
  if (pos > 0) {
    // Entry: the edge shared with the previous cell.
    pts.add(edgeMidpoint(pathCells[pos - 1]));
    pts.add(centre);
  } else {
    // Tail cell: the shaft starts at the centre.
    pts.add(centre);
  }
  if (pos < pathCells.length - 1) {
    // Exit: the edge shared with the next cell.
    pts.add(edgeMidpoint(pathCells[pos + 1]));
  }
  return pts;
}

/// Pulls a polyline out along [direction] by [headTravel] (both in
/// board-cell units) — like pulling a rope by its head, which is
/// exactly what the user's recording shows: the tapped path turns
/// blue and is drawn out along its exit ray, straightening behind
/// the head, the tail following last.
///
/// The rope is INEXTENSIBLE and slides: a point at arc-distance [d]
/// from the head lands on the exit ray at head + dir * (travel - d)
/// once travel >= d (the pulled part, straight behind the head);
/// a point still beyond the pulled length slides FORWARD along the
/// rope's own path by [headTravel] (the tail follows the path the
/// head took). So the rope never stretches — the segment joining
/// the pulled part to the still-winding part stays short, and the
/// whole rope glides out smoothly. (The earlier snap version kept
/// unpulled points fixed, which stretched that joining segment into
/// a long diagonal on a winding path.) The head is the last point.
/// Returns the adjusted points, same order.
List<Point<double>> pullPolyline({
  required List<Point<double>> points,
  required Direction direction,
  required double headTravel,
}) {
  if (points.isEmpty) return points;
  if (headTravel <= 0) return List<Point<double>>.of(points);
  // Arc-length distance of each point from the head (last point).
  final distFromHead = List<double>.filled(points.length, 0);
  var acc = 0.0;
  for (var i = points.length - 2; i >= 0; i--) {
    final a = points[i];
    final b = points[i + 1];
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    acc += sqrt(dx * dx + dy * dy);
    distFromHead[i] = acc;
  }
  final head = points.last;
  final dx = direction.dCol.toDouble();
  final dy = direction.dRow.toDouble();
  // The point on the ORIGINAL polyline at arc-distance [target]
  // from the head (interpolated along the segment it falls on).
  // Used for the sliding (not yet pulled) part of the rope.
  Point<double> pointAtDistance(double target) {
    for (var i = points.length - 1; i > 0; i--) {
      final dHead = distFromHead[i];
      final dPrev = distFromHead[i - 1];
      if (target >= dHead && target <= dPrev) {
        final segLen = dPrev - dHead;
        final t = segLen <= 0 ? 0.0 : (target - dHead) / segLen;
        final a = points[i];
        final b = points[i - 1];
        return Point(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
      }
    }
    return points.first;
  }

  return [
    for (var i = 0; i < points.length; i++)
      if (distFromHead[i] <= headTravel)
        Point(
          head.x + dx * (headTravel - distFromHead[i]),
          head.y + dy * (headTravel - distFromHead[i]),
        )
      else
        pointAtDistance(distFromHead[i] - headTravel),
  ];
}
