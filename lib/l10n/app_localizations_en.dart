// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get accountNumber => 'Account number / IBAN';

  @override
  String get amountPkr => 'Amount (Rs, whole rupees)';

  @override
  String get appTitle => 'TJ Earn';

  @override
  String get balance => 'Balance';

  @override
  String get balanceLoadFailed => 'Could not load balance.';

  @override
  String get coins => 'coins';

  @override
  String get configErrorBody =>
      'Supabase is not configured for this build. Set SUPABASE_URL and SUPABASE_ANON_KEY with --dart-define and rebuild. No balance is shown until then.';

  @override
  String get configErrorTitle => 'App not configured';

  @override
  String get displayName => 'Display name';

  @override
  String get downloading => 'Downloading update…';

  @override
  String get email => 'Email';

  @override
  String get english => 'English';

  @override
  String get errAmountExceedsBalance => 'Amount is greater than your balance.';

  @override
  String get errAmountMin => 'Minimum withdrawal is Rs 200 (20,000 coins).';

  @override
  String get errAmountPositive => 'Enter an amount greater than zero.';

  @override
  String get errAmountWholeRupees => 'Amount must be whole rupees.';

  @override
  String get errTooManyPending =>
      'You already have 2 pending withdrawal requests.';

  @override
  String get genericError => 'Something went wrong. Please try again.';

  @override
  String get goOffers => 'Offers';

  @override
  String get goWallet => 'Wallet';

  @override
  String get goWithdraw => 'Withdraw';

  @override
  String get haveAccount => 'Already have an account? Login';

  @override
  String get historyEmpty => 'No transactions yet.';

  @override
  String get homeTitle => 'Home';

  @override
  String get installPermissionNeeded =>
      'Allow install permission in Settings, then try again.';

  @override
  String get language => 'Language';

  @override
  String get login => 'Login';

  @override
  String get loginButton => 'Login';

  @override
  String get loginFailed => 'Login failed. Check your email and password.';

  @override
  String get logout => 'Logout';

  @override
  String get noAccount => 'No account yet? Register';

  @override
  String get offersEmpty =>
      'Offers are coming in Stage 2. No offers are shown until real providers are connected.';

  @override
  String get offersTitle => 'Rewards & Offers';

  @override
  String get password => 'Password';

  @override
  String get pendingWithdrawals => 'Your withdrawal requests';

  @override
  String get quickActions => 'Quick actions';

  @override
  String get rail => 'Payment method';

  @override
  String get railBank => 'Bank transfer';

  @override
  String get railEasypaisa => 'Easypaisa';

  @override
  String get railJazzcash => 'JazzCash';

  @override
  String get register => 'Register';

  @override
  String get registerButton => 'Create account';

  @override
  String get registerFailed => 'Registration failed. Try a different email.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get statusApproved => 'Approved';

  @override
  String get statusFraudHold => 'Fraud hold';

  @override
  String get statusPaid => 'Paid';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusRejected => 'Rejected';

  @override
  String get submitWithdrawal => 'Submit withdrawal request';

  @override
  String get typeCredit => 'Credit';

  @override
  String get typeDebit => 'Debit';

  @override
  String get typeOffer => 'Offer reward';

  @override
  String get typeWithdrawal => 'Withdrawal';

  @override
  String get updateAvailable => 'Update available';

  @override
  String get updateLater => 'Later';

  @override
  String get updateNow => 'Update';

  @override
  String get urdu => 'Urdu';

  @override
  String get walletTitle => 'Wallet';

  @override
  String get withdrawTitle => 'Withdraw';

  @override
  String get withdrawalFailed => 'Withdrawal request failed.';

  @override
  String get withdrawalSubmitted => 'Withdrawal request submitted.';
}
