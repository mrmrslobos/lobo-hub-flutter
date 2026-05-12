import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:lobohub/models/models.dart';
import 'package:lobohub/providers/auth_provider.dart';
import 'package:lobohub/providers/data_provider.dart';
import 'package:lobohub/providers/sync_provider.dart';
import 'package:lobohub/services/database_service.dart';
import 'package:lobohub/services/local_sembast_store.dart';
import 'package:lobohub/services/supabase_service.dart';
import 'package:lobohub/services/sync_outbox.dart';
import 'package:lobohub/test_support/supabase_test_config.dart';

/// Which integration-test account / isolate slot (shared Sembast suffix).
enum SyncTestUser {
  a('sync_test_device_a'),
  b('sync_test_device_b');

  const SyncTestUser(this.sembastSuffix);
  final String sembastSuffix;
}

/// One logical device: RPC facade over an [Isolate] running real providers + sync.
abstract class TestDevice {
  Future<Task> createTask(String title);

  Future<void> deleteTask(String taskId);

  Future<void> waitForTask(String taskId, {Duration timeout = const Duration(seconds: 5)});

  Future<void> waitForTaskGone(String taskId, {Duration timeout = const Duration(seconds: 5)});

  Future<int> pendingOutboxCount({Duration timeout = const Duration(seconds: 5)});

  Future<String?> lastSyncError({Duration timeout = const Duration(seconds: 5)});

  Future<void> dispose();
}

/// Two-device sync harness: coordinator on the root isolate; each device in its own isolate.
class SyncTestHarness {
  SyncTestHarness._({
    required this.familyId,
    required RootIsolateToken rootToken,
  }) : _rootToken = rootToken;

  final String familyId;
  final RootIsolateToken _rootToken;

  final Map<SyncTestUser, _IsolateDeviceSession> _sessions = {};

  /// Signs in two provisioned accounts long enough to create [familyId], then signs out.
  ///
  /// Supabase stays initialized on this isolate for [tearDown] cleanup RPCs.
  static Future<SyncTestHarness> create() async {
    SupabaseTestConfig.ensureSupabaseDartDefines();
    if (!SupabaseTestConfig.hasIntegrationAccounts) {
      throw StateError(
        'Missing HUB_TEST_USER_A_EMAIL / _PASSWORD / HUB_TEST_USER_B_EMAIL / _PASSWORD '
        '(dart-define). These must be two distinct accounts in your **test** Supabase project.',
      );
    }
    if (kIsWeb) {
      throw UnsupportedError('Two-device sync harness requires VM isolates (not web).');
    }

    TestWidgetsFlutterBinding.ensureInitialized();

    final token = RootIsolateToken.instance;
    if (token == null) {
      throw StateError('RootIsolateToken unavailable — call ensureInitialized() first.');
    }

    await Supabase.initialize(
      url: SupabaseTestConfig.supabaseUrl,
      anonKey: SupabaseTestConfig.supabaseAnonKey,
    );

    final uidA = await _signInAndReturnUid(
      SupabaseTestConfig.userAEmail,
      SupabaseTestConfig.userAPassword,
    );
    final uidB = await _signInSwapAndReturnUid(
      SupabaseTestConfig.userBEmail,
      SupabaseTestConfig.userBPassword,
    );

    await _signIn(SupabaseTestConfig.userAEmail, SupabaseTestConfig.userAPassword);

    final familyId = const Uuid().v4();
    final joinCode = _randomJoinCode();
    final now = DateTime.now().toUtc().toIso8601String();

    await Supabase.instance.client.from('families').insert({
      'id': familyId,
      'name': 'sync harness $familyId',
      'owner_id': uidA,
      'join_code': joinCode,
      'subscription_tier': 'trial',
      'enabled_modules': <dynamic>[],
      'created_at': now,
      'updated_at': now,
      'settings': <String, dynamic>{},
    });

    await Supabase.instance.client.from('family_members').insert({
      'user_id': uidA,
      'family_id': familyId,
      'role': Role.OWNER.name,
      'display_name': 'Harness A',
      'household_role': HouseholdRole.parent.name,
      'declared_under_16': false,
    });

    await Supabase.instance.client.from('family_members').insert({
      'user_id': uidB,
      'family_id': familyId,
      'role': Role.MEMBER.name,
      'display_name': 'Harness B',
      'household_role': HouseholdRole.parent.name,
      'declared_under_16': false,
    });

    await Supabase.instance.client.auth.signOut();

    return SyncTestHarness._(familyId: familyId, rootToken: token);
  }

  /// Spawns an isolate with its own Sembast file ([LocalSembastStore.debugDatabaseSuffix]).
  ///
  /// Device **B** enables realtime so soft-delete propagation exercises
  /// `_maybeTombstoneFromSoftDelete`; device **A** pushes changes only.
  Future<TestDevice> spawnDevice({required SyncTestUser asUser}) async {
    final existing = _sessions[asUser];
    if (existing != null) return existing.wrap();

    final boot = _DeviceBootstrap(
      supabaseUrl: SupabaseTestConfig.supabaseUrl,
      supabaseAnonKey: SupabaseTestConfig.supabaseAnonKey,
      familyId: familyId,
      sembastSuffix: asUser.sembastSuffix,
      enableRealtimeListener: asUser == SyncTestUser.b,
      email: asUser == SyncTestUser.a
          ? SupabaseTestConfig.userAEmail
          : SupabaseTestConfig.userBEmail,
      password: asUser == SyncTestUser.a
          ? SupabaseTestConfig.userAPassword
          : SupabaseTestConfig.userBPassword,
    );

    final session = await _IsolateDeviceSession.spawn(boot: boot, rootToken: _rootToken);
    _sessions[asUser] = session;
    return session.wrap();
  }

  Future<void> tearDown() async {
    for (final s in _sessions.values) {
      await s.dispose();
    }
    _sessions.clear();

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: SupabaseTestConfig.userAEmail,
        password: SupabaseTestConfig.userAPassword,
      );
      await SupabaseService.deleteFamilyCloudData(familyId: familyId);
    } on Object catch (e, st) {
      debugPrint('[SyncTestHarness] tearDown cloud cleanup failed: $e\n$st');
    } finally {
      try {
        await Supabase.instance.client.auth.signOut();
      } on Object catch (_) {}
    }

    await LocalSembastStore.deletePhysicalDatabaseForSuffix(SyncTestUser.a.sembastSuffix);
    await LocalSembastStore.deletePhysicalDatabaseForSuffix(SyncTestUser.b.sembastSuffix);
  }

  static Future<void> _signIn(String email, String password) async {
    final res = await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    if (res.user == null) {
      throw StateError('signIn failed for $email');
    }
  }

  static Future<String> _signInAndReturnUid(String email, String password) async {
    await _signIn(email, password);
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      throw StateError('No uid after sign-in ($email)');
    }
    return uid;
  }

  static Future<String> _signInSwapAndReturnUid(String email, String password) async {
    await Supabase.instance.client.auth.signOut();
    return _signInAndReturnUid(email, password);
  }

  static String _randomJoinCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
  }
}

class _DeviceBootstrap {
  _DeviceBootstrap({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.familyId,
    required this.sembastSuffix,
    required this.enableRealtimeListener,
    required this.email,
    required this.password,
  });

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String familyId;
  final String sembastSuffix;
  final bool enableRealtimeListener;
  final String email;
  final String password;

  Map<String, dynamic> toMap() => {
        'supabaseUrl': supabaseUrl,
        'supabaseAnonKey': supabaseAnonKey,
        'familyId': familyId,
        'sembastSuffix': sembastSuffix,
        'enableRealtimeListener': enableRealtimeListener,
        'email': email,
        'password': password,
      };

  static _DeviceBootstrap fromMap(Map<String, dynamic> m) => _DeviceBootstrap(
        supabaseUrl: m['supabaseUrl']! as String,
        supabaseAnonKey: m['supabaseAnonKey']! as String,
        familyId: m['familyId']! as String,
        sembastSuffix: m['sembastSuffix']! as String,
        enableRealtimeListener: m['enableRealtimeListener']! as bool,
        email: m['email']! as String,
        password: m['password']! as String,
      );
}

class _IsolateDeviceSession {
  _IsolateDeviceSession._({
    required this.isolate,
    required SendPort commandSend,
    required ReceivePort replyPort,
    required StreamSubscription<dynamic> replySub,
    required Map<int, Completer<Map<String, dynamic>>> pending,
  })  : _commandSend = commandSend,
        _replyPort = replyPort,
        _replySub = replySub,
        _pending = pending;

  final Isolate isolate;
  final SendPort _commandSend;
  final ReceivePort _replyPort;
  final StreamSubscription<dynamic> _replySub;
  final Map<int, Completer<Map<String, dynamic>>> _pending;

  int _rpcSeq = 0;
  bool _disposed = false;

  static Future<_IsolateDeviceSession> spawn({
    required _DeviceBootstrap boot,
    required RootIsolateToken rootToken,
  }) async {
    final handshake = ReceivePort();
    final reply = ReceivePort();

    final isolate = await Isolate.spawn(
      syncTestDeviceIsolateMain,
      [
        handshake.sendPort,
        rootToken,
        boot.toMap(),
        reply.sendPort,
      ],
      debugName: 'sync-test-${boot.sembastSuffix}',
    );

    final commandSend = await handshake.first as SendPort;
    handshake.close();

    final pending = <int, Completer<Map<String, dynamic>>>{};
    final replySub = reply.listen((dynamic msg) {
      final map = Map<String, dynamic>.from(msg as Map);
      final id = map['id'] as int?;
      if (id == null) return;
      final c = pending.remove(id);
      if (c != null) {
        c.complete(map);
      }
    });

    return _IsolateDeviceSession._(
      isolate: isolate,
      commandSend: commandSend,
      replyPort: reply,
      replySub: replySub,
      pending: pending,
    );
  }

  Future<Map<String, dynamic>> _rpc(
    String cmd,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final id = ++_rpcSeq;
    final done = Completer<Map<String, dynamic>>();
    _pending[id] = done;
    _commandSend.send(<String, dynamic>{'id': id, 'cmd': cmd, 'args': args});
    return done.future.timeout(timeout);
  }

  TestDevice wrap() => _RpcTestDevice(this);

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _rpc('shutdown', {}, timeout: const Duration(seconds: 30));
    } on Object catch (e, st) {
      debugPrint('[SyncTestHarness] device shutdown rpc: $e\n$st');
    }
    isolate.kill(priority: Isolate.immediate);
    await _replySub.cancel();
    _replyPort.close();
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('isolate disposed'));
      }
    }
    _pending.clear();
  }
}

class _RpcTestDevice implements TestDevice {
  _RpcTestDevice(this._session);

  final _IsolateDeviceSession _session;

  @override
  Future<Task> createTask(String title) async {
    final raw = await _session._rpc(
      'createTask',
      {'title': title},
      timeout: const Duration(seconds: 30),
    );
    _throwIfErr(raw);
    return Task.fromJson(Map<String, dynamic>.from(raw['result'] as Map));
  }

  @override
  Future<void> deleteTask(String taskId) async {
    final raw = await _session._rpc(
      'deleteTask',
      {'taskId': taskId},
      timeout: const Duration(seconds: 30),
    );
    _throwIfErr(raw);
  }

  @override
  Future<void> waitForTask(String taskId, {Duration timeout = const Duration(seconds: 5)}) async {
    final raw = await _session._rpc(
      'waitForTask',
      {
        'taskId': taskId,
        'timeoutMs': timeout.inMilliseconds,
      },
      timeout: timeout + const Duration(seconds: 10),
    );
    _throwIfErr(raw);
  }

  @override
  Future<void> waitForTaskGone(String taskId,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final raw = await _session._rpc(
      'waitForTaskGone',
      {
        'taskId': taskId,
        'timeoutMs': timeout.inMilliseconds,
      },
      timeout: timeout + const Duration(seconds: 10),
    );
    _throwIfErr(raw);
  }

  @override
  Future<int> pendingOutboxCount({Duration timeout = const Duration(seconds: 5)}) async {
    final raw = await _session._rpc(
      'pendingOutboxCount',
      {},
      timeout: timeout + const Duration(seconds: 5),
    );
    _throwIfErr(raw);
    return raw['result'] as int;
  }

  @override
  Future<String?> lastSyncError({Duration timeout = const Duration(seconds: 5)}) async {
    final raw = await _session._rpc(
      'lastSyncError',
      {},
      timeout: timeout + const Duration(seconds: 5),
    );
    _throwIfErr(raw);
    final r = raw['result'];
    if (r == null) return null;
    return r.toString();
  }

  @override
  Future<void> dispose() async {
    await _session.dispose();
  }

  void _throwIfErr(Map<String, dynamic> raw) {
    final ok = raw['ok'] == true;
    if (ok) return;
    throw StateError(raw['error']?.toString() ?? 'RPC failed');
  }
}

void _reply(SendPort replySend, int id, Object? result, Object? error) {
  if (error != null) {
    replySend.send(<String, dynamic>{'id': id, 'ok': false, 'error': error.toString()});
  } else {
    replySend.send(<String, dynamic>{'id': id, 'ok': true, 'result': result});
  }
}

/// VM isolate entry — must stay top-level for [Isolate.spawn].
@pragma('vm:entry-point')
void syncTestDeviceIsolateMain(List<Object?> args) {
  unawaited(
    Future(() async {
    final handshakeReply = args[0] as SendPort;
    final token = args[1] as RootIsolateToken;
    final boot = _DeviceBootstrap.fromMap(Map<String, dynamic>.from(args[2] as Map));
    final replySend = args[3] as SendPort;

    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    WidgetsFlutterBinding.ensureInitialized();

    LocalSembastStore.debugDatabaseSuffix = boot.sembastSuffix;

    await Supabase.initialize(
      url: boot.supabaseUrl,
      anonKey: boot.supabaseAnonKey,
    );

    final signIn = await Supabase.instance.client.auth.signInWithPassword(
      email: boot.email,
      password: boot.password,
    );
    if (signIn.user == null) {
      throw StateError('Device isolate sign-in failed for ${boot.email}');
    }

    final data = DataProvider();
    final auth = AuthProvider(data);
    final sync = SyncProvider(authProvider: auth, dataProvider: data);

    await data.initialize();
    await auth.initialize();

    var merged = await DatabaseService.reconcileCloud(data.db, boot.familyId);
    merged = await DatabaseService.backfillMissingUsersForFamily(merged, boot.familyId);
    data.updateDb(merged);

    await sync.refreshFromCloud(familyIdOverride: boot.familyId);
    if (boot.enableRealtimeListener) {
      sync.startRealtimeListener();
    }

    final uuid = const Uuid();

    final cmdReceive = ReceivePort();
    handshakeReply.send(cmdReceive.sendPort);

    Future<void> handle(int id, String cmd, Map<String, dynamic> args) async {
    try {
      switch (cmd) {
        case 'createTask':
          final title = args['title']! as String;
          final uid = Supabase.instance.client.auth.currentUser!.id;
          final taskId = uuid.v4();
          final task = Task(
            id: taskId,
            familyId: boot.familyId,
            creatorId: uid,
            title: title,
          );
          var db = data.db;
          db = db.copyWith(
            tasks: [...db.tasks.where((t) => t.id != taskId), task],
          );
          await DatabaseService.saveLocal(db);
          data.updateDb(db);
          await DatabaseService.pushFamilyTasksToCloudNow(db, boot.familyId);
          await SyncOutbox.drain();
          _reply(replySend, id, task.toJson(), null);
          return;

        case 'deleteTask':
          final taskId = args['taskId']! as String;
          final db = data.db;
          final next = db.copyWith(
            tasks: [...db.tasks.where((t) => !(t.id == taskId && t.familyId == boot.familyId))],
          );
          await DatabaseService.saveLocal(next);
          data.updateDb(next);
          await DatabaseService.pushFamilyTasksToCloudNow(next, boot.familyId);
          await SyncOutbox.drain();
          _reply(replySend, id, null, null);
          return;

        case 'waitForTask':
          final taskId = args['taskId']! as String;
          final timeoutMs = (args['timeoutMs'] as num?)?.toInt() ?? 5000;
          final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
          while (DateTime.now().isBefore(deadline)) {
            await sync.refreshFromCloud(familyIdOverride: boot.familyId);
            final hit =
                data.db.tasks.any((t) => t.id == taskId && t.familyId == boot.familyId);
            if (hit) {
              _reply(replySend, id, null, null);
              return;
            }
            await Future<void>.delayed(const Duration(milliseconds: 150));
          }
          _reply(
            replySend,
            id,
            null,
            TimeoutException('waitForTask $taskId after ${timeoutMs}ms'),
          );
          return;

        case 'waitForTaskGone':
          final taskId = args['taskId']! as String;
          final timeoutMs = (args['timeoutMs'] as num?)?.toInt() ?? 5000;
          final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
          while (DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
            final still =
                data.db.tasks.any((t) => t.id == taskId && t.familyId == boot.familyId);
            if (!still) {
              _reply(replySend, id, null, null);
              return;
            }
          }
          _reply(
            replySend,
            id,
            null,
            TimeoutException('waitForTaskGone $taskId after ${timeoutMs}ms'),
          );
          return;

        case 'pendingOutboxCount':
          final n = await SyncOutbox.pendingCount();
          _reply(replySend, id, n, null);
          return;

        case 'lastSyncError':
          _reply(replySend, id, sync.lastSyncError, null);
          return;

        case 'shutdown':
          sync.stop();
          await Supabase.instance.client.auth.signOut();
          await DatabaseService.resetIsolateTestStorage();
          LocalSembastStore.debugDatabaseSuffix = null;
          _reply(replySend, id, null, null);
          return;

        default:
          _reply(replySend, id, null, StateError('unknown cmd $cmd'));
      }
    } on Object catch (e, st) {
      _reply(replySend, id, null, '$e\n$st');
    }
    }

    late final StreamSubscription<dynamic> sub;
    sub = cmdReceive.listen((dynamic raw) async {
      final msg = Map<String, dynamic>.from(raw as Map);
      final id = msg['id'] as int;
      final cmd = msg['cmd'] as String;
      final a = Map<String, dynamic>.from(msg['args'] as Map? ?? {});
      await handle(id, cmd, a);
      if (cmd == 'shutdown') {
        await sub.cancel();
        cmdReceive.close();
      }
    });
    }).catchError((Object e, StackTrace st) {
      debugPrint('[sync-test-isolate] fatal: $e\n$st');
    }),
  );
}
