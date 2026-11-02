import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// DIAGNOSTIC BUILD v1.0.18 — Balance query test (Jaani, 2 Nov 2026).
///
/// Purpose: isolate the startup ANR on Jaani's phone, one component at a time.
///
/// v1.0.16 (no plugins, no network) worked fine -> phone + framework OK.
/// v1.0.17 (Supabase init only) worked fine -> init is safe.
/// v1.0.18 adds ONLY the balance query, using the exact same pattern as
/// the real app: SupabaseService.getBalance() -> _invoke('get-balance')
/// -> client.functions.invoke with 15s hard timeout.
///
/// How to read the result:
///   * If THIS build ANRs -> the balance network call is the culprit.
///   * If it runs fine and shows "Balance: X coins" or "Balance: FAIL"
///     -> balance query is safe; next step adds the next query.
///
/// Note: no auth in this diagnostic, so get-balance may return 401
/// (JWT required). That is EXPECTED — the test is whether the call
/// completes without hanging, not whether it succeeds.
///
/// No other queries, no other plugins.
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

  // v1.0.18: add ONLY the balance query.
  // Exact pattern from SupabaseService.getBalance() on main:
  // _invoke('get-balance') -> client.functions.invoke with 15s timeout.
  String balanceStatus;
  if (!supabaseStatus.contains('OK')) {
    balanceStatus = 'Balance: SKIPPED (Supabase init failed)';
  } else {
    try {
      final res = await Supabase.instance.client.functions
          .invoke('get-balance')
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException('get-balance timed out'),
          );
      if (res.status != 200) {
        balanceStatus = 'Balance: FAIL (HTTP ${res.status})';
      } else {
        final data = res.data;
        if (data is Map && data['balance_coins'] is int) {
          balanceStatus = 'Balance: ${data['balance_coins']} coins';
        } else {
          balanceStatus = 'Balance: FAIL (unexpected response)';
        }
      }
    } catch (e) {
      final String msg = e.toString().split('\n').first;
      balanceStatus =
          msg.length > 80 ? 'Balance: FAIL (${msg.substring(0, 80)}...)' : 'Balance: FAIL ($msg)';
    }
  }

  runApp(DiagnosticApp(
    supabaseStatus: supabaseStatus,
    balanceStatus: balanceStatus,
  ));
}

class DiagnosticApp extends StatelessWidget {
  final String supabaseStatus;
  final String balanceStatus;
  const DiagnosticApp({
    super.key,
    required this.supabaseStatus,
    required this.balanceStatus,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TJ Earn (Diagnostic)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF111111),
      ),
      home: DiagnosticHome(
        supabaseStatus: supabaseStatus,
        balanceStatus: balanceStatus,
      ),
    );
  }
}

class DiagnosticHome extends StatefulWidget {
  final String supabaseStatus;
  final String balanceStatus;
  const DiagnosticHome({
    super.key,
    required this.supabaseStatus,
    required this.balanceStatus,
  });

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
    final bool balanceOk =
        widget.balanceStatus.startsWith('Balance: ') &&
        !widget.balanceStatus.contains('FAIL') &&
        !widget.balanceStatus.contains('SKIPPED');
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
                  'DIAGNOSTIC BUILD 1.0.18',
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
                const SizedBox(height: 4),
                Text(
                  widget.balanceStatus,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: balanceOk ? Colors.greenAccent : Colors.orangeAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Balance query only (get-balance). No other queries,\n'
                  'no other plugins. If this hangs, the balance\n'
                  'network call is the cause.',
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
