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

/// Arrow Puzzle play screen (path-model rebuild) — follows the
/// user's Level 51 screen recording, measured frame-by-frame: white
/// background, "Level 51" title with a blue back chevron and a blue
/// outline gear, arrows-left chip, 3 hearts, difficulty chip, a TALL
/// rectangular board (26x50 at L51) of thin NAVY (#14122E) winding
/// arrow paths — one arrow = one long polyline path, with a SMALL
/// head at one end — faint grey dots in empty cells, hint bulb +
/// ruler (Power) tools at the bottom, Unity banner. A tapped path
/// turns BRIGHT BLUE (#3584E2) and is pulled out along its exit ray
/// — the polyline straightening behind its head like a rope, then
/// fading — exactly as in the recording. While Power is armed a
/// faint light-blue grid (#D9DEEF) overlays the board, spanning the
/// full screen width (the recording's grid runs edge to edge, not
/// just over the board).
///
/// Rules: tap a path — it exits if no other path's HEAD lies on its
/// exit ray (shafts never block; the recording's rope passes over
/// them), otherwise it costs 1 heart (3 hearts per attempt). Hint
/// highlights a safe path (2 free/day, then coins). Power: the next
/// tapped path exits in any direction ignoring blocking, no heart
/// lost, and its exit path is revealed — consumed on that tap.
/// TWO CURRENCIES: Level Coins come ONLY from completing a level
/// (server claim) and are the only coins that become cash; Ad Coins
/// come ONLY from watching a rewarded ad (server claim) and are
/// spendable ONLY in-game — never cash, never convertible. Watch Ads
/// sits behind the remote-config flag (default OFF, Unity ticket
/// 00946156) — while it is off, the coin prices are the only live
/// path and the Watch Ad button is hidden entirely.
/// Board colours (sampled from the user's Level 51 screen recording
/// with PIL).
///
/// [arrowNavy] is the single colour of every path on the board
/// (median dark pixel #161532, i.e. #14122E within anti-aliasing).
/// [exitTrailBlue] is the BRIGHT blue of the exiting path and the
/// hint highlight (median trail pixel #3584E2 — a vivid blue, not
/// the grey slate blue used before). [emptyDotColor] is the faint
/// grey-blue dot in empty cells (#DDDEE5). [powerGridColor] is the
/// faint grid shown while Power is armed.
const Color arrowNavy = Color(0xFF14122E);
const Color exitTrailBlue = Color(0xFF3584E2);
const Color emptyDotColor = Color(0xFFDDDEE5);
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

class _ArrowPuzzlePlayScreenState extends State<ArrowPuzzlePlayScreen>
    with SingleTickerProviderStateMixin {
  late ArrowPuzzleGame _game;
  int _heartsLost = 0;
  int _freeHintsLeft = 0;
  int? _balance;
  int? _adCoinsBalance;
  Set<int> _hintCells = <int>{};
  int? _shakeCell;
  Timer? _hintTimer;
  Timer? _shakeTimer;
  bool _winDialogShown = false;
  bool _loseDialogShown = false;
  bool _lifeBoughtThisAttempt = false;

  /// The arrow currently sliding out (bright blue, pulled along its
  /// exit ray), driven by [_exitController]. Null when no exit is
  /// animating.
  _ExitingArrow? _exiting;
  late final AnimationController _exitController;

  ArrowPuzzleConfig get _cfg =>
      RemoteConfigService.instance.config.arrowPuzzle;

  @override
  void initState() {
    super.initState();
    _exitController = AnimationController(
      vsync: this,
      // The recording's exit takes ~0.5s from tap to gone.
      duration: const Duration(milliseconds: 550),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _exiting = null);
        }
      });
    _newGame();
    _loadExtras();
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _shakeTimer?.cancel();
    _exitController.dispose();
    super.dispose();
  }

  void _newGame() {
    final board = widget.dailyChallenge
        ? generateDailyLevel(DateTime.now())
        : generateLevel(widget.level);
    _game = ArrowPuzzleGame(board);
    _heartsLost = 0;
    _hintCells = <int>{};
    _exiting = null;
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
        setState(() => _hintCells = <int>{});
        _startExitAnimation(result);
        if (_game.isWon) _onWin();
      case TapKind.blocked:
        _heartsLost++;
        _flashShake(cellIndex);
        if (_game.isGameOver) _onLose();
      case TapKind.powerCleared:
        _startExitAnimation(result);
        if (_game.isWon) _onWin();
    }
    setState(() {});
  }

  /// Starts the exit animation for the path that just left: the
  /// path's polyline, in bright blue, pulled out along its exit ray
  /// — first recolouring in place, then straightening behind its
  /// head like a rope, then fading — exactly as in the user's
  /// recording (where the tapped path turns blue and slides out
  /// visibly). The path is already gone from the board; this
  /// overlay draws it sliding away.
  void _startExitAnimation(TapResult result) {
    final cells = result.exitedPathCells;
    final dir = result.exitedDirection;
    if (cells.isEmpty || dir == null) return;
    final polyline = pathPolylinePoints(
      pathCells: cells,
      headDirection: dir,
      cols: _game.cols,
    );
    setState(() {
      _exiting = _ExitingArrow(
        polyline: polyline,
        direction: dir,
        headCell: cells.last,
      );
    });
    _exitController.forward(from: 0);
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
    // Highlight the WHOLE hinted path, not just its head cell.
    final pathId = _game.pathIdForCell(cell);
    final path = pathId == null ? null : _game.pathById(pathId);
    setState(() => _hintCells = path == null ? <int>{cell} : path.cells.toSet());
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _hintCells = <int>{});
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
    final pathId = _game.pathIdForCell(index);
    final path = pathId == null ? null : _game.pathById(pathId);
    final isHint = _hintCells.contains(index);
    final isShake = _shakeCell == index;
    // Path board: cells are transparent — the thin navy lines flow
    // across cell borders into one tangled maze on white. Only the
    // transient states tint a cell, in the bright exit blue. Empty
    // cells show the recording's faint grey dot.
    final Color? bg;
    if (isShake) {
      bg = Colors.red.shade100;
    } else if (isHint) {
      bg = exitTrailBlue.withValues(alpha: 0.18);
    } else {
      bg = null;
    }
    Widget? child;
    if (path != null) {
      child = CustomPaint(
        painter: PathSegmentPainter(
          pathCells: path.cells,
          cellIndex: index,
          headDirection: path.headDirection,
          cols: _game.cols,
          highlight: isHint,
        ),
      );
    } else {
      child = const CustomPaint(painter: _EmptyDotPainter());
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

  /// A round tool button (hint bulb / Power ruler). The icon is an
  /// emoji, matching the recording's 3D-looking yellow bulb and
  /// purple ruler (the flat Material icons looked nothing like
  /// them). [badge] is the free-hints count on the bulb.
  Widget _toolButton({
    required String emoji,
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
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 36)),
            ),
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
    final cols = _game.cols;
    final rows = _game.rows;
    final title = widget.dailyChallenge
        ? t.arrowPuzzleDailyChallenge
        : t.arrowPuzzleLevel(widget.level);
    final difficulty = widget.dailyChallenge
        ? 'Hard'
        : difficultyForLevel(widget.level);
    // The recording has no AppBar: "Level 51" is centred with a blue
    // back chevron on the left and a blue outline gear on the right.
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(
                      Icons.chevron_left,
                      size: 36,
                      color: Color(0xFF2196F3),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: Color(0xFF2196F3),
                      size: 28,
                    ),
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
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          // The recording's chip icon is a small grey
                          // cursor arrow pointing up-right.
                          Icons.near_me,
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
                        i < _game.hearts
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: Colors.red,
                        size: 28,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
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
                  constraints: const BoxConstraints(maxWidth: 500),
                  padding: const EdgeInsets.all(8),
                  child: AspectRatio(
                    aspectRatio: cols / rows,
                    child: Stack(
                      // The Power grid paints beyond the board's
                      // left/right edges (full screen width, like
                      // the recording), so the stack must not clip.
                      clipBehavior: Clip.none,
                      children: [
                        // The Power grid sits UNDER the board: the
                        // recording's grid lines run behind the navy
                        // arrows, which stay crisp on top.
                        if (_game.powerArmed)
                          Positioned.fill(
                            child: PowerGridOverlay(
                              key: const ValueKey('power-grid-overlay'),
                              cols: cols,
                              rows: rows,
                            ),
                          ),
                        GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            crossAxisSpacing: 0,
                            mainAxisSpacing: 0,
                          ),
                          itemCount: cols * rows,
                          itemBuilder: (context, index) =>
                              _buildCell(index),
                        ),
                        // The exiting arrow, sliding out in bright
                        // blue over the board. Clipped to the board:
                        // the recording's trail never leaves it.
                        if (_exiting != null)
                          Positioned.fill(
                            child: ClipRect(
                              child: AnimatedBuilder(
                                animation: _exitController,
                                builder: (context, child) {
                                  return CustomPaint(
                                    painter: _ExitingArrowPainter(
                                      exiting: _exiting!,
                                      progress: _exitController.value,
                                      cols: cols,
                                      rows: rows,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16, top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _toolButton(
                    emoji: '💡',
                    color: Colors.amber.shade700,
                    badge: _freeHintsLeft,
                    onTap: _onHint,
                  ),
                  _toolButton(
                    emoji: '📏',
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
      ),
    );
  }
}

/// One path sliding out: its polyline (in board-cell coordinates)
/// plus the direction it is pulled along and the head cell it
/// started from (for the exit-ray length). Held in state while the
/// exit animation runs.
class _ExitingArrow {
  const _ExitingArrow({
    required this.polyline,
    required this.direction,
    required this.headCell,
  });

  /// The path's polyline in board-cell coordinates (see
  /// [pathPolylinePoints]); the last point is the arrowhead tip.
  final List<math.Point<double>> polyline;
  final Direction direction;

  /// The head cell the path started from (for the ray length).
  final int headCell;
}

/// Draws one cell's piece of a path (see [cellSegmentPoints]): a
/// thin NAVY shaft (one colour for every path, v1.0.29) that runs
/// from the entry edge-midpoint, through the cell centre, to the
/// exit edge-midpoint — so neighbouring cells' segments meet at the
/// shared edges and the board reads as one tangled maze of long
/// winding paths. The head cell also draws a SMALL filled arrowhead
/// triangle at the tip (centre + 0.5 in the head direction). The
/// recording's heads are ~12px on a 19px pitch (~0.63) but read as
/// small because each path is several cells long — so the head is
/// 0.55 of the cell long, far smaller relative to the path than the
/// old one-arrow-per-cell heads were. Shafts are ~0.16 of the pitch
/// thick. [highlight] (hint) draws the segment in the bright exit
/// blue.
class PathSegmentPainter extends CustomPainter {
  PathSegmentPainter({
    required this.pathCells,
    required this.cellIndex,
    required this.headDirection,
    required this.cols,
    this.highlight = false,
  });

  /// The whole path's cells (head-last), so this cell's segment can
  /// be found from its neighbours in the path.
  final List<int> pathCells;
  final int cellIndex;
  final Direction headDirection;
  final int cols;
  final bool highlight;

  /// The colour a segment is drawn in: the single navy for every
  /// path, or the bright exit blue for a highlighted (hint) path.
  static Color colorFor({required bool highlight}) =>
      highlight ? exitTrailBlue : arrowNavy;

  /// Shaft width as a fraction of the cell: the recording's shafts
  /// are ~3px on a 19px pitch (0.16).
  static double strokeWidthFor(double cellSize) =>
      (cellSize * 0.16).clamp(2.0, 5.0);

  /// Arrowhead length / half-width as a fraction of the cell: the
  /// recording's heads are ~12px on a 19px pitch (0.63) but read as
  /// small on a multi-cell path — 0.55 long, 0.56 wide.
  static double headLengthFor(double cellSize) => cellSize * 0.55;
  static double headHalfWidthFor(double cellSize) => cellSize * 0.28;

  /// Draws an arrowhead triangle at [tip], pointing along
  /// ([ux], [uy]) (a unit vector), in [color].
  static void drawHead(
    Canvas canvas,
    Offset tip,
    double ux,
    double uy,
    double cellSize,
    Color color,
  ) {
    final headLen = headLengthFor(cellSize);
    final headHalf = headHalfWidthFor(cellSize);
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

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final color = colorFor(highlight: highlight);
    // Inset only a hair: neighbouring cells' segments must meet at
    // the shared edge so the maze reads as long interlocking paths,
    // not isolated squiggles. (A bigger inset visibly breaks the
    // paths.)
    const inset = 0.005;
    final points = cellSegmentPoints(
      pathCells: pathCells,
      cellIndex: cellIndex,
      cols: cols,
    )
        .map(
          (p) => Offset(
            (inset + p.x * (1 - 2 * inset)) * s,
            (inset + p.y * (1 - 2 * inset)) * s,
          ),
        )
        .toList(growable: false);
    if (points.isEmpty) return;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = strokeWidthFor(s)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, stroke);
    // Arrowhead on the head cell, at the tip (centre + 0.5 in the
    // head direction), pointing along the head direction.
    if (cellIndex == pathCells.last) {
      final ux = headDirection.dCol.toDouble();
      final uy = headDirection.dRow.toDouble();
      final tip = Offset(
        (inset + (0.5 + ux * 0.5) * (1 - 2 * inset)) * s,
        (inset + (0.5 + uy * 0.5) * (1 - 2 * inset)) * s,
      );
      drawHead(canvas, tip, ux, uy, s, color);
    }
  }

  @override
  bool shouldRepaint(covariant PathSegmentPainter old) =>
      old.pathCells != pathCells ||
      old.cellIndex != cellIndex ||
      old.headDirection != headDirection ||
      old.cols != cols ||
      old.highlight != highlight;
}

/// Faint grey dot in an empty cell (the recording's empty areas are
/// dotted, not blank): one #DDDEE5 dot per empty cell, ~0.16 of the
/// cell across, centred.
class _EmptyDotPainter extends CustomPainter {
  const _EmptyDotPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.drawCircle(
      Offset(s / 2, s / 2),
      s * 0.08,
      Paint()
        ..color = emptyDotColor
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _EmptyDotPainter old) => false;
}

/// The exiting path, sliding out in bright blue: the tapped path's
/// polyline, recoloured bright blue and pulled along its exit ray —
/// first in place, then straightening behind its head like a rope
/// ([pullPolyline]), then fading — exactly as in the user's
/// recording, where the tapped path turns blue and slides out
/// visibly. [progress] is the animation controller's value (0..1):
/// 0-0.15 the path sits blue in place, 0.15-0.85 it is pulled out,
/// 0.85-1 it fades away. The head travels the path's arc length
/// plus the REAL exit-ray length (head cell to board edge), so the
/// whole long path leaves the board — the old 0.75 fudge assumed
/// the head was already near the edge, which is false for a
/// multi-cell path starting deep in the board.
class _ExitingArrowPainter extends CustomPainter {
  _ExitingArrowPainter({
    required this.exiting,
    required this.progress,
    required this.cols,
    required this.rows,
  });

  final _ExitingArrow exiting;
  final double progress;
  final int cols;
  final int rows;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / cols;
    final cellH = size.height / rows;
    final cell = math.min(cellW, cellH);
    // Arc length of the polyline, in board-cell units.
    var arcLen = 0.0;
    final pts = exiting.polyline;
    for (var i = 1; i < pts.length; i++) {
      final dx = pts[i].x - pts[i - 1].x;
      final dy = pts[i].y - pts[i - 1].y;
      arcLen += math.sqrt(dx * dx + dy * dy);
    }
    // Exit-ray length: head cell to the board edge, in cells.
    final headRow = exiting.headCell ~/ cols;
    final headCol = exiting.headCell % cols;
    final rayLen = switch (exiting.direction) {
      Direction.up => headRow,
      Direction.down => rows - 1 - headRow,
      Direction.left => headCol,
      Direction.right => cols - 1 - headCol,
    };
    double headTravel;
    double opacity;
    if (progress < 0.15) {
      headTravel = 0;
      opacity = 1;
    } else if (progress < 0.85) {
      final t = (progress - 0.15) / 0.70;
      headTravel = t * (arcLen + rayLen);
      opacity = 1;
    } else {
      headTravel = arcLen + rayLen;
      opacity = (1 - progress) / 0.15;
    }
    final pulled = pullPolyline(
      points: pts,
      direction: exiting.direction,
      headTravel: headTravel,
    );
    final color = exitTrailBlue.withValues(alpha: opacity);
    final pixelPts = pulled
        .map((p) => Offset(p.x * cellW, p.y * cellH))
        .toList(growable: false);
    final stroke = Paint()
      ..color = color
      ..strokeWidth = PathSegmentPainter.strokeWidthFor(cell)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(pixelPts.first.dx, pixelPts.first.dy);
    for (var i = 1; i < pixelPts.length; i++) {
      path.lineTo(pixelPts[i].dx, pixelPts[i].dy);
    }
    canvas.drawPath(path, stroke);
    // Arrowhead at the pulled head, pointing along the exit ray.
    final tip = pixelPts.last;
    final prev = pixelPts[pixelPts.length - 2];
    final dx = tip.dx - prev.dx;
    final dy = tip.dy - prev.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len > 0.01) {
      PathSegmentPainter.drawHead(
        canvas,
        tip,
        dx / len,
        dy / len,
        cell,
        color,
      );
    } else {
      // Fully straightened: the head points along the exit ray.
      final ux = exiting.direction.dCol.toDouble();
      final uy = exiting.direction.dRow.toDouble();
      PathSegmentPainter.drawHead(canvas, tip, ux, uy, cell, color);
    }
  }

  @override
  bool shouldRepaint(covariant _ExitingArrowPainter old) =>
      old.progress != progress || old.exiting != exiting;
}

/// Faint light-blue grid over the board while Power (ruler) is armed
/// (from the user's recording): 1px [powerGridColor] lines at every
/// cell boundary. The recording's grid spans the FULL SCREEN WIDTH —
/// edge to edge, well beyond the board — and runs from the board's
/// top to its bottom, so the vertical lines are drawn far past the
/// board's left/right edges (the board stack does not clip) while
/// the horizontal lines stay within the board's height. The grid
/// sits UNDER the arrows (the board paints it first), so the navy
/// lines stay crisp on top. Pointer-transparent so taps still reach
/// the cells.
class PowerGridOverlay extends StatelessWidget {
  const PowerGridOverlay({super.key, required this.cols, required this.rows});

  final int cols;
  final int rows;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _PowerGridPainter(cols: cols, rows: rows),
      ),
    );
  }
}

class _PowerGridPainter extends CustomPainter {
  const _PowerGridPainter({required this.cols, required this.rows});

  final int cols;
  final int rows;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = powerGridColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final stepX = size.width / cols;
    final stepY = size.height / rows;
    // Vertical lines: the board's column boundaries, extended far
    // past both edges so the grid spans the full screen width.
    for (var i = -80; i <= cols + 80; i++) {
      final x = i * stepX;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // Horizontal lines: the board's row boundaries, also full-width.
    for (var j = 0; j <= rows; j++) {
      final y = j * stepY;
      canvas.drawLine(
        Offset(-2000, y),
        Offset(size.width + 2000, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PowerGridPainter old) =>
      old.cols != cols || old.rows != rows;
}
