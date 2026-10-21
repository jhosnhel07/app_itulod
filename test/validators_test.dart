import 'package:flutter_test/flutter_test.dart';
import 'package:app_itulod/core/utils/validators.dart';

// Same cases as the web's test/unit/password-rule.test.mjs.
void main() {
  group('password', () {
    test('accepts 8+ chars with upper, lower, number and symbol', () {
      for (final ok in ['Itulod@2026', 'Abcdef1!', 'P4ssw0rd#long', 'Aa1~aaaa', 'Zz9"zzzz', r'Qq1\qqqq']) {
        expect(Validators.password(ok), isNull, reason: ok);
      }
    });
    test('names what is missing', () {
      expect(Validators.password('Ab1!'), contains('at least 8 characters'));
      expect(Validators.password('itulod@2026'), contains('uppercase'));
      expect(Validators.password('ITULOD@2026'), contains('lowercase'));
      expect(Validators.password('Itulod@abcd'), contains('number'));
      expect(Validators.password('Itulod2026x'), contains('special character'));
      expect(Validators.password('Itulod 2026'), contains('special character'));
      expect(Validators.password('Itulod₱2026'), contains('special character'));
      expect(Validators.password(''), isNotNull);
    });
  });

  test('gmail: only name@gmail.com', () {
    expect(Validators.gmail('juan@gmail.com'), isNull);
    expect(Validators.gmail('Juan.Dela@GMAIL.com'), isNull);
    expect(Validators.gmail('juan@yahoo.com'), isNotNull);
    expect(Validators.gmail('juan@gmail.co'), isNotNull);
    expect(Validators.gmail(''), isNotNull);
  });

  test('phone: PH mobile 09XX XXX XXXX, saved as digits', () {
    expect(Validators.phone('0917 123 4567'), isNull);
    expect(Validators.phone('0917-123-4567'), isNull);
    expect(Validators.phone('abcdefghij'), isNotNull);
    expect(Validators.phone('+63 917 123 4567'), isNotNull);
    expect(Validators.phone('0817 123 4567'), isNotNull);
    expect(Validators.phone('0917 123 456'), isNotNull);
    expect(Validators.normalizePhone('0917 123 4567'), '09171234567');
  });
}
