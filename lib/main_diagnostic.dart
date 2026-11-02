import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// DIAGNOSTIC BUILD v1.0.17 — Supabase init test (Jaani, 2 Nov 2026).
///
/// Purpose: isolate the startup ANR on Jaani's phone, one component at a time.
///
/// v1.0.16 (no plugins, no network) worked fine -> phone + framework OK.
/// v1.0.17 adds ONLY Supabase.initialize(), replicating the real app's
/// exact pattern (15s timeout, same as SupabaseService.init on main).
///
/// How to read the result:
///   * If THIS build ANRs -> Supabase.initialize() is the culprit
///     (likely a native-side block during plugin init).
///   * If it runs fine and shows "Supabase: OK" -> init is safe;
///     next step adds actual queries.
///
/// No queries, no auth, no other plugins. No network calls except what
/// Supabase.initialize() itself does internally.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String supabaseStatus;
  try {
    // Exact pattern from SupabaseService.init() on main:
    // 15s hard cap so main() never waits forever.
    await Supabase.initialize(
      url: const String.fromEnvironment('SUPABASE_URL'),
      publishableKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException('Supabase init timed out'),
    );
    supabaseStatus = 'Supabase: OK (initialized)';
  } catch (e) {
    final String msg = e.toString().split('\n').first;
    supabaseStatus =
        msg.length > 80 ? 'Supabase: FAIL (${msg.substring(0, 80)}...)' : 'Supabase: FAIL ($msg)';
  }

  runApp(DiagnosticApp(supabaseStatus: supabaseStatus));
}

class DiagnosticApp extends StatelessWidget {
  final String supabaseStatus;
  const DiagnosticApp({super.key, required this.supabaseStatus});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TJ Earn (Diagnostic)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF111111),
      ),
      home: DiagnosticHome(supabaseStatus: supabaseStatus),
    );
  }
}

class DiagnosticHome extends StatefulWidget {
  final String supabaseStatus;
  const DiagnosticHome({super.key, required this.supabaseStatus});

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
      SnackBar(content: Text('$what — diagnostic mode, no backend calls')),
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
    final bool supabaseOk = widget.supabaseStatus.contains('OK');
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
                  'DIAGNOSTIC BUILD 1.0.17',
                  style: TextStyle(
                    color: Color(0xFFD4AF37),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.supabaseStatus,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: supabaseOk ? Colors.greenAccent : Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Supabase init only. No queries, no other plugins.\n'
                  'If this hangs, Supabase.initialize() is the cause.',
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
        '$label\n(diagnostic mode \u2014 no backend calls)',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.grey, fontSize: 16),
      ),
    );
  }
}
