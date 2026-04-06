import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/supabase_service.dart';

/// Full cloud reconcile when Supabase is configured and the user is signed in.
Future<void> pullCloudLatest(BuildContext context) async {
  final p = context.read<AppProvider>();
  if (SupabaseService.isConfigured && p.isAuthenticated) {
    await p.refreshFromCloud();
  }
}

/// Same as [pullCloudLatest] with a short haptic for pull-to-refresh / manual sync.
Future<void> pullCloudLatestWithHaptic(BuildContext context) async {
  HapticFeedback.mediumImpact();
  await pullCloudLatest(context);
}
