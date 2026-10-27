import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/title_utils.dart';

void main() {
  group('parseTitle', () {
    test('pipe-delimited year and language tags', () {
      final p = parseTitle('Otis Kasırgasının Tam Ortasında |2026| TR-ES');
      expect(p.title, 'Otis Kasırgasının Tam Ortasında');
      expect(p.year, '2026');
      expect(p.tags, ['TR', 'ES']);
    });

    test('spaced pipes and a subtitle marker', () {
      final p = parseTitle('Buddy | 2026 | TRSUB.');
      expect(p.title, 'Buddy');
      expect(p.year, '2026');
      expect(p.tags, ['TR ALT']);
    });

    test('no spaces around pipes', () {
      final p = parseTitle('Buddy |2026| TRSUB.');
      expect(p.title, 'Buddy');
      expect(p.tags, ['TR ALT']);
    });

    test('year at the end', () {
      final p = parseTitle('Dune: Çöl Gezegeni - 2021');
      expect(p.title, 'Dune: Çöl Gezegeni');
      expect(p.year, '2021');
    });

    test('year in parentheses', () {
      expect(parseTitle('Fight Club (1999)').title, 'Fight Club');
      expect(parseTitle('Fight Club (1999)').year, '1999');
    });

    test('match titles and plain titles are left alone', () {
      expect(parseTitle('2026.10.18 - Trabzonspor - Beşiktaş').title, '2026.10.18 - Trabzonspor - Beşiktaş');
      expect(parseTitle('Akvaryum').title, 'Akvaryum');
      expect(parseTitle('Akvaryum').year, isNull);
    });

    test('an unrecognised pipe part keeps the full original title', () {
      final p = parseTitle('A | B | C');
      expect(p.title, 'A | B | C');
    });

    test('does not strip a real year-like title start', () {
      expect(parseTitle('2012').title, '2012');
      expect(parseTitle('1917').title, '1917');
    });
  });

  test('groupLabel strips the provider prefix', () {
    expect(groupLabel('TR/Film ⚡ Netflix Filmleri'), 'Netflix Filmleri');
    expect(groupLabel('Günlük ⚡ Pazartesi'), 'Pazartesi');
    expect(groupLabel('USA | Sports'), 'USA | Sports');
    expect(groupLabel('TR ⚡ '), 'TR ⚡ ');
  });
}
