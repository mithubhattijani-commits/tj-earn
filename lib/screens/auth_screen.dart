import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Email + password login and registration.
///
/// Registration only creates the auth user. The matching `profiles` row is
/// created by a database trigger (see the SQL migration), never by the app
/// writing profile data it could tamper with.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  var _registerMode = false;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (_registerMode) {
        await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'display_name': _name.text.trim()},
        );
      } else {
        await auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException {
      setState(() {
        _error = _registerMode ? t.registerFailed : t.loginFailed;
      });
    } catch (_) {
      setState(() => _error = t.genericError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(t.appTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _registerMode ? t.register : t.login,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            if (_registerMode) ...[
              TextField(
                controller: _name,
                decoration: InputDecoration(labelText: t.displayName),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: t.email),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(labelText: t.password),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_registerMode ? t.registerButton : t.loginButton),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _registerMode = !_registerMode),
              child: Text(_registerMode ? t.haveAccount : t.noAccount),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
