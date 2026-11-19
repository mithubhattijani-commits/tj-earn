// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get about => 'About';

  @override
  String get accountNumber => 'Account number / IBAN';

  @override
  String get adLimitReached =>
      'Daily ad limit reached (10/day). Come back tomorrow!';

  @override
  String get adLoadFailed => 'Ad could not be loaded. Please try again.';

  @override
  String get adSkipped =>
      'Ad skipped — no coins earned. Watch the full ad to earn.';

  @override
  String adsLeftToday(Object count) {
    return '$count ads left today';
  }

  @override
  String get adminAccessRequired =>
      'Admin access required. Sign in with an admin account to view this panel.';

  @override
  String get adminApplyFilter => 'Apply';

  @override
  String get adminApprove => 'Approve';

  @override
  String get adminCancel => 'Cancel';

  @override
  String get adminCode => 'Code';

  @override
  String get adminCoinsCredited => 'Coins credited';

  @override
  String get adminConfirm => 'Confirm';

  @override
  String get adminConfirmRejectBody =>
      'Reject this referral? The inviter will not receive the reward.';

  @override
  String get adminConfirmRejectTitle => 'Reject referral?';

  @override
  String get adminDecisionDone => 'Decision recorded.';

  @override
  String get adminDecisionFailed => 'Could not record the decision.';

  @override
  String get adminInvited => 'Invited';

  @override
  String get adminLedgerEmpty => 'No ledger entries.';

  @override
  String get adminLoadFailed => 'Could not load admin data.';

  @override
  String get adminLoggedInAs => 'Logged in as:';

  @override
  String get adminNavLabel => 'Admin';

  @override
  String get adminNext => 'Next';

  @override
  String get adminNotAdminHint =>
      'This account is not an admin — log in with the admin email.';

  @override
  String adminPageOf(Object page) {
    return 'Page $page';
  }

  @override
  String get adminPrev => 'Previous';

  @override
  String get adminReasonHint => 'Reason (optional)';

  @override
  String get adminReferralsEmpty => 'No referrals in this state.';

  @override
  String get adminReferrer => 'Referrer';

  @override
  String get adminRefresh => 'Refresh';

  @override
  String get adminReject => 'Reject';

  @override
  String get adminStatusAll => 'All';

  @override
  String get adminTabLedger => 'Ledger';

  @override
  String get adminTabReferrals => 'Referrals';

  @override
  String get adminTabStats => 'Stats';

  @override
  String get adminTitle => 'Admin panel';

  @override
  String get adminTotalReferrers => 'Total referrers';

  @override
  String get adminTypeFilter => 'Type filter (optional)';

  @override
  String get adminUnknownUser => 'Unknown user';

  @override
  String get amountPkr => 'Amount (Rs, whole rupees)';

  @override
  String get appTitle => 'TJ Earn';

  @override
  String get appUpToDate => 'Your app is up to date';

  @override
  String get backToLogin => 'Send reset link';

  @override
  String get balance => 'Balance';

  @override
  String get balanceLoadFailed => 'Could not load balance.';

  @override
  String balanceRsApprox(Object value) {
    return '≈ Rs $value';
  }

  @override
  String get bonusClaimFailed => 'Could not claim bonus.';

  @override
  String get bonusClaimed => 'Bonus claimed!';

  @override
  String get checkForUpdate => 'Check for Update';

  @override
  String get checkinAlready => 'Already checked in today — come back tomorrow!';

  @override
  String get checkinButton => 'Daily Check-in';

  @override
  String get checkinChecking => 'Checking in…';

  @override
  String checkinDone(Object coins) {
    return 'Daily check-in: +$coins coins!';
  }

  @override
  String get checkinDoneNoCoins => 'Checked in!';

  @override
  String get checkinFailed => 'Check-in failed. Please try again.';

  @override
  String get claimAll => 'Claim all';

  @override
  String get claimTooSoon =>
      'Claiming too fast — please wait a moment and try again.';

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
  String get downloadStalled => 'Stalled — check your connection';

  @override
  String get downloading => 'Downloading update…';

  @override
  String get email => 'Email';

  @override
  String get english => 'English';

  @override
  String get errAmountExceedsBalance => 'Amount is greater than your balance.';

  @override
  String get errAmountMin => 'Minimum withdrawal is Rs 100 (10,000 coins).';

  @override
  String get errAmountPositive => 'Enter an amount greater than zero.';

  @override
  String get errAmountWholeRupees => 'Amount must be whole rupees.';

  @override
  String get errTooManyPending =>
      'You already have 2 pending withdrawal requests.';

  @override
  String get forgotPassword => 'Send reset link';

  @override
  String get forgotPasswordHint => 'Send reset link';

  @override
  String get forgotPasswordSent => 'Send reset link';

  @override
  String get forgotPasswordTitle => 'Send reset link';

  @override
  String get gamesLoadFailed =>
      'Could not load Play & Earn. Check your connection and try again.';

  @override
  String get gamesLoading => 'Loading Play & Earn…';

  @override
  String get gamesNote =>
      'Coins are added to your balance by the server after an offer is completed.';

  @override
  String get gamesSubtitle => 'Complete surveys & offers to earn coins';

  @override
  String get gamesTitle => 'Play & Earn';

  @override
  String get gamesUnavailable =>
      'Play & Earn is not available yet. Please try again later.';

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
  String get helpSupport => 'Help & Support';

  @override
  String get helpSupportName => 'Jaani Bhatti — 03090808180';

  @override
  String get historyEmpty => 'No transactions yet.';

  @override
  String get homeTitle => 'Home';

  @override
  String get installPermissionNeeded =>
      'Allow install permission in Settings, then try again.';

  @override
  String get invalidEmail => 'Send reset link';

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
  String get modelNoticeBody =>
      'Coins ab sirf articles parhne se milen ge — aap ka purana balance mehfooz hai.';

  @override
  String get modelNoticeOk => 'Theek hai';

  @override
  String get modelNoticeTitle => 'How coins work now';

  @override
  String get noAccount => 'No account yet? Register';

  @override
  String get noInternetForUpdate =>
      'No internet connection — turn on internet to check for updates';

  @override
  String get offersEmpty =>
      'Offers are coming in Stage 2. No offers are shown until real providers are connected.';

  @override
  String get offersTitle => 'Rewards & Offers';

  @override
  String onboardingComplete(Object coins) {
    return 'All done! +$coins coins bonus!';
  }

  @override
  String get onboardingProfile => 'Set your display name';

  @override
  String onboardingProgress(Object done, Object total) {
    return '$done/$total completed';
  }

  @override
  String get onboardingReferral => 'Share your referral link';

  @override
  String get onboardingSubtitle =>
      'Complete these tasks to earn your welcome bonus';

  @override
  String onboardingTitle(Object coins) {
    return 'Get Started - Earn $coins Bonus!';
  }

  @override
  String get password => 'Password';

  @override
  String get pendingBonuses => 'Pending bonuses';

  @override
  String get pendingWithdrawals => 'Your withdrawal requests';

  @override
  String get pleaseWait => 'Please wait…';

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
  String get referApplied => 'Referral recorded!';

  @override
  String get referApplyButton => 'Apply code';

  @override
  String get referApplyHint => 'Enter the code shared with you';

  @override
  String get referApplyTitle => 'Have a referral code?';

  @override
  String get referApproved => 'Approved';

  @override
  String get referCopied => 'Copied to clipboard';

  @override
  String get referCopy => 'Copy';

  @override
  String get referErrDuplicate => 'You already have a referrer.';

  @override
  String get referErrInvalid => 'This code is not valid.';

  @override
  String get referErrRate => 'Too many attempts. Please try again later.';

  @override
  String get referErrSelf => 'You cannot use your own code.';

  @override
  String get referHistoryEmpty =>
      'No referrals yet. Share your link to get started.';

  @override
  String get referHistoryTitle => 'Referral history';

  @override
  String get referHow1 => 'Share your code or link with friends.';

  @override
  String get referHow2 =>
      'They create their account with your link. One person, one account.';

  @override
  String get referHow3 => 'They register with your code.';

  @override
  String get referHow4 => '200 coins arrive in your wallet immediately.';

  @override
  String get referHowTitle => 'How it works';

  @override
  String get referInvitedYou => 'Invited you';

  @override
  String get referLoadFailed => 'Could not load referral info.';

  @override
  String get referPending => 'Pending';

  @override
  String get referRewardNote =>
      'Each referral pays 200 coins (Rs 2) — credited to your wallet immediately when the invited person registers with your code. Rewards are coins, never cash.';

  @override
  String get referShare => 'Share';

  @override
  String get referShareText =>
      'Join TJ Earn with my referral link and earn coins:';

  @override
  String get referStatusApproved => 'Approved';

  @override
  String get referStatusEligible => 'Eligible';

  @override
  String get referStatusPending => 'Pending';

  @override
  String get referStatusRejected => 'Rejected';

  @override
  String get referSubtitle => 'Invite friends, earn coins';

  @override
  String get referTab => 'Refer';

  @override
  String get referTitle => 'Refer & Earn';

  @override
  String get referTotal => 'Total invites';

  @override
  String get referYouInvited => 'You invited';

  @override
  String get referYourCode => 'Your referral code';

  @override
  String get referYourLink => 'Your referral link';

  @override
  String referralMilestoneNext(Object bonus, Object remaining) {
    return '$remaining more for +$bonus coins bonus!';
  }

  @override
  String referralMilestoneReached(Object coins) {
    return 'Milestone reached! +$coins coins!';
  }

  @override
  String get referralMilestoneTitle => 'Referral Milestones';

  @override
  String get register => 'Register';

  @override
  String get registerButton => 'Create account';

  @override
  String get registerFailed => 'Registration failed. Try a different email.';

  @override
  String get retry => 'Retry';

  @override
  String rewardEarned(Object coins) {
    return 'You earned $coins coins!';
  }

  @override
  String get rewardsSection => 'Rewards';

  @override
  String get sendResetLink => 'Send reset link';

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
  String get tasksTitle => 'My Tasks';

  @override
  String get typeCredit => 'Credit';

  @override
  String get typeDebit => 'Debit';

  @override
  String get typeOffer => 'Offer reward';

  @override
  String get typeWithdrawal => 'Withdrawal';

  @override
  String get unityNotReady =>
      'Ads are not ready yet. Please try again in a moment.';

  @override
  String get updateAvailable => 'Update available';

  @override
  String get updateInfoNotFound => 'Update info not found — try again later';

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
  String get adminGroupByUser => 'Group by user';

  @override
  String get adminTransactions => 'transactions';

  @override
  String referAutoApplied(String code) {
    return 'Referral $code applied! 🎉';
  }
}
