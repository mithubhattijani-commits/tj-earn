import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../widgets/spin_wheel.dart';

/// Dedicated Daily Spin screen.
///
/// Wraps the [SpinWheel] widget (one free spin per day, server-picked
/// weighted reward via the `claim-spin` Edge Function) in a full page so
/// users can reach it directly from the Home rewards section.
class SpinScreen extends StatelessWidget {
  const SpinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(t.spinTitle)),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: SpinWheel(),
      ),
    );
  }
}
