// lib/screens/location/location_screen.dart
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

/// Haversine distance in metres between two lat/lng pairs.
double _haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final phi1 = lat1 * pi / 180;
  final phi2 = lat2 * pi / 180;
  final dPhi = (lat2 - lat1) * pi / 180;
  final dLam = (lon2 - lon1) * pi / 180;
  final a = sin(dPhi / 2) * sin(dPhi / 2) +
      cos(phi1) * cos(phi2) * sin(dLam / 2) * sin(dLam / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

/// Format distance for display.
String _formatDistance(double metres) {
  if (metres < 1000) return '${metres.round()} m away';
  return '${(metres / 1000).toStringAsFixed(1)} km away';
}

/// Find the nearest saved place within its radius.
String? _nearestPlace(double lat, double lon, List<SavedPlace> places) {
  SavedPlace? best;
  double bestDist = double.infinity;
  for (final p in places) {
    final d = _haversine(lat, lon, p.latitude, p.longitude);
    if (d <= p.radiusMetres && d < bestDist) {
      best = p;
      bestDist = d;
    }
  }
  if (best == null) return null;
  return '${best.emoji ?? ''} ${best.name}'.trim();
}

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  Timer? _locationTimer;
  bool _permissionDenied = false;
  Position? _lastPosition;

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<bool> _ensureLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable location services')),
        );
      }
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied')),
          );
        }
        setState(() => _permissionDenied = true);
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission permanently denied. Please enable in Settings.')),
        );
      }
      setState(() => _permissionDenied = true);
      return false;
    }

    setState(() => _permissionDenied = false);
    return true;
  }

  Future<void> _updateLocation() async {
    final provider = context.read<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) setState(() => _lastPosition = position);

      String? placeName;
      String? nearPlace;
      try {
        final placemarks = await geo.placemarkFromCoordinates(
          position.latitude, position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          placeName = [p.street, p.locality].where((s) => s != null && s.isNotEmpty).join(', ');
          nearPlace = [p.subLocality, p.administrativeArea].where((s) => s != null && s.isNotEmpty).join(', ');
        }
      } catch (_) {}

      // Check if near a saved place
      final savedPlaces = provider.db.savedPlaces
          .where((p) => p.familyId == family.id)
          .toList();
      final nearSaved = _nearestPlace(position.latitude, position.longitude, savedPlaces);
      if (nearSaved != null) nearPlace = nearSaved;

      final db = provider.db;
      final existing = db.locationShares.cast<LocationShare?>().firstWhere(
        (l) => l?.userId == user.id && l?.familyId == family.id,
        orElse: () => null,
      );

      if (existing != null && existing.isSharing) {
        final updated = db.locationShares.map((l) {
          if (l.id == existing.id) {
            return LocationShare(
              id: l.id,
              familyId: l.familyId,
              userId: l.userId,
              latitude: position.latitude,
              longitude: position.longitude,
              accuracy: position.accuracy,
              placeName: placeName,
              nearPlace: nearPlace,
              isSharing: true,
              updatedAt: DateTime.now(),
            );
          }
          return l;
        }).toList();
        await provider.saveAndSync(db.copyWith(locationShares: updated.cast<UserLocation>()));
      }
    } catch (e) {
      debugPrint('Location update error: $e');
    }
  }

  void _startLocationUpdates() {
    _locationTimer?.cancel();
    _updateLocation();
    _locationTimer = Timer.periodic(const Duration(seconds: 60), (_) => _updateLocation());
  }

  void _stopLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  Future<void> _toggleSharing(LocationShare? current, bool sharing) async {
    final provider = context.read<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) return;

    if (sharing) {
      final granted = await _ensureLocationPermission();
      if (!granted) return;
    }

    final db = provider.db;

    if (current == null) {
      double lat = 0.0, lng = 0.0;
      String? placeName, nearPlace;

      if (sharing) {
        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
          );
          lat = position.latitude;
          lng = position.longitude;
          if (mounted) setState(() => _lastPosition = position);
          try {
            final placemarks = await geo.placemarkFromCoordinates(lat, lng);
            if (placemarks.isNotEmpty) {
              final p = placemarks.first;
              placeName = [p.street, p.locality].where((s) => s != null && s.isNotEmpty).join(', ');
              nearPlace = [p.subLocality, p.administrativeArea].where((s) => s != null && s.isNotEmpty).join(', ');
            }
          } catch (_) {}
        } catch (_) {}
      }

      final newShare = LocationShare(
        id: const Uuid().v4(),
        familyId: family.id,
        userId: user.id,
        latitude: lat,
        longitude: lng,
        placeName: placeName,
        nearPlace: nearPlace,
        isSharing: sharing,
        updatedAt: DateTime.now(),
      );
      await provider.saveAndSync(db.copyWith(locationShares: [...db.locationShares, newShare]));
    } else {
      final updated = db.locationShares.map((l) {
        if (l.id == current.id) {
          return LocationShare(
            id: l.id,
            familyId: l.familyId,
            userId: l.userId,
            latitude: l.latitude,
            longitude: l.longitude,
            placeName: l.placeName,
            nearPlace: l.nearPlace,
            isSharing: sharing,
            updatedAt: DateTime.now(),
          );
        }
        return l;
      }).toList();
      await provider.saveAndSync(db.copyWith(locationShares: updated.cast<UserLocation>()));
    }

    if (sharing) {
      _startLocationUpdates();
    } else {
      _stopLocationUpdates();
    }
  }

  Future<void> _openInMaps(double lat, double lng) async {
    final uri = Uri.parse('https://maps.google.com/?q=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _deletePlace(String placeId) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      savedPlaces: db.savedPlaces.where((p) => p.id != placeId).toList(),
    ));
  }

  void _showAddPlaceSheet() {
    final pos = _lastPosition;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddPlaceSheet(
        currentPosition: pos != null ? (lat: pos.latitude, lng: pos.longitude) : null,
        onSave: (place) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          await provider.saveAndSync(db.copyWith(
            savedPlaces: [...db.savedPlaces, place],
          ));
        },
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final members = provider.familyMembers;
    final locationShares = provider.db.locationShares
        .where((l) => l.familyId == family.id)
        .toList();

    final myShare = locationShares.cast<LocationShare?>().firstWhere(
      (l) => l?.userId == user.id, orElse: () => null,
    );
    final isSharing = myShare?.isSharing ?? false;
    final shareMap = {for (final l in locationShares) l.userId: l};

    final savedPlaces = provider.db.savedPlaces
        .where((p) => p.familyId == family.id)
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: AppTheme.stone700),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 20, color: AppTheme.primary),
            const SizedBox(width: 6),
            const Text('FamilyHub', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.primary)),
          ],
        ),
        centerTitle: false,
        titleSpacing: 0,
        actions: [
          IconButton(icon: const Icon(Icons.menu_rounded, color: AppTheme.stone500), onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'Family Location',
              subtitle: 'See where everyone is, safely and privately.',
              actions: [
                ActionChipButton(
                  icon: Icons.add_location_alt_outlined,
                  label: 'Add Place',
                  onTap: _showAddPlaceSheet,
                  backgroundColor: AppTheme.stone100,
                  foregroundColor: AppTheme.stone700,
                ),
              ],
            ),

            // ── Sharing Toggle ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSharing ? const Color(0xFFF0FDF4) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSharing ? const Color(0xFF86EFAC) : AppTheme.stone200,
                    width: 2,
                  ),
                ),
                child: Row(children: [
                  Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      color: isSharing ? AppTheme.success : AppTheme.stone200,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.navigation_rounded,
                      color: isSharing ? Colors.white : AppTheme.stone400,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      isSharing ? 'Sharing your location' : 'Location sharing is off',
                      style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.stone800),
                    ),
                    const SizedBox(height: 2),
                    if (isSharing && myShare != null)
                      Text(
                        myShare.nearPlace != null
                            ? '\u{1F4CD} ${myShare.nearPlace}'
                            : myShare.placeName != null
                                ? '\u{1F4CD} ${myShare.placeName}'
                                : 'Getting your location...',
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      )
                    else
                      const Text('Only you can see your location when off', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
                  ])),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _toggleSharing(myShare, !isSharing),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSharing ? AppTheme.stone200 : AppTheme.success,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: isSharing ? null : [
                          BoxShadow(color: AppTheme.success.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.power_settings_new_rounded, size: 16, color: isSharing ? AppTheme.stone700 : Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          isSharing ? 'Stop' : 'Share',
                          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: isSharing ? AppTheme.stone700 : Colors.white),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),

            // ── Family Members ──
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text('FAMILY', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1)),
            ),
            if (members.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('No family members found.', style: TextStyle(color: AppTheme.stone400)),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: members.map((member) {
                    final share = shareMap[member.id];
                    final isMe = member.id == user.id;
                    final memberName = provider.memberDisplayName(member);

                    // Distance calculation
                    String? distLabel;
                    if (!isMe && share?.isSharing == true && _lastPosition != null) {
                      final dist = _haversine(
                        _lastPosition!.latitude, _lastPosition!.longitude,
                        share!.latitude, share.longitude,
                      );
                      distLabel = _formatDistance(dist);
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.stone100),
                      ),
                      child: Row(children: [
                        Stack(children: [
                          UserAvatarWidget(name: memberName, radius: 22),
                          Positioned(
                            bottom: 0, right: 0,
                            child: Container(
                              width: 12, height: 12,
                              decoration: BoxDecoration(
                                color: share?.isSharing == true ? AppTheme.success : AppTheme.stone300,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                        ]),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Text(
                              memberName,
                              style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.stone900),
                            ),
                            if (isMe)
                              const Text(' (You)', style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone400)),
                          ]),
                          if (share?.isSharing == true) ...[
                            const SizedBox(height: 2),
                            Text(
                              share?.nearPlace != null
                                  ? '\u{1F4CD} ${share!.nearPlace}'
                                  : share?.placeName != null
                                      ? '\u{1F4CD} ${share!.placeName}'
                                      : 'Location shared',
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                            if (distLabel != null || share != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Row(children: [
                                  const Icon(Icons.schedule_rounded, size: 11, color: AppTheme.stone400),
                                  const SizedBox(width: 3),
                                  Text(_timeAgo(share!.updatedAt), style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
                                  if (distLabel != null) ...[
                                    const Text(' \u00B7 ', style: TextStyle(fontSize: 11, color: AppTheme.stone400)),
                                    Text(distLabel, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
                                  ],
                                ]),
                              ),
                          ] else
                            const Text('Not sharing location', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
                        ])),
                        // Google Maps navigation button
                        if (share?.isSharing == true && !isMe)
                          GestureDetector(
                            onTap: () => _openInMaps(share!.latitude, share.longitude),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryLight,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.navigation_rounded, size: 18, color: AppTheme.primary),
                            ),
                          ),
                      ]),
                    );
                  }).toList(),
                ),
              ),

            // ── Saved Places ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(children: [
                const Text('SAVED PLACES', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1)),
                const Spacer(),
                GestureDetector(
                  onTap: _showAddPlaceSheet,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, size: 14, color: AppTheme.primary),
                    const SizedBox(width: 2),
                    Text('Add', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                  ]),
                ),
              ]),
            ),
            if (savedPlaces.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.stone200, style: BorderStyle.solid),
                  ),
                  child: Column(children: [
                    Icon(Icons.location_on_outlined, size: 28, color: AppTheme.stone200),
                    const SizedBox(height: 8),
                    const Text('No saved places yet.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.stone400)),
                    const SizedBox(height: 2),
                    const Text('Add Home, School or Work to see when family arrives.', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
                  ]),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: savedPlaces.map((p) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.stone100),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(p.emoji ?? '\u{1F4CD}', style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.stone800)),
                        Text('${p.radiusMetres.round()} m radius', style: const TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.stone400)),
                      ]),
                      if (p.creatorId == user.id) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _deletePlace(p.id),
                          child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.stone300),
                        ),
                      ],
                    ]),
                  )).toList(),
                ),
              ),

            // ── Privacy Notice ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.stone50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.stone200),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.visibility_outlined, size: 16, color: AppTheme.stone400),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                    Text('Privacy', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.stone600)),
                    SizedBox(height: 2),
                    Text(
                      'Location is only visible to your family circle. You can stop sharing at any time. Locations update every 60 seconds while sharing is active.',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone500, height: 1.4),
                    ),
                  ])),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Add Place Bottom Sheet
// ─────────────────────────────────────────────

class _AddPlaceSheet extends StatefulWidget {
  final ({double lat, double lng})? currentPosition;
  final Future<void> Function(SavedPlace place) onSave;

  const _AddPlaceSheet({required this.currentPosition, required this.onSave});

  @override
  State<_AddPlaceSheet> createState() => _AddPlaceSheetState();
}

class _AddPlaceSheetState extends State<_AddPlaceSheet> {
  final _nameCtrl = TextEditingController();
  String _emoji = '\u{1F3E0}';
  double _radius = 200;

  static const _emojis = [
    '\u{1F3E0}', '\u{1F3EB}', '\u{1F4BC}', '\u{1F3E5}', '\u{1F6D2}',
    '\u{26EA}', '\u{1F3CB}\u{FE0F}', '\u{1F333}', '\u{1F355}', '\u{2B50}',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (_nameCtrl.text.trim().isEmpty || widget.currentPosition == null) return;
    final provider = context.read<AppProvider>();
    final place = SavedPlace(
      id: const Uuid().v4(),
      familyId: provider.activeFamily!.id,
      creatorId: provider.activeUser!.id,
      name: _nameCtrl.text.trim(),
      emoji: _emoji,
      latitude: widget.currentPosition!.lat,
      longitude: widget.currentPosition!.lng,
      radiusMetres: _radius,
      createdAt: DateTime.now(),
    );
    widget.onSave(place);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(children: [
              const Icon(Icons.add_location_alt_rounded, color: AppTheme.stone700, size: 22),
              const SizedBox(width: 8),
              const Expanded(child: Text('Save a Place', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 20, color: AppTheme.stone900))),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, size: 22, color: AppTheme.stone400),
              ),
            ]),
          ),
          Expanded(
            child: ListView(controller: controller, padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
              // Emoji picker
              const Text('Icon', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.stone700)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: _emojis.map((e) => GestureDetector(
                onTap: () => setState(() => _emoji = e),
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _emoji == e ? AppTheme.primary : AppTheme.stone200,
                      width: _emoji == e ? 2 : 1,
                    ),
                    color: _emoji == e ? AppTheme.primaryLight : Colors.white,
                  ),
                  child: Center(child: Text(e, style: const TextStyle(fontSize: 20))),
                ),
              )).toList()),
              const SizedBox(height: 20),

              // Name
              const Text('Place Name', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.stone700)),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  hintText: 'e.g. Home, School, Work',
                  filled: true,
                  fillColor: AppTheme.stone50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.stone200)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.stone200)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),
              const SizedBox(height: 20),

              // Location status
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.stone50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: widget.currentPosition != null
                    ? Row(children: [
                        const Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.success),
                        const SizedBox(width: 8),
                        Text(
                          'Using your current location (${widget.currentPosition!.lat.toStringAsFixed(4)}, ${widget.currentPosition!.lng.toStringAsFixed(4)})',
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.success),
                        ),
                      ])
                    : Row(children: const [
                        Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFD97706)),
                        SizedBox(width: 8),
                        Expanded(child: Text(
                          'Start sharing your location first, then add a place while you\'re there.',
                          style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Color(0xFFD97706)),
                        )),
                      ]),
              ),
              const SizedBox(height: 20),

              // Radius slider
              Row(children: [
                const Text('Detection Radius: ', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.stone700)),
                Text('${_radius.round()} m', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.primary)),
              ]),
              const SizedBox(height: 8),
              Slider(
                value: _radius,
                min: 50,
                max: 1000,
                divisions: 19,
                activeColor: AppTheme.primary,
                onChanged: (v) => setState(() => _radius = v),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
                Text('50 m (precise)', style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.stone400)),
                Text('1 km (loose)', style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.stone400)),
              ]),
              const SizedBox(height: 24),

              // Buttons
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.stone100,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(child: Text('Cancel', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.stone700))),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _save,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: widget.currentPosition != null && _nameCtrl.text.trim().isNotEmpty
                            ? AppTheme.primary
                            : AppTheme.primary.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(child: Text('Save Place', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white))),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
