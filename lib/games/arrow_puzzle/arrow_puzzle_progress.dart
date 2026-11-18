import 'package:shared_preferences/shared_preferences.dart';

/// Arrow Puzzle progress — local only (per-device).
///
/// Coins are server-side (Edge Functions); this service only tracks
/// which levels are unlocked, stars, and the daily free-hint budget.
/// Keys are namespaced `arrow_puzzle_` so they never collide with
/// anything else in SharedPreferences.
class ArrowPuzzleProgress {
  ArrowPuzzleProgress._();

  static const _prefix = 'arrow_puzzle_';
  static const _highestUnlockedKey = '${_prefix}highest_unlocked';
  static const _dailyDoneDateKey = '${_prefix}daily_done_date';
  static const _freeHintsDateKey = '${_prefix}free_hints_date';
  static const _freeHintsUsedKey = '${_prefix}free_hints_used';

  static String _starsKey(int level) => '${_prefix}stars_$level';
  static String _bestMovesKey(int level) => '${_prefix}best_moves_$level';

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';

  static Future<int> highestUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_highestUnlockedKey) ?? 1;
  }

  static Future<void> unlockNextAfter(int level) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_highestUnlockedKey) ?? 1;
    if (level + 1 > current) {
      await prefs.setInt(_highestUnlockedKey, level + 1);
    }
  }

  static Future<int> starsFor(int level) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_starsKey(level)) ?? 0;
  }

  static Future<void> recordWin(
    int level, {
    required int stars,
    required int moves,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final prevStars = prefs.getInt(_starsKey(level)) ?? 0;
    if (stars > prevStars) {
      await prefs.setInt(_starsKey(level), stars);
    }
    final prevBest = prefs.getInt(_bestMovesKey(level));
    if (prevBest == null || moves < prevBest) {
      await prefs.setInt(_bestMovesKey(level), moves);
    }
    await unlockNextAfter(level);
  }

  static Future<bool> isDailyDone(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_dailyDoneDateKey) == dateKey(date);
  }

  static Future<void> markDailyDone(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dailyDoneDateKey, dateKey(date));
  }

  /// Free hints left today (2/day, resets at midnight). The count is
  /// local and costs nothing, so no server call is involved.
  static Future<int> freeHintsLeft(
    DateTime now, {
    required int freeHintsPerDay,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final today = dateKey(now);
    if (prefs.getString(_freeHintsDateKey) != today) {
      await prefs.setString(_freeHintsDateKey, today);
      await prefs.setInt(_freeHintsUsedKey, 0);
      return freeHintsPerDay;
    }
    final used = prefs.getInt(_freeHintsUsedKey) ?? 0;
    final left = freeHintsPerDay - used;
    return left < 0 ? 0 : left;
  }

  /// Consumes one free hint for today. Returns false when none are left.
  static Future<bool> useFreeHint(
    DateTime now, {
    required int freeHintsPerDay,
  }) async {
    final left = await freeHintsLeft(now, freeHintsPerDay: freeHintsPerDay);
    if (left <= 0) return false;
    final prefs = await SharedPreferences.getInstance();
    final used = prefs.getInt(_freeHintsUsedKey) ?? 0;
    await prefs.setInt(_freeHintsUsedKey, used + 1);
    return true;
  }
}
