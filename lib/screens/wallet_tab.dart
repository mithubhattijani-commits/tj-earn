import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/supabase_service.dart';

/// Wallet page: server-side balance + read-only transaction history.
///
/// History can be filtered (all / credits / withdrawals) and supports
/// pull-to-refresh. Read-only: no coin grants ever happen client-side.
class WalletTab extends StatefulWidget {
  /// Navigates to the Offers tab so the empty-state CTA can send new users
  /// to earn. Null keeps the old plain empty state.
  final void Function()? onEarnTap;

  const WalletTab({super.key, this.onEarnTap});

  @override
  State<WalletTab> createState() => _WalletTabState();
}

enum _HistoryFilter { all, credit, withdrawal }

class _WalletTabState extends State<WalletTab> {
  late Future<List<Map<String, dynamic>>> _ledger;
  _HistoryFilter _filter = _HistoryFilter.all;

  @override
  void initState() {
    super.initState();
    _ledger = SupabaseService.getLedger();
  }

  Future<void> _reload() async {
    setState(() => _ledger = SupabaseService.getLedger());
    await _ledger;
  }

  String _typeLabel(AppLocalizations t, String type) {
    switch (type) {
      case 'offer':
        return t.typeOffer;
      case 'withdrawal':
        return t.typeWithdrawal;
      default:
        return t.typeCredit;
    }
  }

  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> rows) {
    switch (_filter) {
      case _HistoryFilter.credit:
        return rows
            .where((Map<String, dynamic> r) =>
                ((r['amount_coins'] as num?)?.toInt() ?? 0) > 0)
            .toList();
      case _HistoryFilter.withdrawal:
        return rows
            .where((Map<String, dynamic> r) =>
                ((r['amount_coins'] as num?)?.toInt() ?? 0) < 0)
            .toList();
      case _HistoryFilter.all:
        return rows;
    }
  }

  Widget _filterChips(AppLocalizations t) {
    final List<(_HistoryFilter, String)> options = <(_HistoryFilter, String)>[
      (_HistoryFilter.all, t.adminStatusAll),
      (_HistoryFilter.credit, t.typeCredit),
      (_HistoryFilter.withdrawal, t.typeWithdrawal),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Wrap(
        spacing: 8,
        children: [
          for (final option in options)
            FilterChip(
              label: Text(option.$2),
              selected: _filter == option.$1,
              onSelected: (bool selected) {
                if (selected) setState(() => _filter = option.$1);
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Column(
      children: [
        _filterChips(t),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _ledger,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(child: Text(t.genericError)),
                      ),
                    ],
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator());
                }
                final rows = _applyFilter(snapshot.data!);
                if (rows.isEmpty) {
                  return ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 64,
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              t.historyEmpty,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall,
                            ),
                            if (widget.onEarnTap != null) ...[
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: widget.onEarnTap,
                                icon: const Icon(
                                    Icons.card_giftcard),
                                label: Text(t.goOffers),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                }
                return ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    final amount =
                        (row['amount_coins'] as num?)?.toInt() ?? 0;
                    final type = (row['type'] as String?) ?? 'credit';
                    final created = (row['created_at'] as String?) ?? '';
                    final sign = amount >= 0 ? '+' : '';
                    return ListTile(
                      title: Text(_typeLabel(t, type)),
                      subtitle: Text(created.length >= 16
                          ? created.substring(0, 16)
                          : created),
                      trailing: Text(
                        '$sign$amount',
                        style: TextStyle(
                          color: amount >= 0 ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
