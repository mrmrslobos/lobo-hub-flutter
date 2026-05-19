import '../models/models.dart';

/// Extract / attach `list_items` rows for cloud sync (Phase 3 lists).
class ListItemsCloud {
  ListItemsCloud._();

  static List<ShoppingListItem> flattenFromLists(
    List<ShoppingList> lists,
    String familyId,
  ) {
    final out = <ShoppingListItem>[];
    for (final list in lists) {
      if (list.familyId != familyId) continue;
      for (var i = 0; i < list.items.length; i++) {
        final item = list.items[i];
        out.add(
          ShoppingListItem.fromListItem(
            item,
            listId: list.id,
            familyId: familyId,
            sortOrder: i,
            updatedAt: list.updatedAt,
          ),
        );
      }
    }
    return out;
  }

  static List<ShoppingList> hydrate(
    List<ShoppingList> headers,
    List<ShoppingListItem> items, {
    List<ShoppingList>? legacyHeadersWithItems,
  }) {
    final byList = <String, List<ShoppingListItem>>{};
    for (final row in items) {
      (byList[row.listId] ??= []).add(row);
    }

    final legacyById = <String, ShoppingList>{};
    if (legacyHeadersWithItems != null) {
      for (final h in legacyHeadersWithItems) {
        legacyById[h.id] = h;
      }
    }

    return headers.map((header) {
      var rows = byList[header.id];
      if (rows == null || rows.isEmpty) {
        final legacy = legacyById[header.id];
        if (legacy != null && legacy.items.isNotEmpty) {
          return header.copyWith(items: legacy.items);
        }
        return header.copyWith(items: const []);
      }
      rows = List<ShoppingListItem>.from(rows)
        ..sort((a, b) {
          final o = a.sortOrder.compareTo(b.sortOrder);
          if (o != 0) return o;
          return a.id.compareTo(b.id);
        });
      return header.copyWith(
        items: rows.map((r) => r.toListItem()).toList(),
      );
    }).toList();
  }

  static List<ShoppingList> parseListHeaders(List<dynamic> raw) {
    return raw
        .whereType<Map>()
        .map((m) => ShoppingList.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }
}
