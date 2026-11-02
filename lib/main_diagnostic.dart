import 'package:flutter/material.dart';

/// DIAGNOSTIC BUILD — "bilkul khali app" (Jaani, 2 Nov 2026).
///
/// Purpose: isolate the startup ANR on Jaani's phone.
///
/// This entry point:
///   * calls runApp() SYNCHRONOUSLY — zero awaits before the first frame,
///   * initializes NO plugins (no Supabase, Firebase, Unity Ads, AdMob,
///     SharedPreferences, webview, device_info, url_launcher, share_plus),
///   * makes NO network calls,
///   * renders a static TJ Earn look-alike (dark + gold) with hardcoded
///     dummy data.
///
/// How to read the result:
///   * If THIS build ANRs on Jaani's phone -> the cause is the phone or the
///     Flutter framework itself, not our code.
///   * If it runs fine -> we add components back one by one to find the
///     culprit.
///
/// This file intentionally imports ONLY package:flutter/material.dart.
void main() {
  runApp(const DiagnosticApp());
}

class DiagnosticApp extends StatelessWidget {
  const DiagnosticApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TJ Earn (Diagnostic)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF111111),
      ),
      home: const DiagnosticHome(),
    );
  }
}

class DiagnosticHome extends StatefulWidget {
  const DiagnosticHome({super.key});

  @override
  State<DiagnosticHome> createState() => _DiagnosticHomeState();
}

class _DiagnosticHomeState extends State<DiagnosticHome> {
  int _tab = 0;

  static const List<String> _labels = <String>[
    'Home',
    'Refer',
    'Rewards',
    'Wallet',
    'Withdraw',
    'Settings',
  ];

  static const List<IconData> _icons = <IconData>[
    Icons.home,
    Icons.person_add,
    Icons.card_giftcard,
    Icons.account_balance_wallet,
    Icons.payments,
    Icons.settings,
  ];

  void _diagSnack(String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what — diagnostic mode, no backend')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TJ Earn'),
        backgroundColor: const Color(0xFF111111),
        elevation: 0,
      ),
      body: _tab == 0 ? _homeBody() : _placeholderBody(_labels[_tab]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF1A1A1A),
        selectedItemColor: const Color(0xFFD4AF37),
        unselectedItemColor: Colors.grey,
        onTap: (int i) => setState(() => _tab = i),
        items: <BottomNavigationBarItem>[
          for (int i = 0; i < _labels.length; i++)
            BottomNavigationBarItem(icon: Icon(_icons[i]), label: _labels[i]),
        ],
      ),
    );
  }

  Widget _homeBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _balanceCard(),
        const SizedBox(height: 16),
        _getStartedCard(),
        const SizedBox(height: 16),
        Card(
          color: const Color(0xFF1A2340),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: <Widget>[
                const Text(
                  'DIAGNOSTIC BUILD 1.0.16',
                  style: TextStyle(
                    color: Color(0xFFD4AF37),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'No plugins. No network. Static UI only.\n'
                  'If this hangs, the phone/framework is the cause.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => _diagSnack('Tap test'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Tap test'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _balanceCard() {
    return Card(
      color: const Color(0xFF1A2340),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF3A3A5A)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: <Widget>[
            Text('Balance', style: TextStyle(color: Colors.grey, fontSize: 18)),
            SizedBox(height: 8),
            Text(
              '10',
              style: TextStyle(
                color: Color(0xFFD4AF37),
                fontSize: 56,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text('coins', style: TextStyle(color: Colors.grey, fontSize: 16)),
            SizedBox(height: 4),
            Text(
              '\u2248 Rs 0.10',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _getStartedCard() {
    const List<Map<String, Object>> tasks = <Map<String, Object>>[
      {'icon': Icons.person, 'label': 'Set your display name'},
      {'icon': Icons.check_circle, 'label': 'Complete your first check-in'},
      {'icon': Icons.quiz, 'label': 'Complete your first quiz'},
      {'icon': Icons.casino, 'label': 'Try your first spin'},
      {'icon': Icons.share, 'label': 'Share your referral link'},
    ];
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF8A6D1C), Color(0xFF5E4A12)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Get Started - Earn 100 Bonus!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Complete these tasks to earn your welcome bonus',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          const Text(
            '0/5 completed',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(
              value: 0,
              backgroundColor: Colors.black26,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 12),
          for (final Map<String, Object> t in tasks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.radio_button_unchecked,
                      color: Colors.white70),
                  const SizedBox(width: 12),
                  Icon(t['icon']! as IconData,
                      color: Colors.white54, size: 20),
                  const SizedBox(width: 12),
                  Text(t['label']! as String,
                      style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholderBody(String label) {
    return Center(
      child: Text(
        '$label\n(diagnostic mode \u2014 no backend)',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.grey, fontSize: 16),
      ),
    );
  }
}
