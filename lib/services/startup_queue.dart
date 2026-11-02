import 'dart:async';

/// Sequential startup task queue (Jaani, 2 Nov 2026, updated: 9s gaps): after login the app
/// used to fire all server calls at once (balance, streak, onboarding,
/// admin probe, device register) — on a slow connection they piled up and
/// the phone choked (ANR). Now every startup network call goes through
/// this queue and runs ONE BY ONE with a short breathing gap between them,
/// so the UI stays responsive and each card loads gradually ("ahista
/// ahista").
///
/// Usage: StartupQueue.instance.add(() => _loadSomething());
/// High-priority work (the balance card) uses addFirst().
///
/// A task that hangs is cut off after 30s so one bad call can never stall
/// the whole queue. Task errors never escape the queue — fire-and-forget
/// loaders handle their own errors, and Completer-based loaders forward
/// them to their future.
class StartupQueue {
  StartupQueue._();

  static final StartupQueue instance = StartupQueue._();

  final List<Future<void> Function()> _queue = <Future<void> Function()>[];
  bool _running = false;

  /// Breathing gap between tasks (Jaani, 2 Nov 2026): 8-10 seconds per
  /// his spec — slow enough that a stalling connection never piles up.
  /// 3-4 calls × 9s gaps ≈ 30-35s total load time.
  static const Duration _gap = Duration(seconds: 9);

  /// Safety cap per task — a hanging call can never stall the queue.
  static const Duration _taskCap = Duration(seconds: 30);

  /// Run [task] after all previously queued tasks, one by one.
  void add(Future<void> Function() task) {
    _queue.add(task);
    unawaited(_pump());
  }

  /// Run [task] before everything else in the queue.
  void addFirst(Future<void> Function() task) {
    _queue.insert(0, task);
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final Future<void> Function() task = _queue.removeAt(0);
        try {
          await task().timeout(_taskCap);
        } catch (_) {
          // A failed/hung task must never stall the queue.
        }
        if (_queue.isNotEmpty) {
          await Future.delayed(_gap);
        }
      }
    } finally {
      _running = false;
    }
  }
}
