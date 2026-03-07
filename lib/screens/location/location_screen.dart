// lib/screens/location/location_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';

const _locationUuid = Uuid();

// ─────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────

String _timeSince(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

// ─────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────

class LocationScreen extends StatelessWidget {
  const LocationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final db = provider.db;
    final familyId = provider.activeFamily?.id ?? '';
    final userId = provider.activeUser?.id ?? '';

    final memberUserIds = db.familyMembers
        .where((m) => m.familyId == familyId)
        .map((m) => m.userId)
        .toList();

    final members = db.users
        .where((u) => memberUserIds.contains(u.id))
        .toList();

    final shares = db.locationShares
        .where((l) => l.familyId == familyId)
        .toList();

    final myShare = shares
        .cast<LocationShare?>()
        .firstWhere((l) => l?.userId == userId, orElse: () => null);

    return Scaffold(
      appBar: AppBar(title: const Text('Location Sharing')),
      drawer: const AppDrawer(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _MySharingCard(
            myShare: myShare,
            userId: userId,
            familyId: familyId,
            provider: provider,
            db: db,
          ),
          const SizedBox(height: 20),
          const Text(
            'Family Members',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 10),
          if (members.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No family members found.',
                    style: TextStyle(color: Color(0xFF78716C))),
              ),
            )
          else
            ...members
                .where((u) => u.id != userId)
                .map((u) {
              final share = shares
                  .cast<LocationShare?>()
                  .firstWhere((l) => l?.userId == u.id, orElse: () => null);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MemberLocationCard(user: u, share: share),
              );
            }),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Saved Places',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              TextButton.icon(
                onPressed: () => _showAddPlaceDialog(
                    context, provider, familyId, userId),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._savedPlaces(shares).map((address) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SavedPlaceCard(name: address),
              )),
          if (_savedPlaces(shares).isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Text('📍', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 12),
                  Text('No saved places yet',
                      style: TextStyle(color: Color(0xFF78716C))),
                ],
              ),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  List<String> _savedPlaces(List<LocationShare> shares) {
    final seen = <String>{};
    final result = <String>[];
    for (final s in shares) {
      if (s.address != null &&
          s.address!.isNotEmpty &&
          !s.isSharing &&
          !seen.contains(s.address)) {
        seen.add(s.address!);
        result.add(s.address!);
      }
    }
    return result;
  }

  void _showAddPlaceDialog(BuildContext context, AppProvider provider,
      String familyId, String userId) {
    showDialog(
      context: context,
      builder: (ctx) =>
          _AddPlaceDialog(provider: provider, familyId: familyId, userId: userId),
    );
  }
}

// ─────────────────────────────────────────────
// My Sharing Card
// ─────────────────────────────────────────────

class _MySharingCard extends StatelessWidget {
  const _MySharingCard({
    required this.myShare,
    required this.userId,
    required this.familyId,
    required this.provider,
    required this.db,
  });
  final LocationShare? myShare;
  final String userId;
  final String familyId;
  final AppProvider provider;
  final AppDB db;

  @override
  Widget build(BuildContext context) {
    final isSharing = myShare?.isSharing ?? false;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: isSharing
            ? const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF6366F1)])
            : null,
        color: isSharing ? null : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isSharing
            ? null
            : Border.all(color: const Color(0xFFE7E5E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                isSharing ? '📡' : '📍',
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Location',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: isSharing
                            ? Colors.white
                            : const Color(0xFF1C1917),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isSharing
                          ? (myShare?.address ?? 'Sharing location')
                          : 'Not sharing',
                      style: TextStyle(
                        fontSize: 12,
                        color: isSharing
                            ? Colors.white70
                            : const Color(0xFF78716C),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Switch(
                value: isSharing,
                onChanged: (val) => _toggleSharing(context, val),
                activeColor: Colors.white,
                activeTrackColor: Colors.white.withOpacity(0.3),
              ),
            ],
          ),
          if (isSharing) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.circle,
                    size: 8, color: Color(0xFF86EFAC)),
                const SizedBox(width: 6),
                Text(
                  'Updated ${_timeSince(myShare!.updatedAt)}',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.white),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _toggleSharing(BuildContext context, bool newValue) {
    final now = DateTime.now();
    final List<LocationShare> updated;

    if (myShare == null) {
      updated = [
        ...db.locationShares,
        LocationShare(
          id: _locationUuid.v4(),
          familyId: familyId,
          userId: userId,
          latitude: 0.0,
          longitude: 0.0,
          address: 'Current location',
          updatedAt: now,
          isSharing: newValue,
        ),
      ];
    } else {
      updated = db.locationShares.map((l) {
        if (l.id != myShare!.id) return l;
        return LocationShare(
          id: l.id,
          familyId: l.familyId,
          userId: l.userId,
          latitude: l.latitude,
          longitude: l.longitude,
          address: l.address,
          updatedAt: now,
          isSharing: newValue,
        );
      }).toList();
    }

    provider.saveAndSync(db.copyWith(locationShares: updated));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newValue
            ? 'Location sharing enabled'
            : 'Location sharing disabled')));
  }
}

// ─────────────────────────────────────────────
// Member Location Card
// ─────────────────────────────────────────────

class _MemberLocationCard extends StatelessWidget {
  const _MemberLocationCard({required this.user, required this.share});
  final User user;
  final LocationShare? share;

  @override
  Widget build(BuildContext context) {
    final isSharing = share?.isSharing ?? false;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7E5E4)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.12),
              borderRadius: BorderRadius.circular(22),
            ),
            alignment: Alignment.center,
            child: Text(
              user.initials,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Color(0xFF4F46E5),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      isSharing
                          ? Icons.location_on
                          : Icons.location_off,
                      size: 13,
                      color: isSharing
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFA8A29E),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        isSharing
                            ? (share?.address ?? 'Unknown location')
                            : 'Not sharing',
                        style: TextStyle(
                          fontSize: 12,
                          color: isSharing
                              ? const Color(0xFF44403C)
                              : const Color(0xFFA8A29E),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isSharing
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF78716C))
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isSharing ? 'Sharing' : 'Off',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isSharing
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF78716C),
                  ),
                ),
              ),
              if (share != null) ...[
                const SizedBox(height: 4),
                Text(
                  _timeSince(share!.updatedAt),
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFFA8A29E)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Saved Place Card
// ─────────────────────────────────────────────

class _SavedPlaceCard extends StatelessWidget {
  const _SavedPlaceCard({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7E5E4)),
      ),
      child: Row(
        children: [
          const Text('📍', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          const Icon(Icons.chevron_right,
              color: Color(0xFFA8A29E), size: 20),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Add Place Dialog
// ─────────────────────────────────────────────

class _AddPlaceDialog extends StatefulWidget {
  const _AddPlaceDialog({
    required this.provider,
    required this.familyId,
    required this.userId,
  });
  final AppProvider provider;
  final String familyId;
  final String userId;

  @override
  State<_AddPlaceDialog> createState() => _AddPlaceDialogState();
}

class _AddPlaceDialogState extends State<_AddPlaceDialog> {
  final _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Saved Place'),
      content: TextField(
        controller: _nameCtrl,
        decoration: const InputDecoration(
          labelText: 'Place name',
          hintText: 'e.g. Home, School, Work',
        ),
        textCapitalization: TextCapitalization.words,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_nameCtrl.text.trim().isNotEmpty) {
              final db = widget.provider.db;
              widget.provider.saveAndSync(db.copyWith(locationShares: [
                ...db.locationShares,
                LocationShare(
                  id: _locationUuid.v4(),
                  familyId: widget.familyId,
                  userId: widget.userId,
                  latitude: 0.0,
                  longitude: 0.0,
                  address: _nameCtrl.text.trim(),
                  updatedAt: DateTime.now(),
                  isSharing: false,
                ),
              ]));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Place saved!')));
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
