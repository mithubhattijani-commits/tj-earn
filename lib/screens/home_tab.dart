import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/supabase_service.dart';

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
                          // Coins only — no rupee conversion on the
                          // dashboard (Jaani, 29 Oct 2026).
                          Text(t.coins),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => widget.onNavigate(1),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(
                      Icons.group_add,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.referTitle,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(t.referSubtitle),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(t.quickActions, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => widget.onNavigate(2),
            child: Text(t.goOffers),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => widget.onNavigate(3),
            child: Text(t.goWallet),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => widget.onNavigate(4),
            child: Text(t.goWithdraw),
          ),
        ],
      ),
    );
  }
}
