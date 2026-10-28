import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/supabase_service.dart';
import '../services/validation.dart';

/// Home dashboard: server-side balance + quick actions.
///
/// The balance shown here comes from the `get-balance` Edge Function
/// (SUM of the ledger). Nothing on this screen can change it.
class HomeTab extends StatefulWidget {
  final void Function(int tab) onNavigate;

  const HomeTab({super.key, required this.onNavigate});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late Future<int> _balance;

  @override
  void initState() {
    super.initState();
    _balance = SupabaseService.getBalance();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(t.balance,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  FutureBuilder<int>(
                    future: _balance,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Text(t.balanceLoadFailed);
                      }
                      if (!snapshot.hasData) {
                        return const CircularProgressIndicator();
                      }
                      final coins = snapshot.data!;
                      return Column(
                        children: [
                          Text(
                            '$coins',
                            style: Theme.of(context)
                                .textTheme
                                .displayMedium,
                          ),
                          Text('${t.coins} • ${formatCoinsAsPkr(coins)}'),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(t.quickActions, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => widget.onNavigate(1),
            child: Text(t.goOffers),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => widget.onNavigate(2),
            child: Text(t.goWallet),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => widget.onNavigate(3),
            child: Text(t.goWithdraw),
          ),
        ],
      ),
    );
  }
}
