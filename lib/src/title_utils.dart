import 'xtream.dart';

/// A provider title such as "Kör Nokta |2009| TR-EN" split into a clean title, year and language tags.
class ParsedTitle {
  const ParsedTitle(this.title, {this.year, this.tags = const []});

  final String title;
  final String? year;
  final List<String> tags;
}

final _year = RegExp(r'^(19|20)\d{2}$');
// language codes, optionally joined ("TR-EN", "TR/EN"), possibly with a SUB marker
final _langGroup = RegExp(r'^(?:TR|EN|DE|FR|ES|IT|AR|RU|PT|NL|PL|KU)(?:[-/+](?:TR|EN|DE|FR|ES|IT|AR|RU|PT|NL|PL|KU))*$', caseSensitive: false);
final _sub = RegExp(r'^(TR|EN)?\s*(SUB|ALT|ALTYAZI)\.?$', caseSensitive: false);
final _trailingYear = RegExp(r'\s*[-–(\[]\s*((?:19|20)\d{2})\s*[)\]]?\s*$');

ParsedTitle parseTitle(String raw) {
  final name = raw.trim();
  final parts = name.split('|').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

  if (parts.length >= 2) {
    final tags = <String>[];
    String? year;
    var recognised = 0;
    for (final p in parts.skip(1)) {
      if (_year.hasMatch(p)) {
        year ??= p;
        recognised++;
      } else if (_langGroup.hasMatch(p)) {
        tags.addAll(p.split(RegExp(r'[-/+]')).map((t) => t.toUpperCase()));
        recognised++;
      } else if (_sub.hasMatch(p)) {
        final m = _sub.firstMatch(p)!;
        tags.add('${(m.group(1) ?? 'TR').toUpperCase()} ALT');
        recognised++;
      }
    }
    // Only treat "a | b | c" as title | tags when every trailing part is a recognised tag.
    if (recognised == parts.length - 1) return ParsedTitle(parts.first, year: year, tags: _unique(tags));
  }

  final m = _trailingYear.firstMatch(name);
  if (m != null && m.start > 0) return ParsedTitle(name.substring(0, m.start).trim(), year: m.group(1));
  return ParsedTitle(name);
}

List<String> _unique(List<String> l) => l.toSet().toList();

final _parsed = Expando<ParsedTitle>();

/// Memoised per item (lists hold tens of thousands of entries).
ParsedTitle parsedTitleOf(Item item) => _parsed[item] ??= parseTitle(item.name);

/// Category label without the provider's prefix: "TR/Film ⚡ Netflix Filmleri" -> "Netflix Filmleri".
String groupLabel(String group) {
  final i = group.indexOf('⚡');
  final label = i >= 0 ? group.substring(i + 1).trim() : group.trim();
  return label.isEmpty ? group : label;
}
