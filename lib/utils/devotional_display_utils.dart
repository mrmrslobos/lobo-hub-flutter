// Parse/normalize devotional entries when AI JSON was stored verbatim in DB fields (UI-only).

import 'dart:convert';

import '../models/models.dart';
import '../services/ai_service.dart';

/// Readable body for `content`-like fields — LLMs sometimes emit arrays/maps.
String? coerceDevotionalBody(dynamic v) {
  if (v == null) return null;
  if (v is String) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
  if (v is List) {
    final parts = <String>[];
    for (final item in v) {
      final s = coerceDevotionalBody(item);
      if (s != null) parts.add(s);
    }
    if (parts.isEmpty) return null;
    return parts.join('\n\n');
  }
  if (v is Map) {
    for (final k in [
      'text',
      'body',
      'markdown',
      'content',
      'reading',
      'paragraph',
      'paragraphs',
    ]) {
      if (!v.containsKey(k)) continue;
      final s = coerceDevotionalBody(v[k]);
      if (s != null) return s;
    }
    final paragraphs = v['paragraphs'];
    if (paragraphs is List) {
      final s = coerceDevotionalBody(paragraphs);
      if (s != null) return s;
    }
  }
  return null;
}

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
    final scriptureRef = data['scriptureRef'] as String? ??
        data['scripture_ref'] as String?;
    final scriptureText =
        data['scripture'] as String? ?? data['scripture_text'] as String?;
    if (scriptureText != null && scriptureRef != null) {
      return '$scriptureText\n\u2014 $scriptureRef';
    }
    return scriptureText ?? scriptureRef;
  }

  List<String> promptsFromMap(Map<String, dynamic> data, DevotionalEntry fallback) {
    final raw =
        data['reflectionPrompts'] ?? data['reflection_prompts'];
    if (raw is List) {
      final list = <String>[];
      for (final x in raw) {
        if (x is String) {
          final t = x.trim();
          if (t.isNotEmpty) list.add(t);
        } else {
          final c = coerceDevotionalBody(x);
          if (c != null && c.trim().isNotEmpty) list.add(c.trim());
        }
      }
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
    dynamic rawBody = data['content'] ??
        data['reading'] ??
        data['devotional'] ??
        data['article'] ??
        data['mainContent'] ??
        data['main_content'];
    final innerTrim = coerceDevotionalBody(rawBody);
    if (innerTrim == null || innerTrim.isEmpty) return null;
    final tit = data['title'] as String? ?? data['headline'] as String?;
    final t = tit?.trim();
    final scripture = scriptureFrom(data);
    final prompts = promptsFromMap(data, baseEntry);
    final mergedPrayer = coerceDevotionalBody(data['prayer']);
    final prayerEffective =
        (mergedPrayer != null && mergedPrayer.isNotEmpty) ? mergedPrayer : baseEntry.prayer;
    return baseEntry.copyWith(
      title: (t != null && t.isNotEmpty) ? t : baseEntry.title,
      scripture: scripture ?? baseEntry.scripture,
      content: innerTrim,
      prayer: prayerEffective,
      reflectionPrompts: prompts.isNotEmpty ? prompts : baseEntry.reflectionPrompts,
    );
  }

  DevotionalEntry? fromBlob(String? blob, DevotionalEntry baseEntry) {
    if (blob == null) return null;
    final t = blob.trim();
    if (t.length < 2) return null;
    final data = AiService.tryParseJsonObject(t);
    if (data == null) return null;
    return mergeFromMap(data, baseEntry);
  }

  final merged =
      fromBlob(e.content, e) ?? fromBlob(e.title, e) ?? fromBlob(e.scripture, e);
  final base = merged ?? e;
  return base.copyWith(reflectionPrompts: normalizeReflectionPromptsForDisplay(base.reflectionPrompts));
}
