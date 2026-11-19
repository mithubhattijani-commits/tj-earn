import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_embed_unity/flutter_embed_unity.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../games/tj_racing/race_rewards.dart';
import '../games/tj_racing/race_settings.dart';
import '../games/tj_racing/unity_bridge.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';
import '../services/validation.dart'
    show formatCoinsAsPkr, minWithdrawalCoins;

/// TJ Racing 3D — Unity host screen (v1.0.31).
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
/// KNOWN UNITY GAPS (19 Nov 2026, Unity agent to fix — Flutter
/// implements the protocol anyway and fails soft):
/// - Nothing in Unity subscribes to `OnRewardedAdRequested`, so a
///   `ShowRewardedAd` currently produces no ad and no event.
///   Flutter times the request out after 30s ("ad not available")
///   instead of hanging.
/// - Nothing subscribes to `OnStartRaceRequested` /
///   `OnQuitToMenuRequested` (Flutter doesn't send `StartRace` in
///   v1 — Unity's own RACE button drives starts).
/// - No power-up shop UI in Unity (config + server spend are
///   ready; nothing triggers a purchase yet).
class TjRacingPlayScreen extends StatefulWidget {
  const TjRacingPlayScreen({
    super.key,
    required this.config,
  });

  final TjRacingConfig config;

  @override
  State<TjRacingPlayScreen> createState() => _TjRacingPlayScreenState();
}

class _TjRacingPlayScreenState extends State<TjRacingPlayScreen> {
  TjRacingConfig get _config => widget.config;

  RacingPlayerState? _player;
  final Set<String> _claimedRaceIds = {};
  final Set<String> _claimedRewardRequests = {};
  String? _pendingRewardRequestId;
  Timer? _rewardTimeoutTimer;
  List<Timer> _configTimers = [];

  /// Rs overlay shown over Unity's results screen after a claim
  /// (ResultsUI: "The Rs value is FLUTTER's job"). Dismissible.
  _RsOverlayData? _rsOverlay;
  bool _claiming = false;

  double _sensitivity = RaceSettings.defaultSensitivity;
  String _controlMode = RaceSettings.defaultControlMode;

  @override
  void initState() {
    super.initState();
    _loadAndSendConfig();
  }

  @override
  void dispose() {
    for (final timer in _configTimers) {
      timer.cancel();
    }
    _rewardTimeoutTimer?.cancel();
    super.dispose();
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
            // instance). No ad at game start — Unity's banner shows
            // automatically on its own Ads init; race interstitials
            // are Unity-owned (after Continue, never after a win).
            EmbedUnity(onMessageFromUnity: _onUnityMessage),
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
