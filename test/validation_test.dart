import 'package:flutter_test/flutter_test.dart';
import 'package:tj_earn/services/validation.dart';

void main() {
  group('coin conversion', () {
    test('1 coin = Rs 0.01; 100 coins = Rs 1', () {
      expect(formatCoinsAsPkr(1), 'Rs 0.01');
      expect(formatCoinsAsPkr(100), 'Rs 1.00');
      expect(formatCoinsAsPkr(20000), 'Rs 200.00');
      expect(formatCoinsAsPkr(20050), 'Rs 200.50');
      expect(formatCoinsAsPkr(0), 'Rs 0.00');
    });

    test('whole rupees convert to coins', () {
      expect(pkrToCoins(200), 20000);
      expect(pkrToCoins(1), 100);
    });
  });

  group('withdrawal validation', () {
    test('rejects zero and negative amounts', () {
      expect(
        validateWithdrawal(amountCoins: 0, balanceCoins: 50000, pendingCount: 0),
        'amount_positive',
      );
      expect(
        validateWithdrawal(
            amountCoins: -100, balanceCoins: 50000, pendingCount: 0),
        'amount_positive',
      );
    });

    test('rejects below the Rs 100 minimum', () {
      expect(
        validateWithdrawal(
            amountCoins: 9900, balanceCoins: 50000, pendingCount: 0),
        'amount_min',
      );
      expect(
        validateWithdrawal(
            amountCoins: 10000, balanceCoins: 50000, pendingCount: 0),
        isNull,
      );
    });

    test('rejects non-whole-rupee amounts', () {
      expect(
        validateWithdrawal(
            amountCoins: 20050, balanceCoins: 50000, pendingCount: 0),
        'amount_whole_rupees',
      );
    });

    test('rejects amounts above the balance', () {
      expect(
        validateWithdrawal(
            amountCoins: 30000, balanceCoins: 25000, pendingCount: 0),
        'amount_exceeds_balance',
      );
    });

    test('rejects a third pending request', () {
      expect(
        validateWithdrawal(
            amountCoins: 20000, balanceCoins: 50000, pendingCount: 2),
        'too_many_pending',
      );
      expect(
        validateWithdrawal(
            amountCoins: 20000, balanceCoins: 50000, pendingCount: 1),
        isNull,
      );
    });
  });

  group('version comparison', () {
    test('only a strictly higher versionCode is newer', () {
      expect(isNewerVersion(2, 1), isTrue);
      expect(isNewerVersion(1, 1), isFalse);
      expect(isNewerVersion(1, 2), isFalse);
    });
  });

  group('idempotency', () {
    test('a replayed key is rejected', () {
      final guard = IdempotencyGuard();
      expect(guard.claim('cb-1'), isTrue);
      expect(guard.claim('cb-1'), isFalse);
      expect(guard.claim('cb-2'), isTrue);
    });
  });

  group('account masking', () {
    test('keeps only the last 4 digits', () {
      expect(maskAccount('03001234567'), '****4567');
      expect(maskAccount('12'), '****');
    });
  });

  group('referral links', () {
    test('link uses the production domain and uppercases the code', () {
      expect(
        buildReferralLink('aBcD1234'),
        'https://nigraantv.xyz/earn/?ref=ABCD1234',
      );
    });

    test('link never contains a placeholder domain', () {
      expect(buildReferralLink('ABCDEFGH'), isNot(contains('example')));
      expect(buildReferralLink('ABCDEFGH'), contains('nigraantv.xyz'));
    });
  });

  group('referral code format', () {
    test('accepts 8 unambiguous chars', () {
      expect(isValidReferralCode('ABCDEFGH'), isTrue);
      expect(isValidReferralCode('23456789'), isTrue);
      expect(isValidReferralCode('abcdefgh'), isTrue); // case-insensitive
    });

    test('rejects ambiguous chars and wrong lengths', () {
      expect(isValidReferralCode('ABCD01EF'), isFalse); // 0/1 excluded
      expect(isValidReferralCode('ABCDOIEF'), isFalse); // O/I/L excluded
      expect(isValidReferralCode('ABC'), isFalse);
      expect(isValidReferralCode('ABCDEFGHI'), isFalse);
      expect(isValidReferralCode(''), isFalse);
    });
  });
}
