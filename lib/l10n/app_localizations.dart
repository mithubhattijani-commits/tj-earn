import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ur.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ur'),
  ];

  /// No description provided for @accountNumber.
  ///
  /// In en, this message translates to:
  /// **'Account number / IBAN'**
  String get accountNumber;

  /// No description provided for @amountPkr.
  ///
  /// In en, this message translates to:
  /// **'Amount (Rs, whole rupees)'**
  String get amountPkr;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'TJ Earn'**
  String get appTitle;

  /// No description provided for @balance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get balance;

  /// No description provided for @balanceLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load balance.'**
  String get balanceLoadFailed;

  /// No description provided for @coins.
  ///
  /// In en, this message translates to:
  /// **'coins'**
  String get coins;

  /// No description provided for @configErrorBody.
  ///
  /// In en, this message translates to:
  /// **'Supabase is not configured for this build. Set SUPABASE_URL and SUPABASE_ANON_KEY with --dart-define and rebuild. No balance is shown until then.'**
  String get configErrorBody;

  /// No description provided for @configErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'App not configured'**
  String get configErrorTitle;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayName;

  /// No description provided for @downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading update…'**
  String get downloading;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @errAmountExceedsBalance.
  ///
  /// In en, this message translates to:
  /// **'Amount is greater than your balance.'**
  String get errAmountExceedsBalance;

  /// No description provided for @errAmountMin.
  ///
  /// In en, this message translates to:
  /// **'Minimum withdrawal is Rs 200 (20,000 coins).'**
  String get errAmountMin;

  /// No description provided for @errAmountPositive.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount greater than zero.'**
  String get errAmountPositive;

  /// No description provided for @errAmountWholeRupees.
  ///
  /// In en, this message translates to:
  /// **'Amount must be whole rupees.'**
  String get errAmountWholeRupees;

  /// No description provided for @errTooManyPending.
  ///
  /// In en, this message translates to:
  /// **'You already have 2 pending withdrawal requests.'**
  String get errTooManyPending;

  /// No description provided for @genericError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get genericError;

  /// No description provided for @goOffers.
  ///
  /// In en, this message translates to:
  /// **'Offers'**
  String get goOffers;

  /// No description provided for @goWallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get goWallet;

  /// No description provided for @goWithdraw.
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get goWithdraw;

  /// No description provided for @haveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Login'**
  String get haveAccount;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet.'**
  String get historyEmpty;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTitle;

  /// No description provided for @installPermissionNeeded.
  ///
  /// In en, this message translates to:
  /// **'Allow install permission in Settings, then try again.'**
  String get installPermissionNeeded;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @loginButton.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get loginButton;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed. Check your email and password.'**
  String get loginFailed;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @noAccount.
  ///
  /// In en, this message translates to:
  /// **'No account yet? Register'**
  String get noAccount;

  /// No description provided for @offersEmpty.
  ///
  /// In en, this message translates to:
  /// **'Offers are coming in Stage 2. No offers are shown until real providers are connected.'**
  String get offersEmpty;

  /// No description provided for @offersTitle.
  ///
  /// In en, this message translates to:
  /// **'Rewards & Offers'**
  String get offersTitle;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @pendingWithdrawals.
  ///
  /// In en, this message translates to:
  /// **'Your withdrawal requests'**
  String get pendingWithdrawals;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get quickActions;

  /// No description provided for @rail.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get rail;

  /// No description provided for @railBank.
  ///
  /// In en, this message translates to:
  /// **'Bank transfer'**
  String get railBank;

  /// No description provided for @railEasypaisa.
  ///
  /// In en, this message translates to:
  /// **'Easypaisa'**
  String get railEasypaisa;

  /// No description provided for @railJazzcash.
  ///
  /// In en, this message translates to:
  /// **'JazzCash'**
  String get railJazzcash;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @registerButton.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get registerButton;

  /// No description provided for @registerFailed.
  ///
  /// In en, this message translates to:
  /// **'Registration failed. Try a different email.'**
  String get registerFailed;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @statusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get statusApproved;

  /// No description provided for @statusFraudHold.
  ///
  /// In en, this message translates to:
  /// **'Fraud hold'**
  String get statusFraudHold;

  /// No description provided for @statusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get statusPaid;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPending;

  /// No description provided for @statusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get statusRejected;

  /// No description provided for @submitWithdrawal.
  ///
  /// In en, this message translates to:
  /// **'Submit withdrawal request'**
  String get submitWithdrawal;

  /// No description provided for @typeCredit.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get typeCredit;

  /// No description provided for @typeDebit.
  ///
  /// In en, this message translates to:
  /// **'Debit'**
  String get typeDebit;

  /// No description provided for @typeOffer.
  ///
  /// In en, this message translates to:
  /// **'Offer reward'**
  String get typeOffer;

  /// No description provided for @typeWithdrawal.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal'**
  String get typeWithdrawal;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get updateAvailable;

  /// No description provided for @updateLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get updateLater;

  /// No description provided for @updateNow.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get updateNow;

  /// No description provided for @urdu.
  ///
  /// In en, this message translates to:
  /// **'Urdu'**
  String get urdu;

  /// No description provided for @walletTitle.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get walletTitle;

  /// No description provided for @withdrawTitle.
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get withdrawTitle;

  /// No description provided for @withdrawalFailed.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal request failed.'**
  String get withdrawalFailed;

  /// No description provided for @withdrawalSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal request submitted.'**
  String get withdrawalSubmitted;

  /// No description provided for @referTab.
  ///
  /// In en, this message translates to:
  /// **'Refer'**
  String get referTab;

  /// No description provided for @referTitle.
  ///
  /// In en, this message translates to:
  /// **'Refer & Earn'**
  String get referTitle;

  /// No description provided for @referSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Invite friends, earn coins'**
  String get referSubtitle;

  /// No description provided for @referYourCode.
  ///
  /// In en, this message translates to:
  /// **'Your referral code'**
  String get referYourCode;

  /// No description provided for @referYourLink.
  ///
  /// In en, this message translates to:
  /// **'Your referral link'**
  String get referYourLink;

  /// No description provided for @referCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get referCopy;

  /// No description provided for @referCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get referCopied;

  /// No description provided for @referShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get referShare;

  /// No description provided for @referShareText.
  ///
  /// In en, this message translates to:
  /// **'Join TJ Earn with my referral link and earn coins:'**
  String get referShareText;

  /// No description provided for @referTotal.
  ///
  /// In en, this message translates to:
  /// **'Total invites'**
  String get referTotal;

  /// No description provided for @referPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get referPending;

  /// No description provided for @referApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get referApproved;

  /// No description provided for @referHowTitle.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get referHowTitle;

  /// No description provided for @referHow1.
  ///
  /// In en, this message translates to:
  /// **'Share your code or link with friends.'**
  String get referHow1;

  /// No description provided for @referHow2.
  ///
  /// In en, this message translates to:
  /// **'They create their account with your link. One person, one account.'**
  String get referHow2;

  /// No description provided for @referHow3.
  ///
  /// In en, this message translates to:
  /// **'After their account passes verification, the referral becomes eligible.'**
  String get referHow3;

  /// No description provided for @referHow4.
  ///
  /// In en, this message translates to:
  /// **'Approved referral rewards arrive in your wallet as coins.'**
  String get referHow4;

  /// No description provided for @referRewardNote.
  ///
  /// In en, this message translates to:
  /// **'Approved referrals pay 1,000 coins each (Rs 10) — paid only after the invited account passes verification and the admin approves the referral. Rewards are coins, never cash.'**
  String get referRewardNote;

  /// No description provided for @referHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Referral history'**
  String get referHistoryTitle;

  /// No description provided for @referHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No referrals yet. Share your link to get started.'**
  String get referHistoryEmpty;

  /// No description provided for @referLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load referral info.'**
  String get referLoadFailed;

  /// No description provided for @referStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get referStatusPending;

  /// No description provided for @referStatusEligible.
  ///
  /// In en, this message translates to:
  /// **'Eligible'**
  String get referStatusEligible;

  /// No description provided for @referStatusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get referStatusApproved;

  /// No description provided for @referStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get referStatusRejected;

  /// No description provided for @referYouInvited.
  ///
  /// In en, this message translates to:
  /// **'You invited'**
  String get referYouInvited;

  /// No description provided for @referInvitedYou.
  ///
  /// In en, this message translates to:
  /// **'Invited you'**
  String get referInvitedYou;

  /// No description provided for @referApplyTitle.
  ///
  /// In en, this message translates to:
  /// **'Have a referral code?'**
  String get referApplyTitle;

  /// No description provided for @referApplyHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the code shared with you'**
  String get referApplyHint;

  /// No description provided for @referApplyButton.
  ///
  /// In en, this message translates to:
  /// **'Apply code'**
  String get referApplyButton;

  /// No description provided for @referApplied.
  ///
  /// In en, this message translates to:
  /// **'Referral recorded!'**
  String get referApplied;

  /// No description provided for @referErrSelf.
  ///
  /// In en, this message translates to:
  /// **'You cannot use your own code.'**
  String get referErrSelf;

  /// No description provided for @referErrDuplicate.
  ///
  /// In en, this message translates to:
  /// **'You already have a referrer.'**
  String get referErrDuplicate;

  /// No description provided for @referErrInvalid.
  ///
  /// In en, this message translates to:
  /// **'This code is not valid.'**
  String get referErrInvalid;

  /// No description provided for @referErrRate.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please try again later.'**
  String get referErrRate;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ur'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ur':
      return AppLocalizationsUr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
