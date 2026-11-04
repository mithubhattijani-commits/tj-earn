import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/supabase_service.dart';
import '../services/startup_bundle_service.dart';
import '../services/validation.dart';

/// SIMPLE Refer & Earn (Jaani, 3 Nov 2026 — v1.0.18).
///
/// Kept deliberately small to avoid ANR risk:
/// - Your referral code + share link (copy / share sheet)
/// - Apply-a-code field (for invited users)
/// - Direct referrals: simple count + flat list (no multi-level depth)
/// - Pending bonuses with a single CLAIM ALL button
///
/// All data from the `get-referral` Edge Function. Every network call is
/// bounded by the service `_guard` timeout — no infinite spinners.
class ReferralTab extends StatefulWidget {
  const ReferralTab({super.key});

  @override
  State<ReferralTab> createState() => _ReferralTabState();
}

class _ReferralTabState extends State<ReferralTab> {
  late Future<Map<String, dynamic>> _info;
  final _codeController = TextEditingController();
  bool _applying = false;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _info = SupabaseService.getReferral().timeout(
      const Duration(seconds: 25),
      onTimeout: () => throw Exception('timeout'),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _reload() => setState(
        () => _info = SupabaseService.getReferral().timeout(
          const Duration(seconds: 25),
          onTimeout: () => throw Exception('timeout'),
        ),
      );

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showGuide(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                      child: Text(t.referHowTitle,
                          style: Theme.of(context).textTheme.titleMedium)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.network(
                  StartupBundleService.referralGuideUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const Padding(
                          padding: EdgeInsets.all(48),
                          child:
                              Center(child: CircularProgressIndicator())),
                  errorBuilder: (context, error, stackTrace) => Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(t.referLoadFailed),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(String text) async {
    final copiedMsg = AppLocalizations.of(context)!.referCopied;
    await Clipboard.setData(ClipboardData(text: text));
    _snack(copiedMsg);
  }

  Future<void> _share(String link) async {
    final t = AppLocalizations.of(context)!;
    final text = '${t.referShareText} $link';
    try {
      await Share.share(text);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      _snack(t.referCopied);
    }
  }

  String _friendlyError(AppLocalizations t, String raw) {
    if (raw.contains('self referral')) return t.referErrSelf;
    if (raw.contains('referrer already set')) return t.referErrDuplicate;
    if (raw.contains('invalid code')) return t.referErrInvalid;
    if (raw.contains('rate limited')) return t.referErrRate;
    return t.genericError;
  }

  Future<void> _applyCode() async {
    final t = AppLocalizations.of(context)!;
    final code = _codeController.text.trim().toUpperCase();
    if (!isValidReferralCode(code)) {
      _snack(t.referErrInvalid);
      return;
    }
    setState(() => _applying = true);
    try {
      await SupabaseService.applyReferral(code).timeout(
        const Duration(seconds: 25),
      );
      _codeController.clear();
      _snack(t.referApplied);
      _reload();
    } catch (e) {
      _snack(_friendlyError(t, e.toString()));
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _claimAll() async {
    final t = AppLocalizations.of(context)!;
    setState(() => _claiming = true);
    try {
      final res = await SupabaseService.claimReferralBonuses().timeout(
        const Duration(seconds: 25),
      );
      final coins = (res['coins'] as num?)?.toInt() ?? 0;
      _snack('${t.bonusClaimed} (+$coins)');
      _reload();
    } catch (_) {
      _snack(t.bonusClaimFailed);
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _info,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  children: [
                    Text(t.referLoadFailed),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _reload,
                      child: Text(t.retry),
                    ),
                  ],
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final info = snapshot.data!;
            final code = (info['code'] ?? '').toString();
            final link = (info['link'] ?? '').toString().isNotEmpty
                ? (info['link'] as String)
                : buildReferralLink(code);
            final total = (info['total'] as num?)?.toInt() ?? 0;
            final history = (info['history'] as List?)
                    ?.cast<Map<String, dynamic>>() ??
                const <Map<String, dynamic>>[];
            final pendingBonuses = (info['pending_bonuses'] as List?)
                    ?.cast<Map<String, dynamic>>() ??
                const <Map<String, dynamic>>[];
            final pendingTotal =
                (info['pending_total'] as num?)?.toInt() ?? 0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Rewards guide (Jaani, 4 Nov 2026): image URL comes from
                // the startup bundle (server-driven), so the guide can
                // change without an app update.
                Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _showGuide(context),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(t.referHowTitle,
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              StartupBundleService.referralGuideUrl,
                              fit: BoxFit.fitWidth,
                              loadingBuilder: (context, child, progress) =>
                                  progress == null
                                      ? child
                                      : const SizedBox(
                                          height: 220,
                                          child: Center(
                                              child:
                                                  CircularProgressIndicator())),
                              errorBuilder: (context, error, stackTrace) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Your code card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.referYourCode,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          code,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _copy(code),
                                icon: const Icon(Icons.copy, size: 18),
                                label: Text(t.referCopy),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _share(link),
                                icon: const Icon(Icons.share, size: 18),
                                label: Text(t.referShare),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Pending bonuses with CLAIM ALL
                if (pendingBonuses.isNotEmpty) ...[
                  Card(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.4),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.pendingBonuses,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$pendingTotal ${t.coins}',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _claiming ? null : _claimAll,
                            child: _claiming
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(t.claimAll),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Apply a code (invited users)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.referApplyTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _codeController,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 8,
                          decoration: InputDecoration(
                            hintText: t.referApplyHint,
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _applying ? null : _applyCode,
                          child: _applying
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(t.referApplyButton),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Direct referrals — simple flat list
                Text(
                  '${t.referHistoryTitle} ($total)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (history.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(t.referHistoryEmpty),
                  )
                else
                  ...history.take(50).map((h) {
                    final name = (h['name'] ??
                            h['display_name'] ??
                            t.referYouInvited)
                        .toString();
                    final coins = (h['coins'] as num?)?.toInt();
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.person_add_outlined),
                        title: Text(name),
                        trailing: coins != null && coins > 0
                            ? Text(
                                '+$coins',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }
}
