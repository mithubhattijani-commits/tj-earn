import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Settings: language switch (persisted) + logout.
///
/// The language choice is saved locally and, when signed in, also written
/// to the user's `profiles.language_pref` row (best effort; a failure here
/// never blocks the local switch).
class SettingsTab extends StatelessWidget {
  final Locale locale;
  final void Function(Locale locale) onLocaleChanged;

  const SettingsTab({
    super.key,
    required this.locale,
    required this.onLocaleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(t.language, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        DropdownButton<Locale>(
          value: locale,
          items: const [
            DropdownMenuItem(value: Locale('en'), child: Text('English')),
            DropdownMenuItem(value: Locale('ur'), child: Text('اردو')),
          ],
          onChanged: (v) {
            if (v == null) return;
            onLocaleChanged(v);
            final user = Supabase.instance.client.auth.currentUser;
            if (user != null) {
              Supabase.instance.client
                  .from('profiles')
                  .update({'language_pref': v.languageCode})
                  .eq('id', user.id)
                  .then((_) {});
            }
          },
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Supabase.instance.client.auth.signOut(),
          child: Text(t.logout),
        ),
      ],
    );
  }
}
