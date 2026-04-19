import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/ai_service.dart';
import '../services/field_encryption_service.dart';
import '../services/supabase_service.dart';
import '../services/purchase_service.dart';
import '../services/family_activity_service.dart';
import 'data_provider.dart';
import 'sync_provider.dart';

class AuthProvider extends ChangeNotifier {
  User? _activeUser;
  Family? _activeFamily;
  bool _isInitializing = true;
  bool _isLocked = false;
  Set<String> _unreadModules = {};
  
  final DataProvider dataProvider;
  
  AuthProvider(this.dataProvider);

  User? get activeUser => _activeUser;
  Family? get activeFamily => _activeFamily;
  bool get isInitializing => _isInitializing;
  bool get isLocked => _isLocked;
  bool get isAuthenticated => _activeUser != null && _activeFamily != null;
  Set<String> get unreadModules => _unreadModules;

  Family? get currentFamily {
    if (_activeFamily == null) return null;
    return dataProvider.db.families.firstWhereOrNull((f) => f.id == _activeFamily!.id) ?? _activeFamily;
  }

  Future<void> initialize() async {
    _isInitializing = true;
    notifyListeners();

    try {
      if (SupabaseService.isConfigured) {
        final session = SupabaseService.currentSession;
        if (session != null) {
          final meta = session.user.userMetadata?['name'];
          await _resolveUserFromSession(
            session.user.id,
            session.user.email ?? '',
            meta is String ? meta : null,
          );
        }
      }
    } catch (e) {
      debugPrint('[AuthProvider] init error: $e');
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> _resolveUserFromSession(String id, String email, String? metaName) async {
    final db = dataProvider.db;
    User? u = db.users.firstWhereOrNull((u) => u.id == id);
    if (u == null) {
      if (SupabaseService.isConfigured) {
        final cloudU = await SupabaseService.fetchRow('users', {'id': id});
        if (cloudU != null) u = User.fromJson(cloudU);
      }
    }
    if (u != null) {
      _activeUser = u;
      _activeFamily = userFamilies.firstOrNull;
      if (_activeFamily != null) {
        FieldEncryption.init(_activeFamily!.id, _activeFamily!.joinCode);
        _syncAIFlag();
        dataProvider.updateDb(db.applySensitiveDecryption(_activeFamily!.id));
        NotificationService.registerDeviceToken(_activeFamily!.id, u.id);
      }
    }
  }

  Future<void> refreshStoreSubscription() async {
    if (!isAuthenticated) return;
    try {
      final isActive = await PurchaseService.hasActiveSubscription();
      final hasFamily = await PurchaseService.hasFamilyAIAccess();
      if (_activeFamily?.hasAIAccess != isActive || _activeFamily?.hasAIFamilyAccess != hasFamily) {
        if (SupabaseService.isConfigured) {
          await SupabaseService.updateRow(
            'families',
            {'id': _activeFamily!.id},
            {'has_ai_access': isActive, 'has_ai_family_access': hasFamily},
          );
        }
        _activeFamily = _activeFamily!.copyWith(
          hasAIAccess: isActive,
          hasAIFamilyAccess: hasFamily,
        );
        dataProvider.updateDb(dataProvider.db.copyWith(
          families: dataProvider.db.families.map((f) => f.id == _activeFamily!.id ? _activeFamily! : f).toList(),
        ));
        _syncAIFlag();
        notifyListeners();
      }
    } catch (_) {}
  }

  void _syncAIFlag() {
    AiService.setAIBlocked(_activeFamily != null && !_activeFamily!.hasAIAccess && _activeFamily!.isTrialExpired);
  }

  Future<void> authenticate(User user, Family family, {bool isSignup = false}) async {
    _activeUser = user;
    _activeFamily = family;
    FieldEncryption.init(family.id, family.joinCode);
    _syncAIFlag();
    
    var db = dataProvider.db;
    if (!db.users.any((u) => u.id == user.id)) {
      db = db.copyWith(users: [...db.users, user]);
    }
    if (!db.families.any((f) => f.id == family.id)) {
      db = db.copyWith(families: [...db.families, family]);
    }
    
    dataProvider.updateDb(db.applySensitiveDecryption(family.id));
    NotificationService.registerDeviceToken(family.id, user.id);
    notifyListeners();
  }

  Future<void> logout() async {
    if (SupabaseService.isConfigured) {
      try {
        await SupabaseService.signOut();
      } catch (_) {}
    }
    await PurchaseService.revenueCatLogOut();

    _activeUser = null;
    _activeFamily = null;
    _isLocked = false;
    _unreadModules = {};
    FieldEncryption.clear();
    AiService.setAIBlocked(false);
    
    await dataProvider.wipeData();
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    final userId = _activeUser?.id;
    final familyId = _activeFamily?.id;

    if (SupabaseService.isConfigured && userId != null) {
      try {
        if (familyId != null) {
          await SupabaseService.deleteRows('family_members', {'user_id': userId, 'family_id': familyId});
        }
        await SupabaseService.deleteRows('users', {'id': userId});
      } catch (_) {}
      try {
        await SupabaseService.signOut();
      } catch (_) {}
    }

    await PurchaseService.revenueCatLogOut();

    _activeUser = null;
    _activeFamily = null;
    _isLocked = false;
    _unreadModules = {};
    FieldEncryption.clear();
    AiService.setAIBlocked(false);
    
    await dataProvider.wipeData();
    notifyListeners();
  }

  void markModuleRead(String path) {
    if (_unreadModules.contains(path)) {
      _unreadModules = Set.from(_unreadModules)..remove(path);
      notifyListeners();
    }
  }

  void markModuleUnread(String path) {
    if (!_unreadModules.contains(path)) {
      _unreadModules = Set.from(_unreadModules)..add(path);
      notifyListeners();
    }
  }

  void setLocked(bool locked) {
    _isLocked = locked;
    notifyListeners();
  }

  bool canAccess(String path) {
    if (_activeUser == null || _activeFamily == null) return false;

    final normalized = path.startsWith('/') ? path.substring(1) : path;
    final family = currentFamily;
    
    if (family != null && family.isTrialExpired) {
      if (!Family.freeModules.contains(normalized)) return false;
    }

    final enabled = family?.enabledModules;
    if (enabled != null && enabled.isNotEmpty) {
      if (!enabled.contains(normalized) && !enabled.contains(path)) {
        return false;
      }
    }

    final membership = dataProvider.db.familyMembers.firstWhereOrNull(
      (m) => m.userId == _activeUser!.id && m.familyId == _activeFamily!.id,
    );

    final access = membership?.moduleAccess;
    if (access == null || access.isEmpty) return true;
    return access.contains(normalized) || access.contains(path);
  }

  List<Family> get userFamilies {
    if (_activeUser == null) return [];
    return dataProvider.db.families.where((f) {
      return dataProvider.db.familyMembers.any(
        (m) => m.userId == _activeUser!.id && m.familyId == f.id,
      );
    }).toList();
  }

  void switchFamily(String familyId) {
    final family = dataProvider.db.families.firstWhereOrNull((f) => f.id == familyId);
    if (family != null) {
      _activeFamily = family;
      FieldEncryption.init(family.id, family.joinCode);
      _syncAIFlag();
      dataProvider.updateDb(dataProvider.db.applySensitiveDecryption(family.id));
      if (_activeUser != null) {
        NotificationService.registerDeviceToken(family.id, _activeUser!.id);
      }
      notifyListeners();
    }
  }

  void updateFamily(Family family) {
    _activeFamily = family;
    dataProvider.updateDb(dataProvider.db.copyWith(
      families: dataProvider.db.families.map((f) => f.id == family.id ? family : f).toList(),
    ));
    _syncAIFlag();
    notifyListeners();
  }

  FamilyMember? get activeUserMembership {
    if (_activeUser == null || _activeFamily == null) return null;
    return dataProvider.db.familyMembers.firstWhereOrNull(
      (m) => m.userId == _activeUser!.id && m.familyId == _activeFamily!.id,
    );
  }

  Role get activeUserRole => activeUserMembership?.role ?? Role.MEMBER;
  bool get isOwner => activeUserRole == Role.OWNER;
  bool get isAdmin => activeUserRole == Role.ADMIN || activeUserRole == Role.OWNER;
  bool get hasAIAccess => _activeFamily?.hasAIAccess ?? false;

  List<FamilyMember> get familyMembers =>
      dataProvider.db.familyMembers.where((m) => m.familyId == activeFamily?.id).toList();

  User? userById(String id) =>
      dataProvider.db.users.firstWhereOrNull((u) => u.id == id);

  String displayNameForUserId(String userId, {String fallback = 'Member'}) {
    final fid = activeFamily?.id;
    if (fid != null) {
      for (final m in dataProvider.db.familyMembers) {
        if (m.userId == userId && m.familyId == fid) {
          final dn = m.displayName?.trim();
          if (dn != null && dn.isNotEmpty) return dn;
          break;
        }
      }
    }
    final u = userById(userId);
    if (u != null && u.name.trim().isNotEmpty) return u.name;
    return fallback;
  }

  String memberDisplayName(FamilyMember member) =>
      displayNameForUserId(member.id, fallback: member.name);

  Future<void> updateActiveUserSettings(Map<String, dynamic> patch) async {
    final u = _activeUser;
    if (u == null || patch.isEmpty) return;
    final next = Map<String, dynamic>.from(u.settings)..addAll(patch);
    final updated = u.copyWith(settings: next);
    _activeUser = updated;
    dataProvider.updateDb(dataProvider.db.copyWith(
      users: dataProvider.db.users.map((x) => x.id == u.id ? updated : x).toList(),
    ));
    notifyListeners();
    if (SupabaseService.isConfigured && _activeFamily != null) {
      await DatabaseService.syncToCloud(dataProvider.db, _activeFamily!.id, tableScope: {CloudSyncScope.users});
    }
  }

  Future<void> saveAiHistory({
    required String module,
    required String prompt,
    required String response,
  }) async {
    final user = _activeUser;
    final family = _activeFamily;
    if (user == null || family == null) return;
    final entry = AIHistory(
      id: const Uuid().v4(),
      userId: user.id,
      familyId: family.id,
      module: module,
      prompt: prompt,
      response: response,
      createdAt: DateTime.now(),
    );
    dataProvider.updateDb(dataProvider.db.copyWith(aiHistory: [...dataProvider.db.aiHistory, entry]));
    if (SupabaseService.isConfigured) {
      await DatabaseService.syncToCloud(dataProvider.db, family.id, tableScope: {CloudSyncScope.aiHistory});
    }
  }
}

extension ListWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
