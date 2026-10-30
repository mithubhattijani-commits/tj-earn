import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/supabase_service.dart';

/// Admin panel: referrals queue, referral stats and a read-only ledger
/// viewer. Three tabs; every row comes from the admin Edge Functions.
///
/// SECURITY: the server is the enforcer. The client never trusts itself —
/// a 403/503 from any admin function renders the "admin access required"
/// empty state. Approve/Reject call the existing `review-referral`
/// function, which is idempotent server-side (a replayed approval can
/// never double-credit). All strings are localized via arb keys.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.adminTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: t.adminTabReferrals),
              Tab(text: t.adminTabStats),
              Tab(text: t.adminTabLedger),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ReferralsTab(),
            _StatsTab(),
            _LedgerTab(),
          ],
        ),
      ),
    );
  }
}

/// Empty state shown when the server denies admin access (403/503) or a
/// load fails. Never shows data that was not returned by the server.
class _AdminDenied extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _AdminDenied({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.admin_panel_settings_outlined, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              '${t.adminLoggedInAs} ${SupabaseService.userEmail ?? ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 4),
            Text(
              t.adminNotAdminHint,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(t.adminRefresh),
            ),
          ],
        ),
      ),
    );
  }
}

String _statusLabel(AppLocalizations t, String status) {
  switch (status) {
    case 'approved':
      return t.referStatusApproved;
    case 'rejected':
      return t.referStatusRejected;
    case 'eligible':
      return t.referStatusEligible;
    default:
      return t.referStatusPending;
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'approved':
      return Colors.green;
    case 'rejected':
      return Colors.red;
    case 'eligible':
      return Colors.blue;
    default:
      return Colors.orange;
  }
}

String _shortDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  return iso.length >= 16 ? iso.substring(0, 16).replaceAll('T', ' ') : iso;
}

class _ReferralsTab extends StatefulWidget {
  const _ReferralsTab();

  @override
  State<_ReferralsTab> createState() => _ReferralsTabState();
}

class _ReferralsTabState extends State<_ReferralsTab> {
  static const _statuses = ['eligible', 'pending', 'approved', 'rejected', 'all'];
  String _status = 'eligible';
  late Future<Map<String, dynamic>> _future;
  final Set<String> _deciding = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = SupabaseService.listReferrals(status: _status);
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _approve(String referralId) async {
    // Capture localized strings before the async gap.
    final doneMsg = AppLocalizations.of(context)!.adminDecisionDone;
    final failMsg = AppLocalizations.of(context)!.adminDecisionFailed;
    setState(() => _deciding.add(referralId));
    try {
      await SupabaseService.reviewReferral(
        referralId: referralId,
        action: 'approve',
      );
      _snack(doneMsg);
      _reload();
    } catch (_) {
      _snack(failMsg);
    } finally {
      if (mounted) setState(() => _deciding.remove(referralId));
    }
  }

  Future<void> _reject(String referralId) async {
    final t = AppLocalizations.of(context)!;
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.adminConfirmRejectTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.adminConfirmRejectBody),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration:
                  InputDecoration(hintText: t.adminReasonHint),
              maxLength: 200,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.adminCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.adminConfirm),
          ),
        ],
      ),
    );
    final reason = reasonController.text;
    reasonController.dispose();
    if (confirmed != true || !mounted) return;
    final doneMsg = AppLocalizations.of(context)!.adminDecisionDone;
    final failMsg = AppLocalizations.of(context)!.adminDecisionFailed;
    setState(() => _deciding.add(referralId));
    try {
      await SupabaseService.reviewReferral(
        referralId: referralId,
        action: 'reject',
        reason: reason,
      );
      _snack(doneMsg);
      _reload();
    } catch (_) {
      _snack(failMsg);
    } finally {
      if (mounted) setState(() => _deciding.remove(referralId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              for (final s in _statuses)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s == 'all' ? t.adminStatusAll : _statusLabel(t, s)),
                    selected: _status == s,
                    onSelected: (_) {
                      _status = s;
                      _reload();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: FutureBuilder<Map<String, dynamic>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  final denied = snapshot.error is AdminAccessDenied;
                  return _AdminDenied(
                    message: denied
                        ? t.adminAccessRequired
                        : t.adminLoadFailed,
                    onRetry: _reload,
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator());
                }
                final rows =
                    (snapshot.data!['referrals'] as List?)
                            ?.cast<Map<String, dynamic>>() ??
                        const <Map<String, dynamic>>[];
                if (rows.isEmpty) {
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.all(48),
                      child: Center(child: Text(t.adminReferralsEmpty)),
                    ),
                  );
                }
                return ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _referralRow(t, rows[i]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _referralRow(AppLocalizations t, Map<String, dynamic> r) {
    final id = (r['id'] ?? '').toString();
    final status = (r['status'] ?? '').toString();
    final referredEmail = (r['referred_email'] ?? '').toString();
    final referrerEmail = (r['referrer_email'] ?? '').toString();
    final referrerCode = (r['referrer_code'] ?? '').toString();
    final created = _shortDate(r['created_at']?.toString());
    final busy = _deciding.contains(id);
    final color = _statusColor(status);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    referredEmail.isEmpty
                        ? t.adminUnknownUser
                        : referredEmail,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_statusLabel(t, status),
                      style: TextStyle(color: color, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${t.adminReferrer}: ${referrerEmail.isEmpty ? t.adminUnknownUser : referrerEmail}'
              '${referrerCode.isEmpty ? '' : ' · ${t.adminCode}: $referrerCode'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(created, style: Theme.of(context).textTheme.bodySmall),
            if (status == 'eligible') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : () => _reject(id),
                      child: busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2))
                          : Text(t.adminReject),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: busy ? null : () => _approve(id),
                      child: busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2))
                          : Text(t.adminApprove),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatsTab extends StatefulWidget {
  const _StatsTab();

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _future = SupabaseService.referralStats());
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final denied = snapshot.error is AdminAccessDenied;
            return _AdminDenied(
              message:
                  denied ? t.adminAccessRequired : t.adminLoadFailed,
              onRetry: _reload,
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final counts =
              (data['counts'] as Map?)?.cast<String, dynamic>() ??
                  const <String, dynamic>{};
          final totalReferrers = (data['total_referrers'] as num?)?.toInt() ?? 0;
          final coinsCredited =
              (data['total_coins_credited'] as num?)?.toInt() ?? 0;
          final cards = [
            (_statusLabel(t, 'pending'),
                (counts['pending'] as num?)?.toInt() ?? 0),
            (_statusLabel(t, 'eligible'),
                (counts['eligible'] as num?)?.toInt() ?? 0),
            (_statusLabel(t, 'approved'),
                (counts['approved'] as num?)?.toInt() ?? 0),
            (_statusLabel(t, 'rejected'),
                (counts['rejected'] as num?)?.toInt() ?? 0),
            (t.adminTotalReferrers, totalReferrers),
            (t.adminCoinsCredited, coinsCredited),
          ];
          return GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 110,
            ),
            itemCount: cards.length,
            itemBuilder: (context, i) {
              final (label, value) = cards[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$value',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall),
                      const SizedBox(height: 4),
                      Text(label,
                          style:
                              Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _LedgerTab extends StatefulWidget {
  const _LedgerTab();

  @override
  State<_LedgerTab> createState() => _LedgerTabState();
}

class _LedgerTabState extends State<_LedgerTab> {
  static const _pageSize = 50;
  int _page = 0;
  int _total = 0;
  String _typeFilter = '';
  final _typeController = TextEditingController();
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _typeController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = SupabaseService.listLedger(
        limit: _pageSize,
        offset: _page * _pageSize,
        type: _typeFilter.isEmpty ? null : _typeFilter,
      );
    });
  }

  void _applyFilter() {
    _page = 0;
    _typeFilter = _typeController.text.trim();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _typeController,
                  decoration: InputDecoration(
                    hintText: t.adminTypeFilter,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _applyFilter(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _applyFilter,
                child: Text(t.adminApplyFilter),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final denied = snapshot.error is AdminAccessDenied;
                return _AdminDenied(
                  message: denied
                      ? t.adminAccessRequired
                      : t.adminLoadFailed,
                  onRetry: _reload,
                );
              }
              if (!snapshot.hasData) {
                return const Center(
                    child: CircularProgressIndicator());
              }
              final data = snapshot.data!;
              _total = (data['total'] as num?)?.toInt() ?? 0;
              final rows =
                  (data['entries'] as List?)
                          ?.cast<Map<String, dynamic>>() ??
                      const <Map<String, dynamic>>[];
              if (rows.isEmpty) {
                return Center(child: Text(t.adminLedgerEmpty));
              }
              return ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, i) => _ledgerRow(t, rows[i]),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: t.adminPrev,
                onPressed: _page > 0
                    ? () {
                        _page--;
                        _reload();
                      }
                    : null,
              ),
              Text(t.adminPageOf(_page + 1)),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: t.adminNext,
                onPressed: (_page + 1) * _pageSize < _total
                    ? () {
                        _page++;
                        _reload();
                      }
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ledgerRow(AppLocalizations t, Map<String, dynamic> e) {
    final amount = (e['amount_coins'] as num?)?.toInt() ?? 0;
    final type = (e['type'] ?? '').toString();
    final email = (e['user_email'] ?? '').toString();
    final key = (e['idempotency_key'] ?? '').toString();
    final created = _shortDate(e['created_at']?.toString());
    final positive = amount >= 0;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    email.isEmpty ? t.adminUnknownUser : email,
                    style:
                        const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text('$type · $created',
                      style: Theme.of(context).textTheme.bodySmall),
                  if (key.isNotEmpty)
                    Text(
                      key.length > 28
                          ? '${key.substring(0, 28)}…'
                          : key,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontFamily: 'monospace'),
                    ),
                ],
              ),
            ),
            Text(
              '${positive ? '+' : '−'}$amount',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: positive ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
