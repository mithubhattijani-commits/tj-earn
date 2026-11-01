import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/supabase_service.dart';
import '../services/validation.dart';

/// Withdrawal request form + the user's own request list.
///
/// The form validates locally for instant feedback, but the Edge Function
/// re-validates everything (minimum, balance, pending cap) before storing
/// the request as `pending`. The app never sets a request's status.
class WithdrawTab extends StatefulWidget {
  const WithdrawTab({super.key});

  @override
  State<WithdrawTab> createState() => _WithdrawTabState();
}

class _WithdrawTabState extends State<WithdrawTab> {
  final _account = TextEditingController();
  final _amountPkr = TextEditingController();
  var _rail = 'jazzcash';
  var _busy = false;
  String? _message;
  var _messageIsError = false;
  var _listKey = 0;

  @override
  void dispose() {
    _account.dispose();
    _amountPkr.dispose();
    super.dispose();
  }

  String _errorText(AppLocalizations t, String key) {
    switch (key) {
      case 'amount_positive':
        return t.errAmountPositive;
      case 'amount_min':
        return t.errAmountMin;
      case 'amount_whole_rupees':
        return t.errAmountWholeRupees;
      case 'amount_exceeds_balance':
        return t.errAmountExceedsBalance;
      case 'too_many_pending':
        return t.errTooManyPending;
      default:
        return t.genericError;
    }
  }

  String _errorText(AppLocalizations t, String key) {
    final t = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final wholePkr = int.tryParse(_amountPkr.text.trim());
      if (wholePkr == null) {
        setState(() {
          _message = t.errAmountPositive;
          _messageIsError = true;
        });
        return;
      }
      final amountCoins = pkrToCoins(wholePkr);
      final balance = await SupabaseService.getBalance();
      final existing = await SupabaseService.getWithdrawals();
      final pending = existing
          .where((w) => w['status'] == 'pending' || w['status'] == 'fraud_hold')
          .length;
      final error = validateWithdrawal(
        amountCoins: amountCoins,
        balanceCoins: balance,
        pendingCount: pending,
      );
      if (error != null) {
        setState(() {
          _message = _errorText(t, error);
          _messageIsError = true;
        });
        return;
      }
      await SupabaseService.requestWithdrawal(
        amountCoins: amountCoins,
        rail: _rail,
        accountNumber: _account.text.trim(),
      );
      setState(() {
        _message = t.withdrawalSubmitted;
        _messageIsError = false;
        _listKey++;
      });
    } catch (_) {
      setState(() {
        _message = t.withdrawalFailed;
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _rail,
            decoration: InputDecoration(labelText: t.rail),
            items: [
              DropdownMenuItem(value: 'jazzcash', child: Text(t.railJazzcash)),
              DropdownMenuItem(
                  value: 'easypaisa', child: Text(t.railEasypaisa)),
              DropdownMenuItem(value: 'bank', child: Text(t.railBank)),
            ],
            onChanged: (v) => setState(() => _rail = v ?? 'jazzcash'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _account,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: t.accountNumber),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountPkr,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: t.amountPkr),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(t.submitWithdrawal),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              style: TextStyle(
                  color: _messageIsError ? Colors.red : Colors.green),
            ),
          ],
          const SizedBox(height: 24),
          Text(t.pendingWithdrawals,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            key: ValueKey(_listKey),
            future: SupabaseService.getWithdrawals(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text(t.genericError);
              if (!snapshot.hasData) return const CircularProgressIndicator();
              final rows = snapshot.data!;
              if (rows.isEmpty) return Text(t.historyEmpty);
              return Column(
                children: rows.map((w) {
                  final coins = (w['amount_coins'] as num?)?.toInt() ?? 0;
                  final status = (w['status'] as String?) ?? 'pending';
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  formatCoinsAsPkr(coins),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              _StatusChip(status: status),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${w['rail'] ?? ''} • ${w['account_masked'] ?? ''}',
                            style:
                                Theme.of(context).textTheme.bodySmall,
                          ),
                          if (_isActiveStatus(status)) ...[
                            const SizedBox(height: 12),
                            _WithdrawalTimeline(status: status),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Localised label for a withdrawal status. Pure display — statuses are
/// always set server-side.
String _statusText(AppLocalizations t, String status) {
  switch (status) {
    case 'fraud_hold':
      return t.statusFraudHold;
    case 'approved':
      return t.statusApproved;
    case 'rejected':
      return t.statusRejected;
    case 'paid':
      return t.statusPaid;
    default:
      return t.statusPending;
  }
}

/// Chip colour for a withdrawal status (matches the referral history card).
Color _statusColor(String status) {
  switch (status) {
    case 'fraud_hold':
      return Colors.deepOrange;
    case 'approved':
      return Colors.blue;
    case 'rejected':
      return Colors.red;
    case 'paid':
      return Colors.green;
    default:
      return Colors.orange;
  }
}

/// True for statuses that still move through the timeline. `rejected` is a
/// terminal end-state and shows only the red chip.
bool _isActiveStatus(String status) {
  return status == 'pending' ||
      status == 'fraud_hold' ||
      status == 'approved' ||
      status == 'paid';
}

/// Coloured status pill for a withdrawal request.
class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _statusText(t, status),
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }
}

/// Visual timeline of a withdrawal request's lifecycle:
///
/// Requested (pending) -> Approved -> Paid.
///
/// Completed nodes are green, the current node uses the primary colour,
/// upcoming nodes are grey. Terminal `rejected` requests show only the red
/// chip (see [_isActiveStatus]). Pure display — the app never sets status.
class _WithdrawalTimeline extends StatelessWidget {
  final String status;

  const _WithdrawalTimeline({required this.status});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final labels = <String>[t.statusPending, t.statusApproved, t.statusPaid];
    final int doneSteps;
    switch (status) {
      case 'approved':
        doneSteps = 2;
        break;
      case 'paid':
        doneSteps = 3;
        break;
      default:
        // pending / fraud_hold: the request itself is done
        doneSteps = 1;
    }
    final scheme = Theme.of(context).colorScheme;
    final children = <Widget>[];
    for (var i = 0; i < labels.length; i++) {
      final bool complete = i < doneSteps;
      final bool current = i == doneSteps;
      final Color nodeColor = complete
          ? Colors.green
          : (current ? scheme.primary : Colors.grey.shade400);
      if (i > 0) {
        // Connector centred on the icon row (icon 20px -> centre at 10).
        children.add(
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Container(
                height: 2,
                color: (i - 1) < doneSteps
                    ? Colors.green
                    : Colors.grey.shade300,
              ),
            ),
          ),
        );
      }
      children.add(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              complete
                  ? Icons.check_circle
                  : (current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked),
              color: nodeColor,
              size: 20,
            ),
            const SizedBox(height: 2),
            Text(
              labels[i],
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: nodeColor),
            ),
          ],
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
