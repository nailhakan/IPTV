import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/xtream.dart';

void main() {
  test('normalizeHost adds scheme and strips trailing slash', () {
    expect(Account.normalizeHost('example.com:8080/'), 'http://example.com:8080');
    expect(Account.normalizeHost('https://example.com'), 'https://example.com');
  });
}
