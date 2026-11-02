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
  String get backToLogin => 'Back to login';

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
  String get forgotPassword => 'Forgot password?';

  @override
  String get forgotPasswordHint => 'Enter your email — we\'ll send you a password reset link.';

  @override
  String get forgotPasswordSent => 'Reset link sent to your email. Please check your inbox.';

  @override
  String get forgotPasswordTitle => 'Reset password';

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
  String get invalidEmail => 'Please enter a valid email address.';

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

  @override
  String get adminNavLabel => 'Admin';

  @override
  String get adminLoggedInAs => 'Logged in as:';

  @override
  String get adminNotAdminHint => 'This account is not an admin \u2014 log in with the admin email.';

  @override
  String balanceRsApprox(Object value) => '≈ Rs $value';

  @override
  String get adminTitle => 'Admin panel';

  @override
  String get adminAccessRequired => 'Admin access required. Sign in with an admin account to view this panel.';

  @override
  String get adminTabReferrals => 'Referrals';

  @override
  String get adminTabStats => 'Stats';

  @override
  String get adminTabLedger => 'Ledger';

  @override
  String get adminStatusAll => 'All';

  @override
  String get adminLoadFailed => 'Could not load admin data.';

  @override
  String get adminReferralsEmpty => 'No referrals in this state.';

  @override
  String get adminReferrer => 'Referrer';

  @override
  String get adminInvited => 'Invited';

  @override
  String get adminCode => 'Code';

  @override
  String get adminApprove => 'Approve';

  @override
  String get adminReject => 'Reject';

  @override
  String get adminReasonHint => 'Reason (optional)';

  @override
  String get adminConfirmRejectTitle => 'Reject referral?';

  @override
  String get adminConfirmRejectBody => 'Reject this referral? The inviter will not receive the reward.';

  @override
  String get adminCancel => 'Cancel';

  @override
  String get adminConfirm => 'Confirm';

  @override
  String get adminDecisionDone => 'Decision recorded.';

  @override
  String get adminDecisionFailed => 'Could not record the decision.';

  @override
  String get adminTotalReferrers => 'Total referrers';

  @override
  String get adminCoinsCredited => 'Coins credited';

  @override
  String get adminLedgerEmpty => 'No ledger entries.';

  @override
  String get adminTypeFilter => 'Type filter (optional)';

  @override
  String get adminApplyFilter => 'Apply';

  @override
  String adminPageOf(Object page) => 'Page $page';

  @override
  String get adminPrev => 'Previous';

  @override
  String get adminNext => 'Next';

  @override
  String get adminRefresh => 'Refresh';

  @override
  String get adminUnknownUser => 'Unknown user';

  @override
  String get watchAdTitle => 'Watch Ad & Earn Coins';

  @override
  String get watchAdSubtitle => 'Watch a short video ad and earn coins. Coins are credited after you finish the full ad.';

  @override
  String get watchAdButton => 'Watch Ad';

  @override
  String get watchAdNote => 'One reward per completed ad. Daily limits apply.';

  @override
  String get watchAdTile => 'Watch Ad\nEarn 20 Coins';

  @override
  String get watchAdRewardLine => 'Earn 20 coins per completed video';

  @override
  String get pleaseWait => 'Please wait…';

  @override
  String rewardEarned(Object coins) => 'You earned $coins coins!';
  String get rewardsSection => 'Rewards';

  @override
  String get adSkipped => 'Ad skipped — no coins earned. Watch the full ad to earn.';

  @override
  String get adLoadFailed => 'Ad could not be loaded. Please try again.';

  @override
  String get unityNotReady => 'Ads are not ready yet. Please try again in a moment.';
  String get tasksTitle => 'My Tasks';

  @override
  String get streakTitle => 'Daily Streak';

  @override
  String streakDays(Object count) => '$count day streak';

  @override
  String get streakKeepGoing => 'Check in tomorrow to keep your streak!';

  @override
  String streakMilestone(Object coins) => 'Streak milestone! +$coins coins bonus!';

  @override
  String streakNext(Object days) => 'Next bonus at $days days';

  @override
  String streakAtRisk(Object days) =>
      'Your $days-day streak is at risk! Check in today to keep it burning.';

  @override
  String get streakCheckedInToday => 'Checked in today. Come back tomorrow!';

  @override
  String get spinTitle => 'Daily Spin';

  @override
  String get spinSubtitle => 'Spin the wheel once a day for free coins!';

  @override
  String get spinButton => 'Spin Now';

  @override
  String spinWon(Object coins) => 'You won $coins coins!';

  @override
  String get spinUsed => 'Come back tomorrow for your next spin!';

  @override
  String get spinSpinning => 'Spinning...';

  @override
  String onboardingTitle(Object coins) => 'Get Started - Earn $coins Bonus!';

  @override
  String get onboardingSubtitle => 'Complete these tasks to earn your welcome bonus';

  @override
  String get onboardingProfile => 'Set your display name';

  @override
  String get onboardingCheckin => 'Complete your first check-in';

  @override
  String get onboardingQuiz => 'Complete your first quiz';

  @override
  String get onboardingSpin => 'Try your first spin';

  @override
  String get onboardingReferral => 'Share your referral link';

  @override
  String onboardingComplete(Object coins) => 'All done! +$coins coins bonus!';

  @override
  String onboardingProgress(Object done, Object total) => '$done/$total completed';

  @override
  String get referralMilestoneTitle => 'Referral Milestones';

  @override
  String referralMilestoneNext(Object remaining, Object bonus) => '$remaining more for +$bonus coins bonus!';

  @override
  String referralMilestoneReached(Object coins) => 'Milestone reached! +$coins coins!';

  @override
  String get leaderboardTitle => 'Weekly Leaderboard';

  @override
  String get leaderboardSubtitle => 'Top earners this week';

  @override
  String leaderboardYourRank(Object rank) => 'Your rank: #$rank';

  @override
  String get leaderboardEmpty => 'No earnings this week yet. Be the first!';

  @override
  String get leaderboardYou => 'You';

  @override
  String get helpSupport => 'Help & Support';

  @override
  String get helpSupportName => 'Jaani Bhatti — 03090808180';
}
