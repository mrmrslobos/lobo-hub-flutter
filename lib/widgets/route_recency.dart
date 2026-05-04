import 'dart:async';

import 'package:flutter/material.dart';

import '../services/recent_routes_service.dart';

/// Call [RecentRoutesService.recordPath] when the shell route [location] changes.
class ModuleRouteRecency extends StatefulWidget {
  const ModuleRouteRecency({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  State<ModuleRouteRecency> createState() => _ModuleRouteRecencyState();
}

class _ModuleRouteRecencyState extends State<ModuleRouteRecency> {
  @override
  void initState() {
    super.initState();
    _apply(widget.location);
  }

  @override
  void didUpdateWidget(covariant ModuleRouteRecency oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _apply(widget.location);
    }
  }

  void _apply(String loc) {
    if (loc == '/' || loc == '/auth' || loc.startsWith('/auth')) return;
    unawaited(RecentRoutesService.recordPath(loc));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
