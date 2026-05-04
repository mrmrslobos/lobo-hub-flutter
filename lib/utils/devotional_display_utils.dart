// Parse/normalize devotional entries when AI JSON was stored verbatim in DB fields (UI-only).

import 'dart:convert';

import '../models/models.dart';
import '../services/ai_service.dart';

List<String> normalizeReflectionPromptsForDisplay(List<String> prompts) {
  if (prompts.length != 1) return prompts;
  final s = prompts.first.trim();
  if (!s.startsWith('[')) return prompts;
  try {
    final d = jsonDecode(s);
    if (d is List) return d.whereType<String>().toList();
  } catch (_) {}
  return prompts;
}

/// When AI JSON was stored verbatim (upstream parse failed), unwrap for reading UI only.
DevotionalEntry devotionalEntryForDisplay(DevotionalEntry e) {
  String? scriptureFrom(Map<String, dynamic> data) {
    final scriptureRef = data['scriptureRef'] as String?;
    final scriptureText = data['scripture'] as String?;
    if (scriptureText != null && scriptureRef != null) {
      return '$scriptureText\n\u2014 $scriptureRef';
    }
    return scriptureText ?? scriptureRef;
  }

  List<String> promptsFromMap(Map<String, dynamic> data, DevotionalEntry fallback) {
    final raw = data['reflectionPrompts'];
    if (raw is List) {
      final list = raw.whereType<String>().toList();
      if (list.isNotEmpty) return list;
    }
    if (raw is String) {
      final t = raw.trim();
      if (t.startsWith('[')) {
        try {
          final d = jsonDecode(t);
          if (d is List) return d.whereType<String>().toList();
        } catch (_) {}
      }
    }
    return fallback.reflectionPrompts;
  }

  DevotionalEntry? mergeFromMap(Map<String, dynamic> data, DevotionalEntry baseEntry) {
    final inner = data['content'];
    if (inner is! String) return null;
    final innerTrim = inner.trim();
    if (innerTrim.isEmpty) return null;
    final t = (data['title'] as String?)?.trim();
    final scripture = scriptureFrom(data);
    final prompts = promptsFromMap(data, baseEntry);
    return baseEntry.copyWith(
      title: (t != null && t.isNotEmpty) ? t : baseEntry.title,
      scripture: scripture ?? baseEntry.scripture,
      content: innerTrim,
      prayer: (data['prayer'] as String?)?.trim().isNotEmpty == true
          ? data['prayer'] as String
          : baseEntry.prayer,
      reflectionPrompts: prompts.isNotEmpty ? prompts : baseEntry.reflectionPrompts,
    );
  }

  DevotionalEntry? fromBlob(String? blob, DevotionalEntry baseEntry) {
    if (blob == null) return null;
    final t = blob.trim();
    if (t.length < 10 || !t.startsWith('{')) return null;
    final data = AiService.tryParseJsonObject(t);
    if (data == null) return null;
    return mergeFromMap(data, baseEntry);
  }

  final merged = fromBlob(e.content, e) ?? fromBlob(e.title, e);
  final base = merged ?? e;
  return base.copyWith(reflectionPrompts: normalizeReflectionPromptsForDisplay(base.reflectionPrompts));
}
