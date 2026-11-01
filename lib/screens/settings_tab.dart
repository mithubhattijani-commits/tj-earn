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
        const SizedBox(height: 24),
        Text(t.about, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const AdvertisingBanner(),
      ],
    );
  }
}

/// In-app advertising banner (Jaani, 2 Nov 2026): placed in the About
/// section of Settings. Tapping opens a WhatsApp chat with Nigraan TV
/// for ad bookings.
class AdvertisingBanner extends StatelessWidget {
  const AdvertisingBanner({super.key});

  static const String _waUrl = 'https://wa.me/923090808180';

  Future<void> _openWhatsApp() async {
    final uri = Uri.parse(_waUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 3,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: _openWhatsApp,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF0F2027),
                Color(0xFF203A43),
                Color(0xFF2C5364),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/jaani_ad_banner.jpg',
                  width: 84,
                  height: 112,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'For Advertising',
                      style: TextStyle(
                        color: Color(0xFFFFD76A),
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Contact Us on WhatsApp:',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.chat,
                            color: Color(0xFF25D366), size: 18),
                        SizedBox(width: 6),
                        Text(
                          '03090808180',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
