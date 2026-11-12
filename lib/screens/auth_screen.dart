import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

import '../services/referral_deep_link_service.dart';
import '../services/validation.dart';


/// Email + password login and registration.
///
/// Registration only creates the auth user. The matching `profiles` row is
/// created by a database trigger (see the SQL migration), never by the app
/// writing profile data it could tamper with.
///
/// Daily upgrade, 3 Nov 2026 (Shami): password visibility toggle — users
/// kept mistyping passwords with no way to verify (the #1 friction point
/// on the login screen).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});


  @override
  State<AuthScreen> createState() => _AuthScreenState();
}


class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _referralCode = TextEditingController();
  var _registerMode = false;
  var _busy = false;
  var _obscurePassword = true;
  String? _error;


  @override
  void initState() {
    super.initState();
    _prefillReferralCode();
  }


  /// Task E (12 Nov 2026): prefill the referral field from the pending
  /// code (deep link / deferred /api/ref/match) or the clipboard, so a
  /// user who copied a code from the website does not have to retype it.
  /// Runs once when the screen appears; the user can still edit it.
  Future<void> _prefillReferralCode() async {
    try {
      final service = ReferralDeepLinkService.instance;
      var code = await service.getPendingCode();
      code ??= await service.checkDeferredReferral();
      if (code == null && !kIsWeb) {
        code = await service.readClipboardReferralCode();
      }
      final matched = code;
      if (matched != null && mounted && _referralCode.text.isEmpty) {
        setState(() => _referralCode.text = matched);
      }
    } catch (_) {
      // Best-effort prefill: leave the field empty on failure.
    }
  }


  /// Task E: stores the referral code entered (or prefilled) in this form
  /// as pending, so MainShell's post-sign-in auto-apply picks it up via
  /// the deployed apply-referral function (immediate credit). Called
  /// after a successful sign-up only. Never throws.
  Future<void> _saveReferralCode() async {
    try {
      final code = _referralCode.text.trim().toUpperCase();
      if (code.isEmpty) return;
      if (!isValidReferralCode(code)) return;
      await ReferralDeepLinkService.instance.savePendingCode(code);
    } catch (_) {}
  }


  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _referralCode.dispose();
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
        // Task E: remember the referral code from this form so it is
        // auto-applied after sign-in (see _saveReferralCode).
        await _saveReferralCode();
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


  Future<void> _forgotPassword() async {
    final t = AppLocalizations.of(context)!;
    final emailCtrl = TextEditingController(text: _email.text.trim());
    var sending = false;
    String? msg;
    var sent = false;


    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(t.forgotPasswordTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.forgotPasswordHint),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                enabled: !sent,
                decoration: InputDecoration(labelText: t.email),
              ),
              if (msg != null) ...[
                const SizedBox(height: 12),
                Text(
                  msg!,
                  style: TextStyle(
                    color: sent ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t.backToLogin),
            ),
            if (!sent)
              FilledButton(
                onPressed: sending
                    ? null
                    : () async {
                        final email = emailCtrl.text.trim();
                        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                            .hasMatch(email)) {
                          setDlg(() => msg = t.invalidEmail);
                          return;
                        }
                        setDlg(() {
                          sending = true;
                          msg = null;
                        });
                        try {
                          await Supabase.instance.client.auth
                              .resetPasswordForEmail(email);
                          setDlg(() {
                            sent = true;
                            msg = t.forgotPasswordSent;
                          });
                        } on AuthException {
                          setDlg(() => msg = t.genericError);
                        } catch (_) {
                          setDlg(() => msg = t.genericError);
                        } finally {
                          setDlg(() => sending = false);
                        }
                      },
                child: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(t.sendResetLink),
              ),
          ],
        ),
      ),
    );
    emailCtrl.dispose();
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
              // Referral code (Task E, 12 Nov 2026): optional. Prefilled
              // from a referral link, deferred match or the clipboard.
              TextField(
                controller: _referralCode,
                textCapitalization: TextCapitalization.characters,
                maxLength: 8,
                decoration: InputDecoration(
                  labelText: t.referApplyTitle,
                  hintText: t.referApplyHint,
                  counterText: '',
                ),
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
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: t.password,
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show' : 'Hide',
                  icon: Icon(_obscurePassword
                      ? Icons.visibility
                      : Icons.visibility_off),
                  onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_registerMode ? t.registerButton : t.loginButton),
            ),
            if (!_registerMode)
              TextButton(
                onPressed: _busy ? null : _forgotPassword,
                child: Text(t.forgotPassword),
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
