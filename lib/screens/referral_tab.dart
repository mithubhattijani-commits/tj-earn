import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/supabase_service.dart';
import '../services/validation.dart';

/// Refer & Earn: code display, share link, stats, how-it-works, history.
///
/// All data comes from the `get-referral` Edge Function. Coins are shown
/// only — never rupees. Applying a code calls `apply-referral`; every rule
/// (self-referral, duplicates, rate limits) is enforced server-side.
class ReferralTab extends StatefulWidget {
  const ReferralTab({super.key});

  @override
  State<ReferralTab> createState() => _ReferralTabState();
}

class _ReferralTabState extends State<ReferralTab> {
  late Future<Map<String, dynamic>> _info;
  final _codeController = TextEditingController();
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _info = SupabaseService.getReferral();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _info = SupabaseService.getReferral());

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _copy(String text) async {
    // Capture before the async gap (analyzer: use_build_context_synchronously).
    final copiedMsg = AppLocalizations.of(context)!.referCopied;
    await Clipboard.setData(ClipboardData(text: text));
    _snack(copiedMsg);
  }

  /// System share sheet; falls back to clipboard when unavailable.
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
      await SupabaseService.applyReferral(code);
      _codeController.clear();
      _snack(t.referApplied);
      _reload();
    } catch (e) {
      _snack(_friendlyError(t, e.toString()));
    } finally {
      if (mounted) setState(() => _applying = false);
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
              return _ErrorBlock(
                message: t.referLoadFailed,
                onRetry: _reload,
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
            final pending = (info['pending'] as num?)?.toInt() ?? 0;
            final approved = (info['approved'] as num?)?.toInt() ?? 0;
            final history =
                (info['history'] as List?)?.cast<Map<String, dynamic>>() ??
                    const <Map<String, dynamic>>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _codeCard(t, code, link),
                const SizedBox(height: 16),
                _statsRow(t, total, pending, approved),
                const SizedBox(height: 16),
                // Referral milestone tiers (Attapoll-style)
                _MilestoneCard(approved: approved),
                const SizedBox(height: 16),
                _howCard(t),
                const SizedBox(height: 16),
                _applyCard(t),
                const SizedBox(height: 16),
                _historyCard(t, history),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _codeCard(AppLocalizations t, String code, String link) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.referTitle,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(t.referSubtitle),
            const SizedBox(height: 16),
            Text(t.referYourCode,
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      code,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: t.referCopy,
                    onPressed: () => _copy(code),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(t.referYourLink,
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            SelectableText(link,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(t.referCopy),
                    onPressed: () => _copy(link),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.share, size: 18),
                    label: Text(t.referShare),
                    onPressed: () => _share(link),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statsRow(AppLocalizations t, int total, int pending, int approved) {
    return Row(
      children: [
        Expanded(child: _stat(t.referTotal, total)),
        const SizedBox(width: 12),
        Expanded(child: _stat(t.referPending, pending)),
        const SizedBox(width: 12),
        Expanded(child: _stat(t.referApproved, approved)),
      ],
    );
  }

  Widget _stat(String label, int value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text('$value',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(label,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _howCard(AppLocalizations t) {
    final steps = [t.referHow1, t.referHow2, t.referHow3, t.referHow4];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.referHowTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i + 1}. ',
                        style:
                            const TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(child: Text(steps[i])),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                t.referRewardNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _applyCard(AppLocalizations t) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.referApplyTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _codeController,
              decoration: InputDecoration(
                hintText: t.referApplyHint,
                border: const OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _applying ? null : _applyCode,
              child: _applying
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child:
                          CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(t.referApplyButton),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyCard(AppLocalizations t, List<Map<String, dynamic>> history) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.referHistoryTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(t.referHistoryEmpty),
              )
            else
              for (final h in history) _historyRow(t, h),
          ],
        ),
      ),
    );
  }

  Widget _historyRow(AppLocalizations t, Map<String, dynamic> h) {
    final status = (h['status'] ?? '').toString();
    final role = (h['role'] ?? '').toString();
    final masked = (h['other_masked'] ?? '').toString();
    String statusLabel;
    Color statusColor;
    switch (status) {
      case 'approved':
        statusLabel = t.referStatusApproved;
        statusColor = Colors.green;
        break;
      case 'rejected':
        statusLabel = t.referStatusRejected;
        statusColor = Colors.red;
        break;
      case 'eligible':
        statusLabel = t.referStatusEligible;
        statusColor = Colors.blue;
        break;
      default:
        statusLabel = t.referStatusPending;
        statusColor = Colors.orange;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${role == 'referrer' ? t.referYouInvited : t.referInvitedYou}: $masked',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                Text(
                  (h['created_at'] ?? '').toString().substring(0, 10),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(statusLabel,
                style: TextStyle(color: statusColor, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBlock({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

/// Referral milestone tier card.
///
/// Shows progress to the next milestone (5/10/25 approved referrals)
/// and triggers the milestone check. Bonuses are paid server-side.
class _MilestoneCard extends StatefulWidget {
  final int approved;

  const _MilestoneCard({required this.approved});

  @override
  State<_MilestoneCard> createState() => _MilestoneCardState();
}

class _MilestoneCardState extends State<_MilestoneCard> {
  Map<String, dynamic>? _milestone;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final result = await SupabaseService.checkReferralMilestone();
      if (mounted) {
        setState(() {
          _milestone = result;
          _checking = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final next = _milestone?['next_milestone'] as Map<String, dynamic>?;
    final bonus = _milestone?['bonus_coins'] as int? ?? 0;

    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events,
                    color: Colors.amber.shade700, size: 28),
                const SizedBox(width: 12),
                Text(
                  t.referralMilestoneTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (bonus > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  t.referralMilestoneReached(bonus.toString()),
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (next != null)
              Text(
                t.referralMilestoneNext(
                  (next['remaining'] as int).toString(),
                  (next['bonus'] as int).toString(),
                ),
              )
            else
              Text(
                t.referralMilestoneReached(''),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (_checking)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
