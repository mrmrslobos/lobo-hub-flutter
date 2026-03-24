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
import '../../utils/debounce.dart';

// ─── Place emoji presets ──────────────────────────────────────────────────────

const _placeEmojis = [
  '\u{1F3E0}', // house
  '\u{1F3EB}', // school
  '\u{1F4BC}', // briefcase (work)
  '\u{1F3E5}', // hospital
  '\u{1F6D2}', // shopping cart
  '\u{26EA}',  // church
  '\u{1F3CB}\u{FE0F}', // gym
  '\u{1F333}', // park
  '\u{1F355}', // pizza (restaurant)
  '\u{2B50}',  // star (other)
];

// ─── Haversine helpers ────────────────────────────────────────────────────────

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

String _formatDistance(double metres) {
  if (metres < 1000) return '${metres.round()} m away';
  return '${(metres / 1000).toStringAsFixed(1)} km away';
}

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

// ─── Location Screen ──────────────────────────────────────────────────────────

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  Timer? _locationTimer;
  bool _permissionDenied = false;
  Position? _lastPosition;
  final _placeSearchCtrl = TextEditingController();
  final _placeSearchDebounce = Debouncer();
  String _placeSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _placeSearchCtrl.addListener(() {
      final t = _placeSearchCtrl.text;
      _placeSearchDebounce.run(() {
        if (mounted) setState(() => _placeSearchQuery = t);
      });
    });
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _placeSearchCtrl.dispose();
    _placeSearchDebounce.dispose();
    super.dispose();
  }

  // ─── Permission ─────────────────────────────────────────────────────────────

  Future<bool> _ensureLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) _showSnack('Please enable location services');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) _showSnack('Location permission denied');
        setState(() => _permissionDenied = true);
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) _showSnack('Location permission permanently denied. Please enable in Settings.');
      setState(() => _permissionDenied = true);
      return false;
    }

    setState(() => _permissionDenied = false);
    return true;
  }

  // ─── Location Updates ───────────────────────────────────────────────────────

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
          placeName = [p.name, p.street, p.subLocality, p.locality].where((s) => s != null && s.isNotEmpty).toSet().join(', ');
          nearPlace = [p.locality, p.administrativeArea, p.postalCode].where((s) => s != null && s.isNotEmpty).join(', ');
        }
      } catch (_) {}

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

  // ─── Sharing Toggle ─────────────────────────────────────────────────────────

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
              placeName = [p.name, p.street, p.subLocality, p.locality].where((s) => s != null && s.isNotEmpty).toSet().join(', ');
              nearPlace = [p.locality, p.administrativeArea, p.postalCode].where((s) => s != null && s.isNotEmpty).join(', ');
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
      if (mounted) _showSnack('Location sharing started');
    } else {
      _stopLocationUpdates();
      if (mounted) _showSnack('Location sharing stopped');
    }
  }

  // ─── Maps ───────────────────────────────────────────────────────────────────

  Future<void> _openInMaps(double lat, double lng) async {
    final uri = Uri.parse('https://maps.google.com/?q=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ─── Place CRUD ─────────────────────────────────────────────────────────────

  Future<void> _deletePlace(SavedPlace place) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.error),
          ),
          const SizedBox(width: 10),
          const Text('Delete Place', style: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
        content: Text('Remove "${place.name}" from saved places?', style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone600)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: AppTheme.stone500)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      savedPlaces: db.savedPlaces.where((p) => p.id != place.id).toList(),
    ));
    if (mounted) _showSnack('Place deleted');
  }

  void _showAddPlaceSheet({SavedPlace? editing}) {
    final pos = _lastPosition;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddPlaceSheet(
        currentPosition: pos != null ? (lat: pos.latitude, lng: pos.longitude) : null,
        editing: editing,
      ),
    );
  }

  void _showPlaceActions(SavedPlace place) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(child: Text(place.emoji ?? '\u{1F4CD}', style: const TextStyle(fontSize: 18))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    place.name,
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.stone900),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
            const Divider(height: 1, color: AppTheme.stone100),
            ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.primary),
              ),
              title: const Text('Edit Place', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                _showAddPlaceSheet(editing: place);
              },
            ),
            ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.navigation_rounded, size: 18, color: Color(0xFF3B82F6)),
              ),
              title: const Text('Open in Maps', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                _openInMaps(place.latitude, place.longitude);
              },
            ),
            ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.error),
              ),
              title: const Text('Delete Place', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.error)),
              onTap: () {
                Navigator.pop(context);
                _deletePlace(place);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

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
    final pq = _placeSearchQuery.trim().toLowerCase();
    final filteredPlaces = pq.isEmpty
        ? savedPlaces
        : savedPlaces
            .where((p) =>
                p.name.toLowerCase().contains(pq) ||
                (p.emoji != null && p.emoji!.toLowerCase().contains(pq)))
            .toList();

    final sharingCount = locationShares.where((l) => l.isSharing).length;

    return Scaffold(
      // backgroundColor handled by theme
      drawer: const AppDrawer(),
      appBar: const FamilyHubAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header ──────────────────────────────────────────
            PageHeader(
              title: '\u{1F4CD} Family Location',
              subtitle: 'See where everyone is, safely and privately',
              actions: [
                ActionChipButton(
                  icon: Icons.add_location_alt_outlined,
                  label: 'Add Place',
                  onTap: () => _showAddPlaceSheet(),
                  isPrimary: true,
                ),
              ],
            ),

            // ─── Stat cards ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(children: [
                _MiniStat(
                  icon: Icons.people_rounded,
                  iconColor: AppTheme.primary,
                  value: '${members.length}',
                  label: 'Members',
                ),
                const SizedBox(width: 10),
                _MiniStat(
                  icon: Icons.share_location_rounded,
                  iconColor: AppTheme.success,
                  value: '$sharingCount',
                  label: 'Sharing',
                ),
                const SizedBox(width: 10),
                _MiniStat(
                  icon: Icons.place_rounded,
                  iconColor: const Color(0xFFD97706),
                  value: '${savedPlaces.length}',
                  label: 'Places',
                ),
              ]),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: TextField(
                controller: _placeSearchCtrl,
                style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search saved places…',
                  hintStyle: const TextStyle(fontFamily: 'Inter', color: AppTheme.stone400),
                  prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.stone400),
                  suffixIcon: _placeSearchQuery.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.stone400),
                          onPressed: () {
                            _placeSearchCtrl.clear();
                            setState(() => _placeSearchQuery = '');
                          },
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.stone200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.stone200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            // ─── Sharing Toggle ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSharing ? const Color(0xFFF0FDF4) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSharing ? const Color(0xFF86EFAC) : AppTheme.stone200,
                    width: isSharing ? 1.5 : 1,
                  ),
                ),
                child: Row(children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: isSharing ? AppTheme.success.withValues(alpha: 0.15) : AppTheme.stone100,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isSharing ? Icons.navigation_rounded : Icons.navigation_outlined,
                      color: isSharing ? AppTheme.success : AppTheme.stone400,
                      size: 22,
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
                        myShare.placeName != null
                            ? '\u{1F4CD} ${myShare.placeName}'
                            : myShare.nearPlace != null
                                ? '\u{1F4CD} ${myShare.nearPlace}'
                                : 'Getting your location...',
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      )
                    else
                      const Text('Only visible to your family circle', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
                  ])),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label: isSharing ? 'Stop sharing your location' : 'Start sharing your location',
                    child: GestureDetector(
                    onTap: () => _toggleSharing(myShare, !isSharing),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSharing ? AppTheme.stone100 : AppTheme.success,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: isSharing ? null : [
                          BoxShadow(color: AppTheme.success.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          isSharing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                          size: 16,
                          color: isSharing ? AppTheme.stone600 : Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isSharing ? 'Stop' : 'Share',
                          style: TextStyle(
                            fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13,
                            color: isSharing ? AppTheme.stone600 : Colors.white,
                          ),
                        ),
                      ]),
                    ),
                  ),
                  ),
                ]),
              ),
            ),

            // ─── Permission denied banner ────────────────────────
            if (_permissionDenied)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFD97706)),
                    const SizedBox(width: 10),
                    const Expanded(child: Text(
                      'Location permission denied. Enable it in your device settings to share your location.',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Color(0xFF92400E), height: 1.3),
                    )),
                  ]),
                ),
              ),

            // ─── Family Members ──────────────────────────────────
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 10),
              child: Text('FAMILY MEMBERS', style: TextStyle(
                fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800,
                color: AppTheme.stone400, letterSpacing: 1.1,
              )),
            ),
            if (members.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.stone100),
                  ),
                  child: Column(children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: AppTheme.stone100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.people_outline_rounded, size: 28, color: AppTheme.stone300),
                    ),
                    const SizedBox(height: 12),
                    const Text('No family members', style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.stone700)),
                    const SizedBox(height: 4),
                    const Text('Invite family members to see their locations', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400)),
                  ]),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: members.map((member) {
                    final share = shareMap[member.id];
                    final isMe = member.id == user.id;
                    final memberName = provider.memberDisplayName(member);

                    String? distLabel;
                    if (!isMe && share?.isSharing == true && _lastPosition != null) {
                      final dist = _haversine(
                        _lastPosition!.latitude, _lastPosition!.longitude,
                        share!.latitude, share.longitude,
                      );
                      distLabel = _formatDistance(dist);
                    }

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.stone100),
                      ),
                      child: Row(children: [
                        // Avatar with status dot
                        Stack(children: [
                          AvatarInitials(name: memberName, size: 44),
                          Positioned(
                            bottom: 0, right: 0,
                            child: Container(
                              width: 14, height: 14,
                              decoration: BoxDecoration(
                                color: share?.isSharing == true ? AppTheme.success : AppTheme.stone300,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2.5),
                              ),
                            ),
                          ),
                        ]),
                        const SizedBox(width: 12),
                        // Info
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Text(
                              memberName,
                              style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.stone900),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryLight,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('You', style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                              ),
                            ],
                          ]),
                          const SizedBox(height: 3),
                          if (share?.isSharing == true) ...[
                            Text(
                              share?.placeName != null
                                  ? '\u{1F4CD} ${share!.placeName}'
                                  : share?.nearPlace != null
                                      ? '\u{1F4CD} ${share!.nearPlace}'
                                      : 'Location shared',
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                            if (share != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Row(children: [
                                  const Icon(Icons.schedule_rounded, size: 11, color: AppTheme.stone400),
                                  const SizedBox(width: 3),
                                  Text(_timeAgo(share.updatedAt), style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
                                  if (distLabel != null) ...[
                                    const Text(' \u00B7 ', style: TextStyle(fontSize: 11, color: AppTheme.stone400)),
                                    Text(distLabel, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
                                  ],
                                ]),
                              ),
                          ] else
                            const Text('Not sharing location', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
                        ])),
                        // Navigate button
                        if (share?.isSharing == true && !isMe)
                          Semantics(
                            button: true,
                            label: 'Open directions to $memberName in maps',
                            child: GestureDetector(
                            onTap: () => _openInMaps(share!.latitude, share.longitude),
                            child: Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.navigation_rounded, size: 18, color: AppTheme.primary),
                            ),
                          ),
                          ),
                      ]),
                    );
                  }).toList(),
                ),
              ),

            // ─── Saved Places ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 20, 10),
              child: Row(children: [
                const Text('SAVED PLACES', style: TextStyle(
                  fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800,
                  color: AppTheme.stone400, letterSpacing: 1.1,
                )),
                const Spacer(),
                GestureDetector(
                  onTap: () => _showAddPlaceSheet(),
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
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.stone100),
                  ),
                  child: Column(children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: AppTheme.stone100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.place_outlined, size: 28, color: AppTheme.stone300),
                    ),
                    const SizedBox(height: 12),
                    const Text('No saved places', style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.stone700)),
                    const SizedBox(height: 4),
                    const Text('Add Home, School or Work to see when family arrives', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400)),
                  ]),
                ),
              )
            else if (filteredPlaces.isEmpty && pq.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: OnboardingCard(
                  emoji: '🔎',
                  title: 'No place matches',
                  bullets: const ['Try another name', 'Clear search to see all places'],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: filteredPlaces.map((place) {
                    return GestureDetector(
                      onLongPress: () => _showPlaceActions(place),
                      onTap: () => _showPlaceActions(place),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.stone100),
                        ),
                        child: Row(children: [
                          Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(child: Text(place.emoji ?? '\u{1F4CD}', style: const TextStyle(fontSize: 22))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(place.name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.stone800)),
                            const SizedBox(height: 2),
                            Row(children: [
                              Icon(Icons.radar_rounded, size: 11, color: AppTheme.stone400),
                              const SizedBox(width: 4),
                              Text('${place.radiusMetres.round()} m radius', style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
                            ]),
                          ])),
                          const Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.stone300),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ),

            // ─── Privacy Notice ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.stone50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.stone100),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.stone200,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.shield_outlined, size: 16, color: AppTheme.stone500),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                    Text('Privacy & Security', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.stone700)),
                    SizedBox(height: 4),
                    Text(
                      'Location is only visible to your family circle. You can stop sharing at any time. Locations update every 60 seconds while sharing is active.',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500, height: 1.4),
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

// ─── Mini Stat Card ───────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _MiniStat({required this.icon, required this.iconColor, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.stone100),
        ),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(
                  fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.stone800,
                )),
                Text(label, style: const TextStyle(
                  fontFamily: 'Inter', fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.stone400,
                )),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Add / Edit Place Sheet ──────────────────────────────────────────────────

class _AddPlaceSheet extends StatefulWidget {
  final ({double lat, double lng})? currentPosition;
  final SavedPlace? editing;

  const _AddPlaceSheet({required this.currentPosition, this.editing});

  @override
  State<_AddPlaceSheet> createState() => _AddPlaceSheetState();
}

class _AddPlaceSheetState extends State<_AddPlaceSheet> {
  final _nameCtrl = TextEditingController();
  late String _emoji;
  late double _radius;
  bool _saving = false;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _nameCtrl.text = widget.editing!.name;
      _emoji = widget.editing!.emoji ?? '\u{1F3E0}';
      _radius = widget.editing!.radiusMetres;
    } else {
      _emoji = '\u{1F3E0}';
      _radius = 200;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please enter a place name'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }

    final pos = widget.currentPosition;
    if (pos == null && !_isEditing) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Location not available. Start sharing first.'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }

    setState(() => _saving = true);
    final provider = context.read<AppProvider>();
    final db = provider.db;

    if (_isEditing) {
      final updated = db.savedPlaces.map((p) {
        if (p.id != widget.editing!.id) return p;
        return SavedPlace(
          id: p.id,
          familyId: p.familyId,
          creatorId: p.creatorId,
          name: _nameCtrl.text.trim(),
          emoji: _emoji,
          latitude: pos?.lat ?? p.latitude,
          longitude: pos?.lng ?? p.longitude,
          radiusMetres: _radius,
          createdAt: p.createdAt,
        );
      }).toList();
      await provider.saveAndSync(db.copyWith(savedPlaces: updated));
    } else {
      final place = SavedPlace(
        id: const Uuid().v4(),
        familyId: provider.activeFamily!.id,
        creatorId: provider.activeUser!.id,
        name: _nameCtrl.text.trim(),
        emoji: _emoji,
        latitude: pos!.lat,
        longitude: pos.lng,
        radiusMetres: _radius,
        createdAt: DateTime.now(),
      );
      await provider.saveAndSync(db.copyWith(savedPlaces: [...db.savedPlaces, place]));
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isEditing ? 'Place updated' : 'Place saved!'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header with icon badge
                  Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.add_location_alt_rounded, size: 18, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _isEditing ? 'Edit Place' : 'Save a Place',
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.stone900),
                    ),
                  ]),
                  const SizedBox(height: 20),

                  // Icon selector
                  const Text('Icon', style: TextStyle(
                    fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700,
                  )),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _placeEmojis.map((e) {
                      final isSelected = _emoji == e;
                      return GestureDetector(
                        onTap: () => setState(() => _emoji = e),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? AppTheme.primary : AppTheme.stone200,
                              width: isSelected ? 2 : 1,
                            ),
                            color: isSelected ? AppTheme.primaryLight : AppTheme.stone50,
                          ),
                          child: Center(child: Text(e, style: const TextStyle(fontSize: 22))),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // Place name
                  const Text('Place Name', style: TextStyle(
                    fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700,
                  )),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameCtrl,
                    autofocus: !_isEditing,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: 'e.g. Home, School, Work',
                      hintStyle: const TextStyle(color: AppTheme.stone300),
                      filled: true,
                      fillColor: AppTheme.stone50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppTheme.stone200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppTheme.stone200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Location status
                  if (!_isEditing)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: widget.currentPosition != null
                            ? const Color(0xFFF0FDF4)
                            : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: widget.currentPosition != null
                              ? const Color(0xFFBBF7D0)
                              : const Color(0xFFFDE68A),
                        ),
                      ),
                      child: widget.currentPosition != null
                          ? Row(children: [
                              const Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.success),
                              const SizedBox(width: 8),
                              Expanded(child: Text(
                                'Using your current location (${widget.currentPosition!.lat.toStringAsFixed(4)}, ${widget.currentPosition!.lng.toStringAsFixed(4)})',
                                style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.success),
                              )),
                            ])
                          : Row(children: const [
                              Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFD97706)),
                              SizedBox(width: 8),
                              Expanded(child: Text(
                                'Start sharing your location first, then add a place while you\'re there.',
                                style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Color(0xFF92400E)),
                              )),
                            ]),
                    ),

                  // Radius slider
                  const Text('Detection Radius', style: TextStyle(
                    fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700,
                  )),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: AppTheme.primary,
                          inactiveTrackColor: AppTheme.stone200,
                          thumbColor: AppTheme.primary,
                          overlayColor: AppTheme.primary.withValues(alpha: 0.1),
                        ),
                        child: Slider(
                          value: _radius,
                          min: 50,
                          max: 1000,
                          divisions: 19,
                          onChanged: (v) => setState(() => _radius = v),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_radius.round()} m',
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary),
                      ),
                    ),
                  ]),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
                      Text('50 m (precise)', style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.stone400)),
                      Text('1 km (loose)', style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.stone400)),
                    ]),
                  ),
                  const SizedBox(height: 24),

                  // Save button
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                          : Text(
                              _isEditing ? 'Save Changes' : 'Save Place',
                              style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
