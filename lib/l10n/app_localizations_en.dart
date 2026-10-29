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

  @override
  String get referTab => 'Refer';

  @override
  String get referTitle => 'Refer & Earn';

  @override
  String get referSubtitle => 'Invite friends, earn coins';

  @override
  String get referYourCode => 'Your referral code';

  @override
  String get referYourLink => 'Your referral link';

  @override
  String get referCopy => 'Copy';

  @override
  String get referCopied => 'Copied to clipboard';

  @override
  String get referShare => 'Share';

  @override
  String get referShareText => 'Join TJ Earn with my referral link and earn coins:';

  @override
  String get referTotal => 'Total invites';

  @override
  String get referPending => 'Pending';

  @override
  String get referApproved => 'Approved';

  @override
  String get referHowTitle => 'How it works';

  @override
  String get referHow1 => 'Share your code or link with friends.';

  @override
  String get referHow2 => 'They create their account with your link. One person, one account.';

  @override
  String get referHow3 => 'After their account passes verification, the referral becomes eligible.';

  @override
  String get referHow4 => 'Approved referral rewards arrive in your wallet as coins.';

  @override
  String get referRewardNote => 'Approved referrals pay 1,000 coins each (Rs 10) — paid only after the invited account passes verification and the admin approves the referral. Rewards are coins, never cash.';

  @override
  String get referHistoryTitle => 'Referral history';

  @override
  String get referHistoryEmpty => 'No referrals yet. Share your link to get started.';

  @override
  String get referLoadFailed => 'Could not load referral info.';

  @override
  String get referStatusPending => 'Pending';

  @override
  String get referStatusEligible => 'Eligible';

  @override
  String get referStatusApproved => 'Approved';

  @override
  String get referStatusRejected => 'Rejected';

  @override
  String get referYouInvited => 'You invited';

  @override
  String get referInvitedYou => 'Invited you';

  @override
  String get referApplyTitle => 'Have a referral code?';

  @override
  String get referApplyHint => 'Enter the code shared with you';

  @override
  String get referApplyButton => 'Apply code';

  @override
  String get referApplied => 'Referral recorded!';

  @override
  String get referErrSelf => 'You cannot use your own code.';

  @override
  String get referErrDuplicate => 'You already have a referrer.';

  @override
  String get referErrInvalid => 'This code is not valid.';

  @override
  String get referErrRate => 'Too many attempts. Please try again later.';
}
