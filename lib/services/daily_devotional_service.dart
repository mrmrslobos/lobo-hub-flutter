import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import 'supabase_service.dart';
import 'ai_service.dart';
import 'database_service.dart';
import 'notification_service.dart';

// Per-user daily devotional (schedule + default privacy). Stored in User.settings.
const kUserDailyEnabled = 'daily_devotional_enabled';
const kUserDailyHour = 'daily_devotional_hour';
const kUserDailyMinute = 'daily_devotional_minute';
const kUserDailyPrivate = 'daily_devotional_private_default';

bool userDailyEnabled(User? u, Family? f) {
  if (u?.settings.containsKey(kUserDailyEnabled) == true) {
    return u!.settings[kUserDailyEnabled] == true;
  }
  return f?.dailyDevotionalEnabled ?? false;
}

int userDailyHourUtc(User? u, Family? f) {
  if (u?.settings[kUserDailyHour] != null) {
    return (u!.settings[kUserDailyHour] as num).toInt();
  }
  return f?.dailyDevotionalHour ?? 7;
}

int userDailyMinuteUtc(User? u, Family? f) {
  if (u?.settings[kUserDailyMinute] != null) {
    return (u!.settings[kUserDailyMinute] as num).toInt();
  }
  return f?.dailyDevotionalMinute ?? 0;
}

bool userDailyPrivateDefault(User? u) =>
    u?.settings[kUserDailyPrivate] == true;

int userDailyNotificationId(String userId) =>
    9910000 + (userId.hashCode.abs() % 900000);

DateTime userDailyScheduledLocalToday(User? u, Family? f) {
  return dailyDevotionalStoredUtcToLocalToday(
    userDailyHourUtc(u, f),
    userDailyMinuteUtc(u, f),
  );
}

/// Converts hour/minute stored as UTC (from a local time picker) back to local
/// wall-clock time for [day], using that day's DST offset.
DateTime dailyDevotionalStoredUtcToLocalToday(
  int hourUtc,
  int minuteUtc, {
  DateTime? day,
}) {
  final anchor = day ?? DateTime.now();
  return DateTime.utc(
    anchor.year,
    anchor.month,
    anchor.day,
    hourUtc,
    minuteUtc,
  ).toLocal();
}

DateTime _calendarDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// Creates today's devotional on-device, updates the daily local notification,
/// and keeps notification taps aligned with the stored entry.
class DailyDevotionalService {
  DailyDevotionalService._();

  static const _kScriptureBuckets = <String>[
    'Old Testament narrative or Torah (not used in your avoid-list)',
    'Wisdom literature — Job, Psalms, Proverbs, or Ecclesiastes',
    'Major or minor prophets',
    'The Gospels — life or teaching of Jesus',
    'Acts and the early church',
    'Pauline epistles (Romans through Philemon)',
    'Hebrews, general epistles, or Revelation',
  ];

  static DevotionalEntry? findTodaysAuto(
    AppDB db, {
    required String familyId,
    required String userId,
    DateTime? onDay,
  }) {
    final day = _calendarDay(onDay ?? DateTime.now());
    for (final e in db.devotionalEntries) {
      if (e.familyId == familyId &&
          e.creatorId == userId &&
          e.tags.contains('daily-auto') &&
          _calendarDay(e.date) == day) {
        return e;
      }
    }
    return null;
  }

  /// Sync + generate today's devotional when enabled; refresh the daily alarm.
  static Future<DevotionalEntry?> prepareOnAppActive(AppProvider provider) async {
    final family = provider.activeFamily;
    final user = provider.activeUser;
    if (family == null || user == null) return null;
    if (!userDailyEnabled(user, family)) {
      await rescheduleNotification(provider);
      return null;
    }

    final entry = await ensureTodayDevotional(
      provider,
      syncCloudFirst: true,
      generateIfMissing: true,
    );
    await rescheduleNotification(provider, entry: entry);
    return entry;
  }

  /// Pull from cloud, then create today's row on-device when missing.
  static Future<DevotionalEntry?> ensureTodayDevotional(
    AppProvider provider, {
    bool syncCloudFirst = true,
    bool generateIfMissing = true,
  }) async {
    final family = provider.activeFamily;
    final user = provider.activeUser;
    if (family == null || user == null) return null;
    if (!userDailyEnabled(user, family)) return null;

    DevotionalEntry? existing = findTodaysAuto(
      provider.db,
      familyId: family.id,
      userId: user.id,
    );
    if (existing != null) return existing;

    if (syncCloudFirst) {
      try {
        final merged = await DatabaseService.reconcileCloud(
          provider.db,
          family.id,
          getLocalAfterFetch: () => provider.db,
        );
        await provider.updateDb(merged);
        existing = findTodaysAuto(
          provider.db,
          familyId: family.id,
          userId: user.id,
        );
        if (existing != null) return existing;
      } catch (e) {
        debugPrint('[DailyDevotionalService] cloud sync failed: $e');
      }
    }

    if (!generateIfMissing) return null;
    final entry = await generateForToday(
      db: provider.db,
      user: user,
      familyId: family.id,
    );
    if (entry != null) {
      await provider.updateDb(await DatabaseService.loadLocal());
    }
    return entry;
  }

  /// Background / headless entry: no [AppProvider].
  static Future<DevotionalEntry?> ensureTodayInBackground({
    required AppDB db,
    required User user,
    required Family family,
    bool syncCloudFirst = true,
    bool generateIfMissing = true,
  }) async {
    if (!userDailyEnabled(user, family)) return null;

    var working = db;
    var existing = findTodaysAuto(
      working,
      familyId: family.id,
      userId: user.id,
    );
    if (existing != null) return existing;

    if (syncCloudFirst && SupabaseService.isConfigured) {
      try {
        working = await DatabaseService.reconcileCloud(
          working,
          family.id,
          getLocalAfterFetch: () => working,
        );
        await DatabaseService.saveLocal(working);
        existing = findTodaysAuto(
          working,
          familyId: family.id,
          userId: user.id,
        );
        if (existing != null) return existing;
      } catch (e) {
        debugPrint('[DailyDevotionalService] background sync failed: $e');
      }
    }

    if (!generateIfMissing) return null;
    return generateForToday(
      db: working,
      user: user,
      familyId: family.id,
    );
  }

  static Future<DevotionalEntry?> generateForToday({
    AppDB? db,
    User? user,
    String? familyId,
    AppProvider? provider,
  }) async {
    assert(
      provider != null || (db != null && user != null && familyId != null),
      'Provide AppProvider or db+user+familyId',
    );

    if (AiService.isAIBlocked) return null;

    final resolvedDb = provider?.db ?? db!;
    final resolvedUser = provider?.activeUser ?? user!;
    final resolvedFamilyId = familyId ?? provider!.activeFamily!.id;

    final existing = findTodaysAuto(
      resolvedDb,
      familyId: resolvedFamilyId,
      userId: resolvedUser.id,
    );
    if (existing != null) return existing;

    try {
      final variety = _devotionalVarietyBlock(resolvedDb, resolvedFamilyId);
      final prompt = '''Write an adult-oriented daily devotional for today.
Audience: mature adults navigating real life—work stress, relationships, parenting fatigue, grief, temptation, doubt, health, money worries, and ordinary discouragement. Speak with honesty and compassion; do not talk down, use childish language, or rely on simplistic moral tales.

Pick one Bible verse or short passage (within the assigned Scripture region below) and build a focused devotional around it.

Requirements:
- Be direct where it helps: name common adult struggles without being graphic or sensational.
- Anchor hope in God's character and in specific promises from Scripture (quote or paraphrase faithfully).
- Close the main message on an uplifting, faith-filled note—realistic, not trite.
- Aim for roughly 250–400 words in "content" when possible.

Return JSON with these exact fields: title, scripture, scriptureRef, content, reflectionPrompts (array of 3 personal reflection or journaling prompts for an adult), prayer.
For "scripture", write out the FULL verse text (e.g. "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.").
For "scriptureRef", provide only the reference (e.g. "John 3:16").
For "prayer", write a sincere, adult-voiced prayer that names real tension and rests on God's promises.$variety''';

      final raw = await AiService.ask(
        prompt: prompt,
        feature: 'ai_devotional',
        familyId: resolvedFamilyId,
        responseMimeType: 'application/json',
      );
      if (raw == null) return null;

      if (provider != null) {
        provider.saveAiHistory(
          module: 'devotional',
          prompt: 'Auto-generate daily devotional',
          response: raw,
        );
      }

      final vis = userDailyPrivateDefault(resolvedUser)
          ? Visibility.PRIVATE
          : Visibility.FAMILY;

      DevotionalEntry entry;
      final data = AiService.tryParseJsonObject(raw);
      if (data != null) {
        final scriptureRef = data['scriptureRef'] as String?;
        final scriptureText = data['scripture'] as String?;
        final scripture = scriptureText != null && scriptureRef != null
            ? '$scriptureText\n\u2014 $scriptureRef'
            : scriptureText ?? scriptureRef;
        entry = DevotionalEntry(
          id: const Uuid().v4(),
          familyId: resolvedFamilyId,
          creatorId: resolvedUser.id,
          title: data['title'] as String? ?? 'Daily Devotional',
          scripture: scripture,
          content: data['content'] as String?,
          reflectionPrompts:
              (data['reflectionPrompts'] as List?)?.cast<String>() ?? [],
          prayer: data['prayer'] as String?,
          date: DateTime.now(),
          visibility: vis,
          tags: ['daily-auto'],
        );
      } else {
        entry = DevotionalEntry(
          id: const Uuid().v4(),
          familyId: resolvedFamilyId,
          creatorId: resolvedUser.id,
          title: 'Daily Devotional',
          content: raw,
          date: DateTime.now(),
          visibility: vis,
          tags: ['daily-auto'],
        );
      }

      final nextDb = resolvedDb.copyWith(
        devotionalEntries: [...resolvedDb.devotionalEntries, entry],
      );
      if (provider != null) {
        await provider.saveAndSync(
          nextDb,
          pushTableScope: {CloudSyncScope.devotionals},
        );
      } else {
        await DatabaseService.saveAndSync(
          nextDb,
          resolvedFamilyId,
          tableScope: {CloudSyncScope.devotionals},
        );
      }
      return entry;
    } catch (e, st) {
      debugPrint('[DailyDevotionalService] generation failed: $e\n$st');
      return null;
    }
  }

  static Future<void> rescheduleNotification(
    AppProvider provider, {
    DevotionalEntry? entry,
  }) async {
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) return;
    await rescheduleNotificationFor(
      user: user,
      family: family,
      db: provider.db,
      entry: entry,
    );
  }

  static Future<void> rescheduleNotificationFor({
    required User user,
    required Family family,
    required AppDB db,
    DevotionalEntry? entry,
  }) async {
    final nid = userDailyNotificationId(user.id);
    if (!userDailyEnabled(user, family)) {
      await NotificationService.cancel(nid);
      return;
    }

    final resolved = entry ??
        findTodaysAuto(
          db,
          familyId: family.id,
          userId: user.id,
        );

    final scheduled = userDailyScheduledLocalToday(user, family);
    final title = resolved != null && resolved.title.trim().isNotEmpty
        ? resolved.title.trim()
        : 'Daily devotional';
    final body = _notificationBody(resolved);
    final payload = resolved != null
        ? '/devotional?id=${resolved.id}'
        : '/devotional';

    await NotificationService.scheduleDaily(
      id: nid,
      title: title,
      body: body,
      time: Time(scheduled.hour, scheduled.minute),
      payload: payload,
    );
  }

  static String _notificationBody(DevotionalEntry? entry) {
    if (entry == null) {
      return 'Open ${AppConfig.appName} for today\'s reading.';
    }
    final ref = _scriptureRefForAvoidList(entry.scripture);
    if (ref != null && ref.isNotEmpty) return ref;
    final content = entry.content?.trim();
    if (content != null && content.isNotEmpty) {
      final first = content.split(RegExp(r'\r?\n')).first.trim();
      if (first.length > 120) return '${first.substring(0, 117)}...';
      if (first.isNotEmpty) return first;
    }
    return 'Tap to read today\'s devotional.';
  }

  static String _dailyScriptureBucket(String familyId, DateTime now) {
    final dayKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    var h = 0;
    for (final cu in '$familyId$dayKey'.codeUnits) {
      h = (h * 31 + cu) & 0x7fffffff;
    }
    return _kScriptureBuckets[h % _kScriptureBuckets.length];
  }

  static String? _scriptureRefForAvoidList(String? scripture) {
    if (scripture == null || scripture.trim().isEmpty) return null;
    final lines = scripture
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i];
      final dash = RegExp(r'^[\u2014\u2013\-]\s*(.+)$');
      final m = dash.firstMatch(line);
      if (m != null) return m.group(1)!.trim();
      if (line.length <= 120 &&
          RegExp(r'\d+\s*:\s*\d+').hasMatch(line) &&
          RegExp(r'[A-Za-z\u00C0-\u024F]').hasMatch(line)) {
        return line;
      }
    }
    final em = scripture.lastIndexOf('\u2014');
    if (em >= 0) return scripture.substring(em + 1).trim();
    final en = scripture.lastIndexOf('\u2013');
    if (en >= 0) return scripture.substring(en + 1).trim();
    return null;
  }

  static String _devotionalVarietyBlock(AppDB db, String familyId) {
    final sorted = db.devotionals
        .where((e) => e.familyId == familyId)
        .toList()
      ..sort((a, b) {
        final c = b.date.compareTo(a.date);
        if (c != 0) return c;
        return b.updatedAt.compareTo(a.updatedAt);
      });

    final refs = <String>[];
    final titles = <String>[];
    final seenR = <String>{};
    final seenT = <String>{};

    for (final e in sorted) {
      if (refs.length < 16) {
        final r = _scriptureRefForAvoidList(e.scripture);
        if (r != null && r.isNotEmpty && seenR.add(r)) refs.add(r);
      }
      if (titles.length < 10) {
        final t = e.title.trim();
        if (t.isNotEmpty && t != 'Daily Devotional' && seenT.add(t)) {
          titles.add(t);
        }
      }
      if (refs.length >= 16 && titles.length >= 10) break;
    }

    final bucket = _dailyScriptureBucket(familyId, DateTime.now());
    final nonce = const Uuid().v4();
    final ts = DateTime.now().toUtc().toIso8601String();

    final buf = StringBuffer()
      ..write(
        "\n\nToday's Scripture focus (choose ONE tight passage within this region): $bucket.",
      )
      ..write(
        '\nAvoid overused default choices (e.g. John 3:16, Psalm 23, Philippians 4:6-7, Jeremiah 29:11) unless they truly fit and are not excluded below.',
      );
    if (refs.isNotEmpty) {
      buf
        ..write(
          '\nIMPORTANT: Do NOT use these recently used passages (different book/chapter): ',
        )
        ..write(refs.join('; '))
        ..write('.');
    }
    if (titles.isNotEmpty) {
      buf
        ..write('\nDo NOT reuse or lightly rephrase these recent titles: ')
        ..write(titles.join('; '))
        ..write('.');
    }
    buf
      ..write('\nVary tone, metaphors, and structure; avoid boilerplate openings.')
      ..write('\nUnique generation id (do not echo): $nonce at $ts.');
    return buf.toString();
  }
}
