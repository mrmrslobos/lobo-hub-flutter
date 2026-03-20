// lib/widgets/offline_banner.dart
// Shows a persistent banner when the device is offline and a sync indicator.

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../providers/app_provider.dart';

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
            if (provider.isSyncing && !_isOffline) {
              return const _SyncIndicator();
            }
            return const SizedBox.shrink();
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
    return Container(
      width: double.infinity,
      height: 2,
      color: Colors.transparent,
      child: const LinearProgressIndicator(
        backgroundColor: Colors.transparent,
        valueColor: AlwaysStoppedAnimation(AppTheme.primary),
      ),
    );
  }
}
