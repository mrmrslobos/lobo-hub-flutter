// lib/screens/location/location_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  Future<void> _toggleSharing(LocationShare? current, bool sharing) async {
    final provider = context.read<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) return;
    final db = provider.db;

    if (current == null) {
      // Create new share entry
      final newShare = LocationShare(
        id: const Uuid().v4(),
        familyId: family.id,
        userId: user.id,
        latitude: 0.0,
        longitude: 0.0,
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

    // Build map: userId -> LocationShare
    final shareMap = {for (final l in locationShares) l.userId: l};

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
            const PageHeader(
              title: '\u{1F4CD} Family Location',
              subtitle: 'See where everyone is',
            ),
            // My sharing toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isSharing
                        ? [AppTheme.success, const Color(0xFF059669)]
                        : [AppTheme.stone600, AppTheme.stone500],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(children: [
                  Text(isSharing ? '\u{1F4CD}' : '\u{1F4F5}', style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(isSharing ? 'Sharing Location' : 'Location Hidden', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
                    Text(isSharing ? 'Family can see your location' : 'Tap to start sharing', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white70)),
                  ])),
                  Switch(
                    value: isSharing,
                    onChanged: (v) => _toggleSharing(myShare, v),
                    activeColor: Colors.white,
                    activeTrackColor: Colors.white.withOpacity(0.3),
                  ),
                ]),
              ),
            ),
            // Family members
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
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: members.length,
                  itemBuilder: (ctx, i) {
                    final member = members[i];
                    final share = shareMap[member.id];
                    final isMe = member.id == user.id;
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
                          UserAvatarWidget(name: member.name, radius: 22),
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
                          Text(
                            '${member.name}${isMe ? ' (You)' : ''}',
                            style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.stone900),
                          ),
                          if (share?.isSharing == true) ...[
                            const SizedBox(height: 2),
                            Text(
                              share?.address ?? 'Location shared',
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ] else
                            const Text('Location hidden', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
                        ])),
                        if (share != null)
                          Text(_timeAgo(share.updatedAt), style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
                      ]),
                    );
                  },
                ),
              ),
            // Map placeholder
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: AppTheme.stone100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.stone200),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.map_rounded, size: 48, color: AppTheme.stone300),
                  const SizedBox(height: 8),
                  const Text('Map view', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone400)),
                  const Text('Integrate maps package for live view', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone300)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
