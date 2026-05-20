/// Parsed shopping-list line from quick-add text (name + optional quantity).
class ParsedListItemInput {
  final String text;
  final String? quantity;

  const ParsedListItemInput({required this.text, this.quantity});

  bool get isEmpty => text.isEmpty;
}

/// Splits quick-add text into item name and quantity.
///
/// Supports: `2x milk`, `milk x2`, `2 milk`, `milk 2`, `milk (2L)`, `flour 500g`.
ParsedListItemInput parseListItemInput(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return const ParsedListItemInput(text: '');

  // 2x milk / 2 x milk
  var m = RegExp(r'^(\S+)\s*x\s+(.+)$', caseSensitive: false).firstMatch(s);
  if (m != null) {
    return ParsedListItemInput(
      text: m.group(2)!.trim(),
      quantity: m.group(1)!.trim(),
    );
  }

  // milk x2 / milk x 2L
  m = RegExp(r'^(.+?)\s+x\s*(\S+)$', caseSensitive: false).firstMatch(s);
  if (m != null) {
    return ParsedListItemInput(
      text: m.group(1)!.trim(),
      quantity: m.group(2)!.trim(),
    );
  }

  // milk (2) / milk (2L)
  m = RegExp(r'^(.+?)\s*\(([^)]+)\)\s*$').firstMatch(s);
  if (m != null) {
    final qty = m.group(2)!.trim();
    final name = m.group(1)!.trim();
    if (name.isNotEmpty && qty.isNotEmpty) {
      return ParsedListItemInput(text: name, quantity: qty);
    }
  }

  final qtyToken = r'(\d[\d./\s]*(?:kg|g|l|ml|oz|lb|pk|ct|ea|doz|dozen)?)';

  // 2 milk / 500g flour
  m = RegExp('^$qtyToken\\s+(.+)\$').firstMatch(s);
  if (m != null) {
    return ParsedListItemInput(
      text: m.group(2)!.trim(),
      quantity: m.group(1)!.trim(),
    );
  }

  // milk 2 / flour 500g
  m = RegExp('^(.+?)\\s+$qtyToken\$').firstMatch(s);
  if (m != null) {
    return ParsedListItemInput(
      text: m.group(1)!.trim(),
      quantity: m.group(2)!.trim(),
    );
  }

  return ParsedListItemInput(text: s);
}
