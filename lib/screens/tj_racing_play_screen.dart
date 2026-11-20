import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_embed_unity/flutter_embed_unity.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../games/tj_racing/race_rewards.dart';
import '../games/tj_racing/race_settings.dart';
import '../games/tj_racing/unity_bridge.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';
import '../services/validation.dart'
    show formatCoinsAsPkr, minWithdrawalCoins;

/// TJ Racing 3D — Unity host screen (v1.0.32).
///
/// ORIENTATION (v1.0.32): this screen is LANDSCAPE (menu, splash and
/// race — the approved landscape splash mockup); the rest of the app
/// is portrait-only (locked in main()). Unity's PlayerSettings
/// defaultScreenOrientation is LandscapeLeft, so Flutter requests
/// exactly that here — one fixed orientation, no fighting. Portrait
/// is restored on every exit (back / pop / dispose).
///
/// The game UI lives in UNITY (MainMenu scene: menu, garage, RACE
/// button; Race_NightCity scene: race, HUD, results). Flutter is
/// the host: it embeds the Unity view, sends config / balances /
/// unlocks over the bridge (`unity_bridge.dart`), and does every
/// coin operation server-side. Unity NEVER credits anything.
///
/// Flow (see `UNITY_CONTRACT.md` for the verified protocol):
/// 1. Screen opens → Flutter loads player state (balances from the
///    server, settings + owned cars locally) and sends `SetConfig`
///    + `SetUnlockedCars` + `SetBalances` (+ `SetSelectedCar`,
///    `SetSensitivity`, `SetControlMode`). Unity sends NO ready
///    signal, so the trio is re-sent on a stagger (0.5s / 2s / 5s)
///    and again on every balance change — `SetConfig` is
///    idempotent, repeats are harmless. NO ad at game start.
/// 2. Player taps RACE in Unity's menu → Unity races → Unity sends
///    `race_result` → Flutter calls the server `claim-race-level`
///    (race id + position only; Unity's `level_coins_earned` is
///    info-only and never trusted) → Flutter refreshes balances and
///    sends `SetBalances`, and overlays the Rs line on Unity's
///    results screen ("You won 10 coins = Rs 0.10" — ResultsUI's
///    own comment says the Rs value is Flutter's job).
/// 3. Locked car tapped in Unity's garage → `car_locked_tapped` →
///    Flutter shows the unlock / Watch Ad dialog. Unlock spends Ad
///    Coins ONLY via the server (`spend-race-item`); Watch Ad sends
///    `ShowRewardedAd` to Unity, which reports
///    `rewarded_completed` with the same `requestId` — Flutter
///    claims Ad Coins server-side keyed by it.
/// 4. Back / close → `QuitToMenu` + pop.
///
/// UNITY HEARTBEAT (v1.0.33): Unity sends `menu_ready` once its
/// menu is built and `loading_progress` (0-100) as the race scene
/// loads. If neither arrives within 8 s, this screen recovers in
/// stages (delayed pause+resume → forced EmbedUnity re-attach via a
/// fresh key → a Flutter RETRY / BACK overlay) — the v1.0.32 stall
/// had no host-side recovery at all. Unity's old gaps (no subscribers
/// for `OnRewardedAdRequested` / `OnStartRaceRequested` /
/// `OnQuitToMenuRequested`, no power-up return message) were all
/// fixed 19 Nov 2026 — see UNITY_CONTRACT.md.
class TjRacingPlayScreen extends StatefulWidget {
  const TjRacingPlayScreen({
    super.key,
    required this.config,
  });

  final TjRacingConfig config;

  @override
  State<TjRacingPlayScreen> createState() => _TjRacingPlayScreenState();
}

class _TjRacingPlayScreenState extends State<TjRacingPlayScreen>
    with WidgetsBindingObserver {
  TjRacingConfig get _config => widget.config;

  RacingPlayerState? _player;
  final Set<String> _claimedRaceIds = {};
  final Set<String> _claimedRewardRequests = {};
  String? _pendingRewardRequestId;
  Timer? _rewardTimeoutTimer;
  List<Timer> _configTimers = [];
  Timer? _unfreezeTimer;

  // Unity heartbeat watchdog (v1.0.33): Unity sends `menu_ready` once
  // its menu is built and `loading_progress` as the race scene loads.
  // If neither arrives, the Unity view is treated as frozen (the
  // v1.0.32 "LOADING 1%" stall) and recovered in stages — delayed
  // pause+resume, then a forced platform-view re-attach (new EmbedUnity
  // key), then a Flutter overlay with RETRY / BACK so the user is never
  // trapped on a dead game screen.
  bool _unityReady = false;
  int _unityViewKeySeed = 0;
  int _recoveryStage = 0;
  Timer? _watchdogTimer;
  bool _loadStuck = false;
  int? _lastUnityPct;

  /// Rs overlay shown over Unity's results screen after a claim
  /// (ResultsUI: "The Rs value is FLUTTER's job"). Dismissible.
  _RsOverlayData? _rsOverlay;
  bool _claiming = false;

  double _sensitivity = RaceSettings.defaultSensitivity;
  String _controlMode = RaceSettings.defaultControlMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Landscape for the game screen (menu, splash, race) — set
    // FIRST, before the Unity view mounts, so the view is created
    // in landscape instead of rotating mid-mount. Matches Unity's
    // defaultScreenOrientation (LandscapeLeft) exactly.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
    ]);
    _loadAndSendConfig();
    // One-shot unfreeze 2 s after the screen opens: the Unity view
    // can also freeze on a visibility flicker that is NOT our rebuild
    // (e.g. the activity-resume observer firing while Unity is still
    // initialising). Same pause + resume, once, while the menu is
    // still showing — harmless if nothing froze.
    _unfreezeTimer = Timer(const Duration(seconds: 2), _unfreezeUnity);
    // Watchdog: if Unity never signals it is alive (menu_ready /
    // loading_progress), recover in stages — see _onUnityWatchdog.
    _armWatchdog();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Background -> foreground can re-trigger the plugin's surface
    // freeze (activity resume while Unity re-attaches). If Unity never
    // signalled ready, unfreeze again on return.
    if (state == AppLifecycleState.resumed && mounted && !_unityReady) {
      _unfreezeUnity();
      _armWatchdog();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final timer in _configTimers) {
      timer.cancel();
    }
    _unfreezeTimer?.cancel();
    _watchdogTimer?.cancel();
    _rewardTimeoutTimer?.cancel();
    // Safety net: if this screen is popped by any path other than
    // _leaveGame, portrait must still come back (see _leaveGame).
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  /// flutter_embed_unity freeze workaround (v1.0.32, hardened
  /// v1.0.33): the plugin's own UnityPlayerSingleton notes that a
  /// quick VISIBLE → GONE → VISIBLE flicker of the platform view
  /// (orientation change, hot reload, or a widget rebuild after
  /// mount) can leave Unity's UI frozen on its last frame while the
  /// player itself keeps running — the splash then looks stuck
  /// forever and taps do nothing visible. The plugin's documented
  /// unfreeze is pause + resume. v1.0.32 called them back-to-back in
  /// one post-frame callback, which can land before the player
  /// finishes initialising and no-op; v1.0.33 leaves a real 300 ms
  /// gap between pause and resume, and also runs this once Unity
  /// signals it is alive (menu_ready) — the point where the resume
  /// is most likely to take effect. `pauseUnity` / `resumeUnity`
  /// are top-level exports of package:flutter_embed_unity.
  void _unfreezeUnity() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      pauseUnity();
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) resumeUnity();
      });
    });
  }

  void _armWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(const Duration(seconds: 8), _onUnityWatchdog);
  }

  /// Watchdog stages (v1.0.33 — the v1.0.32 "LOADING 1%" stall had
  /// NO host-side recovery: Unity froze on frame 1 and Flutter
  /// waited forever). Each stage runs only if Unity still has not
  /// signalled it is alive.
  void _onUnityWatchdog() {
    if (!mounted || _unityReady) return;
    if (_recoveryStage == 0) {
      // Stage 1: delayed pause + resume.
      _recoveryStage = 1;
      _unfreezeUnity();
      _watchdogTimer = Timer(const Duration(seconds: 4), _onUnityWatchdog);
    } else if (_recoveryStage == 1) {
      // Stage 2: force the platform view to detach + re-attach by
      // rebuilding EmbedUnity with a fresh key — recreates the
      // UnityPlayer surface, the strongest recovery short of
      // restarting the screen.
      _recoveryStage = 2;
      setState(() => _unityViewKeySeed++);
      _watchdogTimer = Timer(const Duration(seconds: 6), _onUnityWatchdog);
    } else {
      // Stage 3: stop silent recovery — show the Flutter overlay
      // (it always renders, even if Unity is frozen) with RETRY
      // (fresh view key + fresh watchdog) and BACK.
      setState(() => _loadStuck = true);
    }
  }

  void _retryUnityLoad() {
    setState(() {
      _loadStuck = false;
      _unityReady = false;
      _recoveryStage = 0;
      _unityViewKeySeed++;
    });
    _armWatchdog();
    _unfreezeUnity();
    final player = _player;
    if (player != null) _sendFullConfig(player);
  }

  /// Unity signalled it is alive (menu_ready or loading_progress):
  /// stop all recovery, re-send the config now (Unity is definitely
  /// listening), and unfreeze once at the point where a resume is
  /// most likely to take effect.
  void _onUnityAlive() {
    if (_unityReady) return;
    _unityReady = true;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    if (_loadStuck && mounted) setState(() => _loadStuck = false);
    final player = _player;
    if (player != null) _sendFullConfig(player);
    _unfreezeUnity();
  }

  Future<void> _loadAndSendConfig() async {
    final player = await RacingPlayerState.load(
      config: _config,
      getLevelCoins: SupabaseService.getBalance,
      getAdCoins: SupabaseService.getAdCoins,
      getTotalEarned: SupabaseService.getTotalEarnedCoins,
    );
    if (!mounted) return;
    setState(() {
      _player = player;
      _sensitivity = player.sensitivity;
      _controlMode = player.controlMode;
    });
    // The setState above rebuilds the widget tree right after the
    // Unity view mounted — the visibility flicker that freezes
    // Unity's UI (see _unfreezeUnity). Unfreeze on the next frame.
    _unfreezeUnity();
    _sendFullConfig(player);
    // No ready signal from Unity: re-send on a stagger so the
    // config lands even if Unity was still loading on the first
    // send (messages to a not-yet-loaded Unity are dropped).
    _configTimers = [
      Timer(const Duration(milliseconds: 500), () {
        if (mounted) _sendFullConfig(player);
      }),
      Timer(const Duration(seconds: 2), () {
        if (mounted) _sendFullConfig(player);
      }),
      Timer(const Duration(seconds: 5), () {
        if (mounted) _sendFullConfig(player);
      }),
    ];
  }

  void _sendFullConfig(RacingPlayerState player) {
    UnityBridge.sendConfig(
      config: _config,
      level: player.level,
      levelCoins: player.levelCoins,
      adCoins: player.adCoins,
      rsValue: player.rsValue,
      totalEarnedRs: player.totalEarnedRs,
    );
    UnityBridge.sendUnlockedCars(player.unlockedCarIds);
    UnityBridge.sendSelectedCar(player.selectedCarId);
    UnityBridge.sendSensitivity(player.sensitivity);
    UnityBridge.sendControlMode(player.controlMode);
  }

  Future<void> _refreshBalancesAndSend() async {
    final player = await RacingPlayerState.load(
      config: _config,
      getLevelCoins: SupabaseService.getBalance,
      getAdCoins: SupabaseService.getAdCoins,
      getTotalEarned: SupabaseService.getTotalEarnedCoins,
    );
    if (!mounted) return;
    setState(() => _player = player);
    // Same rebuild-while-mounted trigger as the player load above
    // (a freeze here would stick the results screen instead of the
    // splash) — unfreeze on the next frame.
    _unfreezeUnity();
    UnityBridge.sendBalances(
      levelCoins: player.levelCoins,
      adCoins: player.adCoins,
      rsValue: player.rsValue,
      totalEarnedRs: player.totalEarnedRs,
    );
    // Level / unlocked cars can change after a race too.
    UnityBridge.sendConfig(
      config: _config,
      level: player.level,
      levelCoins: player.levelCoins,
      adCoins: player.adCoins,
      rsValue: player.rsValue,
      totalEarnedRs: player.totalEarnedRs,
    );
    UnityBridge.sendUnlockedCars(player.unlockedCarIds);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Rs amount without the "Rs" prefix and without trailing zeros
  /// (3700 coins -> "37", 3750 -> "37.50"), at the config rate.
  String _rsNumber(int coins) {
    final perPkr = _config.levelCoins.coinsPerPkr;
    if (perPkr <= 0) return '0';
    final rs = coins / perPkr;
    return rs == rs.roundToDouble()
        ? rs.toInt().toString()
        : rs.toStringAsFixed(2);
  }

  void _onUnityMessage(String message) {
    if (!mounted) return;
    final incoming = UnityIncoming.parse(message);
    switch (incoming.kind) {
      case UnityIncomingKind.menuReady:
        // Unity's menu is built and its Update loop is running.
        _onUnityAlive();
      case UnityIncomingKind.loadingProgress:
        // The engine is alive and the race scene is loading — also
        // a heartbeat (the % is shown in the stuck overlay if the
        // surface later freezes).
        _lastUnityPct = incoming.loadingPct;
        _onUnityAlive();
      case UnityIncomingKind.raceResult:
        _onRaceResult(incoming.raceResult!);
      case UnityIncomingKind.raceStarted:
        // Unity started a race (its own RACE button). Flutter
        // never starts races, so there is nothing to disable.
        break;
      case UnityIncomingKind.raceCancelled:
        // Player quit mid-race in Unity — Unity is back at its
        // menu; no credit, no Flutter action.
        break;
      case UnityIncomingKind.rewardedCompleted:
        _onRewardedCompleted(incoming.rewarded);
      case UnityIncomingKind.rewardedFailed:
        _clearPendingReward();
        _snack(AppLocalizations.of(context)!.tjRacingAdNotAvailable);
      case UnityIncomingKind.interstitialShown:
        // Analytics only — Unity owns race interstitials.
        debugPrint('[TJ Racing] interstitial shown');
      case UnityIncomingKind.carLockedTapped:
        if (incoming.carLocked != null) {
          _showUnlockDialog(incoming.carLocked!);
        }
      case UnityIncomingKind.powerupPurchaseRequested:
        if (incoming.powerupPurchase != null) {
          _showPowerupPurchaseDialog(incoming.powerupPurchase!);
        }
      case UnityIncomingKind.unknown:
        break;
    }
  }

  Future<void> _onRaceResult(RaceResult result) async {
    // Duplicate delivery guard (the server also dedupes per
    // race id — this only avoids a double claim ATTEMPT).
    if (_claimedRaceIds.contains(result.raceId)) return;
    // A short race (fewer laps than configured) pays nothing.
    if (result.lapsCompleted < _config.race.laps) return;
    _claimedRaceIds.add(result.raceId);
    setState(() => _claiming = true);
    try {
      final data = await SupabaseService.claimRaceLevel(
        raceId: result.raceId,
        position: result.position,
        lapsCompleted: result.lapsCompleted,
        totalRacers: result.totalRacers,
        raceTimeSecs: result.raceTimeSecs,
      );
      if (!mounted) return;
      final coins = (data['coins'] as num?)?.toInt() ??
          raceLevelCoinsForPosition(
            result.position,
            win: _config.levelCoins.win,
            second: _config.levelCoins.second,
            third: _config.levelCoins.third,
            finish: _config.levelCoins.finish,
          );
      final coinsToday = (data['coins_today'] as num?)?.toInt();
      await RaceSettings.recordRaceFinished(won: result.isWin);
      await _refreshBalancesAndSend();
      if (!mounted) return;
      setState(() {
        _claiming = false;
        // Flutter's Rs overlay on Unity's results screen
        // (ResultsUI.cs: "The Rs value is FLUTTER's job").
        _rsOverlay = _RsOverlayData(
          coins: coins,
          coinsToday: coinsToday,
          balanceCoins: _player?.levelCoins,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _claiming = false);
      _snack(
        e.toString().contains('429')
            ? AppLocalizations.of(context)!.tjRacingCapReached
            : AppLocalizations.of(context)!.tjRacingClaimFailed,
      );
    }
  }

  Future<void> _onRewardedCompleted(RewardedDetail? detail) async {
    final requestId = detail?.requestId ?? _pendingRewardRequestId;
    _clearPendingReward();
    if (requestId == null || requestId.isEmpty) {
      // Unity reported completion without an id — nothing to key
      // the server claim by; do NOT invent an idempotency key for
      // a completed view we cannot attribute.
      return;
    }
    if (_claimedRewardRequests.contains(requestId)) return;
    _claimedRewardRequests.add(requestId);
    try {
      final data = await SupabaseService.claimAdReward(
        idempotencyKey: requestId,
      );
      if (!mounted) return;
      final granted = (data['ad_coins'] as num?)?.toInt() ??
          _config.adCoins.perRewardedAd;
      await _refreshBalancesAndSend();
      if (!mounted) return;
      _snack('+$granted ${AppLocalizations.of(context)!.tjRacingAdCoins}');
    } catch (e) {
      if (!mounted) return;
      _snack(
        e.toString().contains('429')
            ? AppLocalizations.of(context)!.tjRacingCapReached
            : AppLocalizations.of(context)!.tjRacingAdNotAvailable,
      );
    }
  }

  void _clearPendingReward() {
    _pendingRewardRequestId = null;
    _rewardTimeoutTimer?.cancel();
    _rewardTimeoutTimer = null;
  }

  /// Sends `ShowRewardedAd` to Unity and waits for
  /// `rewarded_completed` / `rewarded_failed`. Times out after 30s
  /// — required because nothing in Unity subscribes to
  /// `OnRewardedAdRequested` yet (19 Nov 2026 gap), so a request
  /// may otherwise never answer.
  void _requestRewardedAd() {
    final requestId = SupabaseService.newIdempotencyKey('ad-reward');
    _pendingRewardRequestId = requestId;
    _rewardTimeoutTimer?.cancel();
    _rewardTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;
      if (_pendingRewardRequestId == requestId) {
        _clearPendingReward();
        _snack(AppLocalizations.of(context)!.tjRacingAdNotAvailable);
      }
    });
    UnityBridge.sendShowRewardedAd(requestId);
  }

  Future<void> _showUnlockDialog(CarLockedDetail locked) async {
    final t = AppLocalizations.of(context)!;
    final car = _config.carById(locked.carId);
    final price = car?.adCoinsPrice ?? locked.price;
    final name = car?.name ?? locked.carId;
    final have = _player?.adCoins ?? 0;
    final alreadyOwned =
        _player?.unlockedCarIds.contains(locked.carId) ?? false;
    if (alreadyOwned) {
      // Stale Unity state: Flutter already owns this car.
      UnityBridge.sendUnlockedCars(_player!.unlockedCarIds);
      UnityBridge.sendSelectedCar(locked.carId);
      return;
    }
    final unlock = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(name),
        content: Text(t.tjRacingUnlockPrompt(name, price, have)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.tjRacingWatchAd(_config.adCoins.perRewardedAd)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.tjRacingUnlock(price)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (unlock == null) return;
    if (!unlock) {
      // Watch Ad: Unity shows it, reports completion, Flutter
      // claims afterwards. Nothing is credited here.
      _requestRewardedAd();
      return;
    }
    try {
      await SupabaseService.spendRaceItem(
        item: 'race_car_${locked.carId}',
        adCoinsPrice: price,
      );
      await RaceSettings.addOwnedCar(locked.carId);
      await RaceSettings.setSelectedCarId(locked.carId);
      await _refreshBalancesAndSend();
      if (!mounted) return;
      UnityBridge.sendUnlockedCars(_player?.unlockedCarIds ?? {locked.carId});
      UnityBridge.sendSelectedCar(locked.carId);
      _snack(t.tjRacingUnlocked);
    } catch (e) {
      if (!mounted) return;
      _snack(
        e.toString().contains('not enough')
            ? t.tjRacingNotEnoughAdCoins
            : t.tjRacingClaimFailed,
      );
    }
  }

  /// Power-up purchase (Unity pause panel → `powerup_purchase_requested`).
  /// Shows Flutter's own dialog and spends Ad Coins ONLY via the
  /// server (`spend-race-item`, item `race_powerup_<id>` — the
  /// function generates a fresh idempotency key per call, so a
  /// retry can never double-charge). The price comes from the
  /// remote config when the power-up is known, else Unity's detail
  /// price. On a successful spend (fresh OR idempotent replay —
  /// either way the item IS granted) Flutter sends
  /// `PowerupGranted` (`UnityBridge.sendPowerupGranted`) so Unity
  /// applies the effect in the race (nitro: full meter; shield:
  /// 20 s traffic pass-through) or holds it for the next race.
  /// On ANY failed spend (402 / 409 / other) nothing is sent —
  /// nothing was granted, so Unity must apply nothing.
  Future<void> _showPowerupPurchaseDialog(
    PowerupPurchaseDetail detail,
  ) async {
    final t = AppLocalizations.of(context)!;
    final powerup = _config.powerupById(detail.powerupId);
    final price = powerup?.adCoinsPrice ?? detail.price;
    final name = powerup?.name ?? detail.powerupId;
    final have = _player?.adCoins ?? 0;
    final buy = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(name),
        content: Text(t.tjRacingPowerupPrompt(name, price, have)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.tjRacingWatchAd(_config.adCoins.perRewardedAd)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.tjRacingPowerupBuy(price)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (buy == null) return;
    if (!buy) {
      // Watch Ad: earn Ad Coins first, then the player can tap
      // the power-up again. Nothing is spent here.
      _requestRewardedAd();
      return;
    }
    try {
      await SupabaseService.spendRaceItem(
        item: racePowerupItemId(detail.powerupId),
        adCoinsPrice: price,
      );
      await _refreshBalancesAndSend();
      if (!mounted) return;
      // Success (fresh spend OR idempotent replay — the item IS
      // granted either way): tell Unity to apply the effect now.
      // Every failure path throws above and never reaches this
      // line, so a failed spend can never grant an effect.
      UnityBridge.sendPowerupGranted(detail.powerupId);
      _snack(t.tjRacingPowerupBought);
    } catch (e) {
      if (!mounted) return;
      final message = e.toString();
      if (message.contains('not enough')) {
        // 402: insufficient Ad Coins — nothing was spent.
        _snack(t.tjRacingNotEnoughAdCoins);
      } else if (message.contains('already owned')) {
        // 409: the server refused a second charge — nothing was
        // spent twice. Refresh so the shown balance is exact.
        await _refreshBalancesAndSend();
        if (!mounted) return;
        _snack(t.tjRacingPowerupAlreadyOwned);
      } else {
        _snack(t.tjRacingClaimFailed);
      }
    }
  }

  void _showSettings() {
    final t = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(t.tjRacingSettings),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.tjRacingControls),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'tilt', label: Text(t.tjRacingTilt)),
                  ButtonSegment(
                    value: 'buttons',
                    label: Text(t.tjRacingButtons),
                  ),
                  ButtonSegment(value: 'both', label: Text(t.tjRacingBoth)),
                ],
                selected: {_controlMode},
                onSelectionChanged: (selection) async {
                  final mode = selection.first;
                  await RaceSettings.setControlMode(mode);
                  UnityBridge.sendControlMode(mode);
                  setDialogState(() => _controlMode = mode);
                  if (mounted) setState(() => _controlMode = mode);
                },
              ),
              const SizedBox(height: 16),
              Text(
                '${t.tjRacingSensitivity}: ${_sensitivity.toStringAsFixed(1)}',
              ),
              Slider(
                value: _sensitivity,
                min: 0.5,
                max: 2.0,
                divisions: 15,
                label: _sensitivity.toStringAsFixed(1),
                onChanged: (value) {
                  setDialogState(() => _sensitivity = value);
                },
                onChangeEnd: (value) async {
                  await RaceSettings.setTiltSensitivity(value);
                  UnityBridge.sendSensitivity(value);
                  if (mounted) setState(() => _sensitivity = value);
                },
              ),
              const SizedBox(height: 8),
              Text(
                t.tjRacingCalibrateNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  UnityBridge.sendRecalibrateTilt();
                  _snack(t.tjRacingCalibrateNote);
                },
                child: Text(t.tjRacingRecalibrate),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t.tjRacingDone),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _leaveGame() async {
    UnityBridge.sendQuitToMenu();
    // Back to portrait BEFORE popping: Unity forced the activity to
    // landscape while the game ran, and without this the app stays
    // landscape after leaving the game (v1.0.31 bug). dispose()
    // re-asserts it as a safety net.
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    if (mounted) Navigator.of(context).pop();
  }

  Widget _rsOverlayCard(AppLocalizations t) {
    final overlay = _rsOverlay!;
    final coins = overlay.coins;
    final balance = overlay.balanceCoins;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: coins > 0
                    ? Text(
                        // Cash earning: coins AND Rs, always together.
                        t.tjRacingResultWin(
                          coins,
                          formatCoinsAsPkr(coins),
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      )
                    : Text(
                        t.tjRacingResultNoCoins,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => setState(() => _rsOverlay = null),
              ),
            ],
          ),
          if (overlay.coinsToday != null) ...[
            const SizedBox(height: 4),
            Text(
              t.tjRacingEarnedToday(
                formatCoinsAsPkr(overlay.coinsToday!),
              ),
              style: const TextStyle(color: Colors.white70),
            ),
          ],
          if (balance != null) ...[
            const SizedBox(height: 4),
            Text(
              balance >= minWithdrawalCoins
                  ? t.tjRacingWithdrawReady(formatCoinsAsPkr(balance))
                  : t.tjRacingWithdrawProgress(
                      _rsNumber(minWithdrawalCoins),
                      _rsNumber(balance),
                    ),
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) async {
        if (didPop) return;
        await _leaveGame();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_config.title),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _showSettings,
              tooltip: t.tjRacingSettings,
            ),
          ],
        ),
        body: Stack(
          children: [
            // The Unity game (MainMenu scene first; Unity switches
            // to Race_NightCity internally on RACE). One EmbedUnity
            // widget per screen (the plugin supports a single
            // instance). The key changes only when the watchdog
            // forces a platform-view re-attach (v1.0.33 recovery
            // stage 2) — never on ordinary rebuilds. No ad at game
            // start — Unity's banner shows automatically on its own
            // Ads init; race interstitials are Unity-owned (after
            // Continue, never after a win).
            EmbedUnity(
              key: ValueKey('unity-$_unityViewKeySeed'),
              onMessageFromUnity: _onUnityMessage,
            ),
            if (_rsOverlay != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _rsOverlayCard(t),
              ),
            if (_claiming)
              const Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_loadStuck)
              // Watchdog stage 3 (v1.0.33): Unity never signalled it
              // is alive. This is a Flutter overlay, so it renders
              // even if the Unity surface is frozen — the user is
              // never trapped on a dead game screen.
              Positioned.fill(
                child: Container(
                  color: Colors.black87,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Game is not loading',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _lastUnityPct != null
                              ? 'Stuck at $_lastUnityPct% — try again or go back.'
                              : 'Try again or go back.',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FilledButton(
                              onPressed: _retryUnityLoad,
                              child: const Text('RETRY'),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: _leaveGame,
                              child: const Text(
                                'BACK',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Server-confirmed race reward, for the Rs overlay on Unity's
/// results screen. All Rs strings are built by the caller with
/// `formatCoinsAsPkr` (Level Coins WITH Rs; Ad Coins never here).
class _RsOverlayData {
  const _RsOverlayData({
    required this.coins,
    this.coinsToday,
    this.balanceCoins,
  });

  final int coins;
  final int? coinsToday;
  final int? balanceCoins;
}
