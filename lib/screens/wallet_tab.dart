import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/supabase_service.dart';

/// Wallet page: server-side balance + read-only transaction history.
class WalletTab extends StatelessWidget {
  const WalletTab({super.key});

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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: SupabaseService.getLedger(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(t.genericError));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return Center(child: Text(t.historyEmpty));
        }
        return ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final row = rows[i];
            final amount = (row['amount_coins'] as num?)?.toInt() ?? 0;
            final type = (row['type'] as String?) ?? 'credit';
            final created = (row['created_at'] as String?) ?? '';
            final sign = amount >= 0 ? '+' : '';
            return ListTile(
              title: Text(_typeLabel(t, type)),
              subtitle: Text(created.length >= 16 ? created.substring(0, 16) : created),
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
    );
  }
}
