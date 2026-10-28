import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

/// Rewards & offers page (Stage 1 structure).
///
/// Deliberately honest: Stage 1 has no providers connected, so this screen
/// shows an empty state instead of fake offers. Stage 2 wires Unity Offerwall
/// and AdGem here.
class OffersTab extends StatelessWidget {
  const OffersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(t.offersEmpty, textAlign: TextAlign.center),
      ),
    );
  }
}
