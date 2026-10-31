import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin_screen.dart';

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
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminScreen()),
          ),
          icon: const Icon(Icons.admin_panel_settings_outlined),
          label: Text(t.adminTitle),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => Supabase.instance.client.auth.signOut(),
          child: Text(t.logout),
        ),
        const SizedBox(height: 24),
        Text(t.helpSupport, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.support_agent),
            title: Text(t.helpSupportName),
            subtitle: const Text('WhatsApp'),
            trailing: const Icon(Icons.chat),
            onTap: () async {
              final uri = Uri.parse('https://wa.me/923090808180');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ),
      ],
    );
  }
}
