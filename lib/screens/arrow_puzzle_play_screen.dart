import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../games/arrow_puzzle/arrow_puzzle_model.dart';
import '../games/arrow_puzzle/arrow_puzzle_progress.dart';
import '../services/game_reward_ad_service.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';
import '../services/unity_ads_service.dart';

/// Arrow Puzzle play screen (v1.0.29, navy monochrome rebuild) —
/// follows the user's Level 51 screen recording: white background,
/// Level title, arrows-left chip, 3 hearts, difficulty chip, dense
/// maze board of thin NAVY (#14122E) tangled arrow paths, hint bulb +
/// ruler (Power) tools at the bottom, Unity banner. Exiting arrows
/// leave a light-blue (#6F7DAC) trail along their exit ray for
/// ~700ms; while Power is armed a faint light-blue grid (#D9DEEF)
/// overlays the board.
///
/// Rules (user-confirmed): tap an arrow — it exits if its path is
/// clear, otherwise it costs 1 heart (3 hearts per attempt). Hint
/// highlights a safe move (2 free/day, then coins). Power: the next
/// tapped arrow exits in any direction ignoring blocking, no heart
/// lost, and its exit path is revealed — consumed on that tap.
///
/// Rules (user-confirmed): tap an arrow — it exits if its path is
/// clear, otherwise it costs 1 heart (3 hearts per attempt). Hint
/// highlights a safe move (2 free/day, then coins). Power: the next
/// tapped arrow exits in any direction ignoring blocking, no heart
/// lost, and its exit path is revealed — consumed on that tap.
/// TWO CURRENCIES: Level Coins come ONLY from completing a level
/// (server claim) and are the only coins that become cash; Ad Coins
/// come ONLY from watching a rewarded ad (server claim) and are
/// spendable ONLY in-game — never cash, never convertible. Watch Ads
/// sits behind the remote-config flag (default OFF, Unity ticket
/// 00946156) — while it is off, the coin prices are the only live
/// path and the Watch Ad button is hidden entirely.
/// Navy monochrome board colours (v1.0.29, sampled from the user's
/// Level 51 screen recording with PIL — anti-aliased, so ±small
/// variance on the samples).
///
/// [arrowNavy] is the single colour of every arrow on the board.
/// [exitTrailBlue] is the light slate blue of the exit trail left
/// when an arrow slides out, and of the hint highlight.
/// [powerGridColor] is the faint grid shown while Power is armed.
const Color arrowNavy = Color(0xFF14122E);
const Color exitTrailBlue = Color(0xFF6F7DAC);
const Color powerGridColor = Color(0xFFD9DEEF);

class ArrowPuzzlePlayScreen extends StatefulWidget {
  const ArrowPuzzlePlayScreen({
    super.key,
    required this.level,
    this.dailyChallenge = false,
  });

  /// Level number. 0 when [dailyChallenge] is true (the board is
  /// generated from the date, not from a level number).
  final int level;
  final bool dailyChallenge;

  @override
  State<ArrowPuzzlePlayScreen> createState() => _ArrowPuzzlePlayScreenState();
}

class _ArrowPuzzlePlayScreenState extends State<ArrowPuzzlePlayScreen> {
  late ArrowPuzzleGame _game;
  int _heartsLost = 0;
  int _freeHintsLeft = 0;
  int? _balance;
  int? _adCoinsBalance;
  int? _hintCell;
  List<int> _revealedPath = [];
  int? _shakeCell;
  Timer? _hintTimer;
  Timer? _revealTimer;
  Timer? _shakeTimer;
  bool _winDialogShown = false;
  bool _loseDialogShown = false;
  bool _lifeBoughtThisAttempt = false;

  ArrowPuzzleConfig get _cfg =>
      RemoteConfigService.instance.config.arrowPuzzle;

  @override
  void initState() {
    super.initState();
    _newGame();
    _loadExtras();
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _revealTimer?.cancel();
    _shakeTimer?.cancel();
    super.dispose();
  }

  void _newGame() {
    final board = widget.dailyChallenge
        ? generateDailyLevel(DateTime.now())
        : generateLevel(widget.level);
    _game = ArrowPuzzleGame(board);
    _heartsLost = 0;
    _hintCell = null;
    _revealedPath = [];
    _shakeCell = null;
    _winDialogShown = false;
    _loseDialogShown = false;
    _lifeBoughtThisAttempt = false;
  }

  Future<void> _loadExtras() async {
    final freeLeft = await ArrowPuzzleProgress.freeHintsLeft(
      DateTime.now(),
      freeHintsPerDay: _cfg.freeHintsPerDay,
    );
    int? balance;
    try {
      balance = await SupabaseService.getBalance();
    } catch (_) {
      balance = null;
    }
    int? adBalance;
    try {
      final ad = await SupabaseService.getAdCoins();
      final raw = ad['ad_coins_balance'];
      if (raw is int) adBalance = raw;
    } catch (_) {
      adBalance = null;
    }
    if (!mounted) return;
    setState(() {
      _freeHintsLeft = freeLeft;
      _balance = balance;
      _adCoinsBalance = adBalance;
    });
  }

  Future<void> _refreshBalance() async {
    try {
      final balance = await SupabaseService.getBalance();
      if (mounted) setState(() => _balance = balance);
    } catch (_) {
      // Balance display is best-effort; the server enforces spends.
    }
  }

  Future<void> _refreshAdCoins() async {
    try {
      final ad = await SupabaseService.getAdCoins();
      final raw = ad['ad_coins_balance'];
      if (mounted && raw is int) setState(() => _adCoinsBalance = raw);
    } catch (_) {
      // Ad Coin display is best-effort; the server enforces the grant.
    }
  }

  /// Watch Ads top-up (flag-gated): a completed rewarded ad earns Ad
  /// Coins via the server claim. Returns the Ad Coins granted, or
  /// null when no ad was completed. Ad Coins are in-game only.
  Future<int?> _watchAdForCoins(BuildContext context) async {
    final t = AppLocalizations.of(context)!;
    final grant = await GameRewardAdService.tryGrantAdCoins(
      adsEnabled: _cfg.adsForRewardsEnabled,
    );
    if (grant != AdGrantResult.granted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.arrowPuzzleAdNotAvailable)),
        );
      }
      return null;
    }
    try {
      final res = await SupabaseService.claimAdReward(
        idempotencyKey: SupabaseService.newIdempotencyKey('ad-reward'),
      );
      final earned = res['ad_coins'];
      if (context.mounted && earned is int) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.arrowPuzzleAdCoinsEarned(earned))),
        );
      }
      unawaited(_refreshAdCoins());
      return earned is int ? earned : 0;
    } on Exception catch (e) {
      if (context.mounted) {
        final message = e.toString().contains('429')
            ? t.arrowPuzzleAdDailyCapReached
            : t.arrowPuzzleAdNotAvailable;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
      return null;
    }
  }

  void _onCellTap(int cellIndex) {
    if (_game.isWon || _game.isGameOver) return;
    final result = _game.tap(cellIndex);
    switch (result.kind) {
      case TapKind.invalid:
        return;
      case TapKind.cleared:
        setState(() => _hintCell = null);
        _showExitTrail(result.revealedPath);
        if (_game.isWon) _onWin();
      case TapKind.blocked:
        _heartsLost++;
        _flashShake(cellIndex);
        if (_game.isGameOver) _onLose();
      case TapKind.powerCleared:
        _showExitTrail(result.revealedPath);
        if (_game.isWon) _onWin();
    }
    setState(() {});
  }

  /// Highlights the exited arrow's exit ray in light blue, fading
  /// after ~700ms. Used for EVERY exit — a normal tap as well as a
  /// Power tap — matching the recording, where the arrow slides out
  /// along a straight light-blue line.
  void _showExitTrail(List<int> path) {
    if (path.isEmpty) return;
    setState(() => _revealedPath = path);
    _revealTimer?.cancel();
    _revealTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _revealedPath = []);
    });
  }

  void _flashShake(int cellIndex) {
    setState(() => _shakeCell = cellIndex);
    _shakeTimer?.cancel();
    _shakeTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _shakeCell = null);
    });
  }

  void _applyHint() {
    final cell = _game.findHint();
    if (cell == null) return;
    setState(() => _hintCell = cell);
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _hintCell = null);
    });
  }

  /// Hint flow: free hints first (2/day), then the coin price. The ad
  /// option appears only when the remote-config flag is on (Unity
  /// ticket 00946156) — it is off in this build.
  Future<void> _onHint() async {
    if (_game.isWon || _game.isGameOver) return;
    if (_freeHintsLeft > 0) {
      final used = await ArrowPuzzleProgress.useFreeHint(
        DateTime.now(),
        freeHintsPerDay: _cfg.freeHintsPerDay,
      );
      if (!mounted) return;
      if (used) {
        setState(() => _freeHintsLeft--);
        _applyHint();
      }
      return;
    }
    if (!mounted) return;
    _showBuySheet(
      item: 'hint',
      price: _cfg.hintPriceCoins,
      title: AppLocalizations.of(context)!.arrowPuzzleHint,
      onGranted: _applyHint,
    );
  }

  /// Power flow: tap the ruler to arm (after buying, if not already
  /// armed); tap again to disarm. Buying spends coins via the server.
  Future<void> _onPower() async {
    if (_game.isWon || _game.isGameOver) return;
    if (_game.powerArmed) {
      setState(() => _game.powerArmed = false);
      return;
    }
    if (!mounted) return;
    _showBuySheet(
      item: 'power',
      price: _cfg.powerPriceCoins,
      title: AppLocalizations.of(context)!.arrowPuzzlePower,
      onGranted: () {
        setState(() => _game.powerArmed = true);
      },
    );
  }

  /// Purchase sheet for an item. Two ways to pay, both server-side:
  /// Level Coins (the cash balance) or Ad Coins (the in-game-only
  /// Ad Coin balance — never cash, never convertible). The Watch Ad
  /// button tops up Ad Coins and appears only when the remote-config
  /// flag is on (Unity ticket 00946156); it is off in this build, so
  /// the coin prices are the only live path.
  void _showBuySheet({
    required String item,
    required int price,
    required String title,
    required VoidCallback onGranted,
  }) {
    final t = AppLocalizations.of(context)!;
    final adsEnabled = _cfg.adsForRewardsEnabled;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        // Local copy of the Ad Coin balance so the sheet can refresh
        // after a Watch Ad top-up without reopening.
        var adBalance = _adCoinsBalance ?? 0;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> buyWith(String currency) async {
              try {
                final res = await SupabaseService.spendGameItem(
                  item: item,
                  level: widget.level,
                  currency: currency,
                );
                if (!sheetContext.mounted) return;
                final newAd = res['new_ad_balance'];
                if (newAd is int) {
                  setState(() => _adCoinsBalance = newAd);
                  setSheetState(() => adBalance = newAd);
                }
                Navigator.of(sheetContext).pop();
                onGranted();
                unawaited(_refreshBalance());
              } catch (_) {
                if (!sheetContext.mounted) return;
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(content: Text(t.arrowPuzzleNotEnoughCoins)),
                );
              }
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${t.balance}: ${_balance ?? '—'} ${t.coins}',
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      t.arrowPuzzleAdCoinsBalance(adBalance),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => unawaited(buyWith('level_coins')),
                      child: Text(
                        item == 'hint'
                            ? t.arrowPuzzleBuyHintCoins(price)
                            : item == 'power'
                                ? t.arrowPuzzleBuyPowerCoins(price)
                                : t.arrowPuzzleBuyLifeCoins(price),
                      ),
                    ),
                    if (adBalance >= price) ...[
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: () => unawaited(buyWith('ad_coins')),
                        child: Text(
                          t.arrowPuzzleBuyWithAdCoins(price),
                        ),
                      ),
                    ],
                    if (adsEnabled) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () async {
                          final earned =
                              await _watchAdForCoins(sheetContext);
                          if (earned == null) return;
                          final ad = await SupabaseService.getAdCoins()
                              .catchError(
                            (_) => const <String, dynamic>{},
                          );
                          final raw = ad['ad_coins_balance'];
                          if (!sheetContext.mounted) return;
                          if (raw is int) {
                            setState(() => _adCoinsBalance = raw);
                            setSheetState(() => adBalance = raw);
                          }
                        },
                        child: Text(
                          t.arrowPuzzleWatchAdGetCoins(
                            _cfg.adCoinsPerAd,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _elapsed() {
    final start = _game.startedAt;
    if (start == null) return '0:00';
    final d = DateTime.now().difference(start);
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _onWin() async {
    if (_winDialogShown) return;
    _winDialogShown = true;
    final t = AppLocalizations.of(context)!;
    final stars = _game.starsForWin(heartsLost: _heartsLost);
    final moves = _game.moves;
    final elapsed = _elapsed();

    int? coinsEarned;
    var alreadyClaimed = false;
    var claimFailed = false;
    try {
      final res = await SupabaseService.claimGameLevel(
        widget.level,
        dailyChallenge: widget.dailyChallenge,
        moves: moves,
        heartsLost: _heartsLost,
      );
      if (res['already'] == true) {
        alreadyClaimed = true;
      } else if (res['coins'] is int) {
        coinsEarned = res['coins'] as int;
      }
    } catch (_) {
      // Fail-soft: the win still counts locally; the server claim
      // can be retried by replaying (idempotency makes it safe).
      claimFailed = true;
    }

    if (widget.dailyChallenge) {
      await ArrowPuzzleProgress.markDailyDone(DateTime.now());
    } else {
      await ArrowPuzzleProgress.recordWin(
        widget.level,
        stars: stars,
        moves: moves,
      );
    }
    unawaited(_refreshBalance());
    if (!mounted) return;

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(t.arrowPuzzleLevelComplete),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  3,
                  (i) => Icon(
                    i < stars ? Icons.star : Icons.star_border,
                    size: 32,
                    color: i < stars ? Colors.amber : Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('${t.arrowPuzzleMoves}: $moves   •   $elapsed'),
              const SizedBox(height: 8),
              Text(
                alreadyClaimed
                    ? t.arrowPuzzleAlreadyClaimed
                    : claimFailed
                        ? t.genericError
                        : coinsEarned != null
                            ? t.arrowPuzzleCoinsEarned(coinsEarned)
                            : '',
                style: const TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('home'),
              child: Text(t.appTitle),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('replay'),
              child: Text(t.arrowPuzzleReplay),
            ),
            if (!widget.dailyChallenge)
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop('next'),
                child: Text(t.arrowPuzzleNextLevel),
              ),
          ],
        );
      },
    );
    if (!mounted) return;
    if (choice == 'next') {
      unawaited(UnityAdsService.maybeShowLevelInterstitial(
        everyNthLevel: _cfg.interstitialEveryNthLevel,
        minGap: Duration(minutes: _cfg.interstitialMinGapMinutes),
      ));
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ArrowPuzzlePlayScreen(level: widget.level + 1),
        ),
      );
    } else if (choice == 'replay') {
      setState(_newGame);
    } else {
      Navigator.of(context).pop();
    }
  }

  /// Buys +1 heart with the selected currency and continues the
  /// attempt. One purchase per game-over (after buying, hearts = 1;
  /// losing it again ends the game for real).
  Future<void> _buyLife({required String currency}) async {
    final t = AppLocalizations.of(context)!;
    try {
      final res = await SupabaseService.spendGameItem(
        item: 'life',
        level: widget.level,
        currency: currency,
      );
      final newAd = res['new_ad_balance'];
      if (!mounted) return;
      setState(() {
        if (newAd is int) _adCoinsBalance = newAd;
        _game.hearts = 1;
        _lifeBoughtThisAttempt = true;
        _loseDialogShown = false;
      });
      unawaited(_refreshBalance());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.arrowPuzzleNotEnoughCoins)),
      );
      setState(() => _loseDialogShown = false);
    }
  }

  Future<void> _onLose() async {
    if (_loseDialogShown) return;
    _loseDialogShown = true;
    final t = AppLocalizations.of(context)!;
    final canBuyLife = !_lifeBoughtThisAttempt;
    final lifePrice = _cfg.lifePriceCoins;
    final canPayWithAdCoins =
        (_adCoinsBalance ?? 0) >= lifePrice;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(t.arrowPuzzleGameOver),
          content: canBuyLife
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t.arrowPuzzleBuyLifeCoins(lifePrice),
                      textAlign: TextAlign.center,
                    ),
                    if (_cfg.adsForRewardsEnabled)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          t.arrowPuzzleAdCoinsBalance(
                            _adCoinsBalance ?? '—',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                )
              : const SizedBox.shrink(),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('quit'),
              child: Text(t.appTitle),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('retry'),
              child: Text(t.arrowPuzzleReplay),
            ),
            if (canBuyLife) ...[
              if (canPayWithAdCoins)
                FilledButton.tonal(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop('life_ad'),
                  child: Text(
                    t.arrowPuzzleBuyWithAdCoins(lifePrice),
                  ),
                ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop('life'),
                child: Text(
                  t.arrowPuzzleBuyLifeCoins(lifePrice),
                ),
              ),
              if (_cfg.adsForRewardsEnabled)
                TextButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop('watch_ad'),
                  child: Text(
                    t.arrowPuzzleWatchAdGetCoins(_cfg.adCoinsPerAd),
                  ),
                ),
            ],
          ],
        );
      },
    );
    if (!mounted) return;
    if (choice == 'life') {
      await _buyLife(currency: 'level_coins');
    } else if (choice == 'life_ad') {
      await _buyLife(currency: 'ad_coins');
    } else if (choice == 'watch_ad') {
      // Top up Ad Coins, then re-show the dialog so the "Use Ad
      // Coins" button appears once the balance covers the life.
      await _watchAdForCoins(context);
      if (!mounted) return;
      setState(() => _loseDialogShown = false);
      unawaited(_onLose());
    } else if (choice == 'retry') {
      setState(_newGame);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _restartLevel() {
    setState(_newGame);
  }

  Widget _buildCell(int index) {
    final arrow = _game.arrows[index];
    final isStone = _game.stones.contains(index);
    final isHint = _hintCell == index;
    final isRevealed = _revealedPath.contains(index);
    final isShake = _shakeCell == index;
    // Maze board: cells are transparent — the thin navy lines flow
    // across cell borders into one tangled maze on white. Only the
    // transient states tint a cell, in the light exit-trail blue.
    final Color? bg;
    if (isShake) {
      bg = Colors.red.shade100;
    } else if (isRevealed) {
      bg = exitTrailBlue.withValues(alpha: 0.45);
    } else if (isHint) {
      bg = exitTrailBlue.withValues(alpha: 0.18);
    } else {
      bg = null;
    }
    Widget? child;
    if (isStone) {
      child = const CustomPaint(painter: _StoneDotPainter());
    } else if (arrow != null) {
      child = CustomPaint(
        painter: MazeArrowPainter(
          direction: arrow.direction,
          colorIndex: arrow.colorIndex,
          cellIndex: index,
          boardSize: _game.size,
          highlight: isHint,
        ),
      );
    }
    return GestureDetector(
      onTap: () => _onCellTap(index),
      child: Container(
        color: bg,
        child: Container(
          decoration: BoxDecoration(
            border: isHint
                ? Border.all(color: exitTrailBlue, width: 3)
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _toolButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    int? badge,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: active
                  ? Border.all(color: color, width: 3)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, size: 36, color: color),
          ),
          if (badge != null)
            Positioned(
              right: -2,
              top: -6,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final size = _game.size;
    final title = widget.dailyChallenge
        ? t.arrowPuzzleDailyChallenge
        : t.arrowPuzzleLevel(widget.level);
    final difficulty = widget.dailyChallenge
        ? 'Hard'
        : difficultyForLevel(widget.level);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F2937),
        elevation: 0,
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t.arrowPuzzleReplay,
            onPressed: _restartLevel,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings),
            onSelected: (value) {
              if (value == 'restart') {
                _restartLevel();
              } else if (value == 'quit') {
                Navigator.of(context).pop();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'restart',
                child: Text(t.arrowPuzzleReplay),
              ),
              const PopupMenuItem(
                value: 'quit',
                child: Text('Quit'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.navigation,
                        size: 16,
                        color: Color(0xFF1F2937),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        // Arrows left (the reference's "152"), not moves.
                        '${_game.arrowsLeft}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: List.generate(
                    3,
                    (i) => Icon(
                      i < _game.hearts ? Icons.favorite : Icons.favorite_border,
                      color: Colors.red,
                      size: 28,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    difficulty,
                    style: const TextStyle(color: Color(0xFF1F2937)),
                  ),
                ),
              ],
            ),
          ),
          if (_game.powerArmed)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                t.arrowPuzzlePowerActive,
                style: const TextStyle(
                  color: Color(0xFF1E88E5),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.all(8),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    children: [
                      GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: size,
                          crossAxisSpacing: 0,
                          mainAxisSpacing: 0,
                        ),
                        itemCount: size * size,
                        itemBuilder: (context, index) => _buildCell(index),
                      ),
                      // While Power (ruler) is armed, a faint
                      // light-blue grid overlays the whole board.
                      // Pointer-transparent: taps still reach the
                      // cells underneath.
                      if (_game.powerArmed)
                        Positioned.fill(
                          child: PowerGridOverlay(
                            key: const ValueKey('power-grid-overlay'),
                            boardSize: size,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              '${t.balance}: ${_balance ?? '—'} ${t.coins}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.black54),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16, top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _toolButton(
                  icon: Icons.lightbulb,
                  color: Colors.amber.shade700,
                  badge: _freeHintsLeft,
                  onTap: _onHint,
                ),
                _toolButton(
                  icon: Icons.straighten,
                  color: Colors.purple,
                  active: _game.powerArmed,
                  onTap: _onPower,
                ),
              ],
            ),
          ),
          const UnityBannerAdWidget(),
        ],
      ),
    );
  }
}

/// Draws one arrow as a thin winding maze path (see [mazePathPoints]):
/// a thin NAVY polyline (one colour for every arrow, v1.0.29) that
/// starts on one cell edge, turns once or twice at right angles, and
/// ends with an arrowhead on the exit edge. Neighbouring cells' lines
/// meet at shared edges, so the board reads as one tangled maze.
/// [highlight] (hint) draws the line in the light exit-trail blue.
/// [colorIndex] is accepted for stability and ignored for colour.
class MazeArrowPainter extends CustomPainter {
  MazeArrowPainter({
    required this.direction,
    required this.colorIndex,
    required this.cellIndex,
    required this.boardSize,
    this.highlight = false,
  });

  final Direction direction;

  /// Retained for stability/determinism; the navy rebuild draws
  /// every arrow in [arrowNavy] regardless of this value.
  final int colorIndex;
  final int cellIndex;
  final int boardSize;
  final bool highlight;

  /// The colour an arrow is drawn in: the single navy for every
  /// arrow, or the light exit-trail blue for a highlighted (hint)
  /// arrow. Independent of [colorIndex] by design.
  static Color colorFor({required bool highlight}) =>
      highlight ? exitTrailBlue : arrowNavy;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final color = colorFor(highlight: highlight);
    // Inset only a hair: neighbouring cells' lines must meet at the
    // shared edge so the maze reads as long interlocking paths, not
    // isolated squiggles. (A bigger inset visibly breaks the paths.)
    const inset = 0.005;
    final points = mazePathPoints(
      cellIndex: cellIndex,
      direction: direction,
      boardSize: boardSize,
    )
        .map(
          (p) => Offset(
            (inset + p.x * (1 - 2 * inset)) * s,
            (inset + p.y * (1 - 2 * inset)) * s,
          ),
        )
        .toList(growable: false);
    final stroke = Paint()
      ..color = color
      ..strokeWidth = (s * 0.075).clamp(2.5, 4.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, stroke);
    // Arrowhead at the end, pointing along the final segment.
    final tip = points.last;
    final prev = points[points.length - 2];
    final dx = tip.dx - prev.dx;
    final dy = tip.dy - prev.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len > 0.01) {
      final ux = dx / len;
      final uy = dy / len;
      final headLen = s * 0.15;
      final headHalf = s * 0.10;
      final base = Offset(tip.dx - ux * headLen, tip.dy - uy * headLen);
      final perp = Offset(-uy, ux);
      final head = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(
          base.dx + perp.dx * headHalf,
          base.dy + perp.dy * headHalf,
        )
        ..lineTo(
          base.dx - perp.dx * headHalf,
          base.dy - perp.dy * headHalf,
        )
        ..close();
      canvas.drawPath(
        head,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant MazeArrowPainter old) =>
      old.direction != direction ||
      old.cellIndex != cellIndex ||
      old.boardSize != boardSize ||
      old.highlight != highlight;
}

/// Faint light-blue grid over the whole board while Power (ruler) is
/// armed (v1.0.29, from the user's recording): 1px [powerGridColor]
/// lines at every cell boundary, above the board and below the
/// HUD/tools. Pointer-transparent so taps still reach the cells.
class PowerGridOverlay extends StatelessWidget {
  const PowerGridOverlay({super.key, required this.boardSize});

  final int boardSize;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _PowerGridPainter(boardSize: boardSize),
      ),
    );
  }
}

class _PowerGridPainter extends CustomPainter {
  const _PowerGridPainter({required this.boardSize});

  final int boardSize;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = powerGridColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final stepX = size.width / boardSize;
    final stepY = size.height / boardSize;
    for (var i = 0; i <= boardSize; i++) {
      final x = i * stepX;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      final y = i * stepY;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PowerGridPainter old) =>
      old.boardSize != boardSize;
}

/// A stone blocker on the maze board: a small dark dot.
class _StoneDotPainter extends CustomPainter {
  const _StoneDotPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.drawCircle(
      Offset(s / 2, s / 2),
      s * 0.16,
      Paint()
        ..color = const Color(0xFF1A2450)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _StoneDotPainter old) => false;
}
