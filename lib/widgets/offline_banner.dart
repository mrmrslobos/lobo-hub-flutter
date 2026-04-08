// lib/widgets/offline_banner.dart
// Shows a persistent banner when the device is offline and a sync indicator.

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../providers/app_provider.dart';
import '../services/supabase_service.dart';
import '../utils/sync_format.dart';
import '../utils/user_facing_errors.dart';

class ConnectivityWrapper extends StatefulWidget {
  final Widget child;
  const ConnectivityWrapper({super.key, required this.child});

  @override
  State<ConnectivityWrapper> createState() => _ConnectivityWrapperState();
}

class _ConnectivityWrapperState extends State<ConnectivityWrapper> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _checkInitial();
    _sub = _connectivity.onConnectivityChanged.listen(_onChanged);
  }

  Future<void> _checkInitial() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _onChanged(result);
    } catch (_) {}
  }

  void _onChanged(List<ConnectivityResult> results) {
    final offline = results.every((r) => r == ConnectivityResult.none);
    if (offline != _isOffline) {
      setState(() => _isOffline = offline);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_isOffline) const _OfflineBanner(),
        Consumer<AppProvider>(
          builder: (ctx, provider, _) {
            if (_isOffline) return const SizedBox.shrink();
            if (!SupabaseService.isConfigured || !provider.isAuthenticated) {
              return const SizedBox.shrink();
            }
            if (provider.isSyncing) return const _SyncIndicator();
            final err = provider.lastSyncError;
            if (err != null && err.isNotEmpty) {
              return _SyncErrorBanner(
                detail: err,
                onRetry: () => provider.refreshFromCloud(),
                onDismiss: provider.clearSyncError,
              );
            }
            final at = provider.lastSuccessfulSyncAt;
            if (at != null) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LastSyncedBar(at: at),
                  _LocalSaveFlash(persistAt: provider.lastLocalPersistAt),
                ],
              );
            }
            return _LocalSaveFlash(persistAt: provider.lastLocalPersistAt);
          },
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.stone800,
      child: SafeArea(
        bottom: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off_rounded, size: 16, color: Colors.white70),
              SizedBox(width: 8),
              Text(
                'You\'re offline — changes saved locally',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncIndicator extends StatelessWidget {
  const _SyncIndicator();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Syncing with cloud',
      child: Container(
        width: double.infinity,
        height: 2,
        color: Colors.transparent,
        child: const LinearProgressIndicator(
          backgroundColor: Colors.transparent,
          valueColor: AlwaysStoppedAnimation(AppTheme.primary),
        ),
      ),
    );
  }
}

class _LastSyncedBar extends StatelessWidget {
  final DateTime at;
  const _LastSyncedBar({required this.at});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = formatRelativeSyncTime(at);
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.space5, vertical: AppTheme.space2),
        child: Row(
          children: [
            Icon(Icons.cloud_done_outlined, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncErrorBanner extends StatefulWidget {
  final String detail;
  final Future<void> Function() onRetry;
  final VoidCallback onDismiss;

  const _SyncErrorBanner({
    required this.detail,
    required this.onRetry,
    required this.onDismiss,
  });

  @override
  State<_SyncErrorBanner> createState() => _SyncErrorBannerState();
}

class _SyncErrorBannerState extends State<_SyncErrorBanner> {
  bool _showTechnical = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final friendly = humanizeCloudSyncError(widget.detail);
    final raw = widget.detail.trim();
    final hasTechnical =
        raw.isNotEmpty && (friendly != raw || raw.length > friendly.length + 8);

    return Material(
      color: AppTheme.error.withValues(alpha: 0.12),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                liveRegion: true,
                label: 'Sync error. $friendly',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.sync_problem_rounded, size: 18, color: AppTheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Couldn’t sync with the cloud. Your changes are still on this device.',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                              height: 1.25,
                            ),
                          ),
                          if (friendly.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              friendly,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: cs.onSurface.withValues(alpha: 0.8),
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (hasTechnical) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => setState(() => _showTechnical = !_showTechnical),
                    child: Text(
                      _showTechnical ? 'Hide details' : 'Technical details',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ),
                if (_showTechnical)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
                    child: SelectableText(
                      raw.length > 1200 ? '${raw.substring(0, 1200)}…' : raw,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        height: 1.25,
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed: widget.onDismiss,
                      child: const Text('Dismiss'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => widget.onRetry(),
                      child: const Text('Retry sync'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Brief confirmation that the latest edit is stored on-device (between cloud syncs).
class _LocalSaveFlash extends StatefulWidget {
  final DateTime? persistAt;

  const _LocalSaveFlash({required this.persistAt});

  @override
  State<_LocalSaveFlash> createState() => _LocalSaveFlashState();
}

class _LocalSaveFlashState extends State<_LocalSaveFlash> {
  bool _visible = false;
  DateTime? _lastSeen;

  @override
  void didUpdateWidget(covariant _LocalSaveFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    final t = widget.persistAt;
    if (t != null && t != _lastSeen) {
      _lastSeen = t;
      setState(() => _visible = true);
      Future<void>.delayed(const Duration(milliseconds: 2200), () {
        if (mounted && widget.persistAt == t) {
          setState(() => _visible = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Saved on this device',
      child: Material(
        color: const Color(0xFF16A34A).withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                'Saved on this device',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
