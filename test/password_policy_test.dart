import 'package:flutter_test/flutter_test.dart';
import 'package:showtrack/services/password_policy.dart';

void main() {
  test('strong password passes', () {
    expect(passwordProblems('Tape4Rewind', email: 'jane.doe@x.com', name: 'Jane Doe'), isEmpty);
  });
  test('each missing class is reported', () {
    expect(passwordProblems('short1A'), ['At least 8 characters']);
    expect(passwordProblems('alllower12'), ['An uppercase letter']);
    expect(passwordProblems('ALLUPPER12'), ['A lowercase letter']);
    expect(passwordProblems('NoDigitsHere'), ['A number']);
  });
  test('rejects parts of the name or email, any case', () {
    const bad = 'No part of your name or email';
    expect(passwordProblems('Polak2026xx', email: 'simonpolakovic@x.com'), [bad]);
    expect(passwordProblems('xxSIMOx2026', name: 'Simon'), [bad]);
    expect(passwordProblems('Bob12345xyZ', name: 'Bob'), [bad]);
    expect(passwordProblems('Tape4Rewind', name: 'Simon'), isEmpty);
  });
}
