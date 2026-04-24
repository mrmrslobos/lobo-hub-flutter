// lib/screens/photos/photos_screen.dart
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../config/cloud_sync_scope.dart';
import '../../config/module_config.dart';
import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/family_activity_service.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';
import '../../utils/debounce.dart';

const _reactionEmojis = ['❤️', '😍', '😂', '🥹', '🎉', '👏'];

Future<void> _reportContent(
  BuildContext context,
  String contentType,
  String contentId,
) async {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Report Content'),
      content: Text('Report this $contentType? The family admin will be notified.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () async {
            final provider = context.read<AppProvider>();
            final familyId = provider.activeFamily?.id;
            final actorUserId = provider.activeUser?.id;
            if (familyId != null && actorUserId != null) {
              final nextDb = FamilyActivityService.append(
                provider.db,
                familyId: familyId,
                actorUserId: actorUserId,
                action: 'content_reported',
                detail: '$contentType:$contentId',
              );
              await provider.saveAndSync(
                nextDb,
                pushTableScope: {CloudSyncScope.familyActivityLogs},
              );
            }
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('Report saved for family admin review'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ));
          },
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Report'),
        ),
      ],
    ),
  );
}

const _milestoneCategories = [
  (id: 'Firsts',        emoji: '⭐', icon: Icons.star_rounded,         color: Color(0xFFF59E0B)),
  (id: 'Growing Up',    emoji: '👶', icon: Icons.child_care_rounded,   color: Color(0xFFEC4899)),
  (id: 'School',        emoji: '🎒', icon: Icons.school_rounded,       color: Color(0xFF3B82F6)),
  (id: 'Activities',    emoji: '🏆', icon: Icons.emoji_events_rounded, color: Color(0xFF22C55E)),
  (id: 'Travel',        emoji: '✈️', icon: Icons.flight_rounded,       color: Color(0xFF0EA5E9)),
  (id: 'Celebrations',  emoji: '🎉', icon: Icons.celebration_rounded,  color: Color(0xFF8B5CF6)),
  (id: 'Health',        emoji: '❤️', icon: Icons.favorite_rounded,     color: Color(0xFFF43F5E)),
  (id: 'Family',        emoji: '👨‍👩‍👧', icon: Icons.people_rounded,       color: Color(0xFF6366F1)),
];

class PhotosScreen extends StatefulWidget {
  const PhotosScreen({super.key});

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  final _picker = ImagePicker();
  final _searchCtrl = TextEditingController();
  final _searchDebounce = Debouncer();
  int _tabIndex = 0;
  bool _isUploading = false;
  String _searchQuery = '';

  bool _isOwner(AppProvider provider) {
    final userId = provider.activeUser?.id;
    return userId != null && provider.activeFamily?.ownerId == userId;
  }

  bool _canManagePhoto(AppProvider provider, Photo photo) {
    final userId = provider.activeUser?.id;
    return userId != null && (photo.uploaderId == userId || _isOwner(provider));
  }

  bool _canManageMilestone(AppProvider provider, Milestone ms) {
    final userId = provider.activeUser?.id;
    return userId != null && (ms.childId == userId || _isOwner(provider));
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  bool _isNetworkUrl(String url) =>
      url.startsWith('http://') || url.startsWith('https://');

  Widget _photoImage(String url, {BoxFit fit = BoxFit.cover}) {
    if (_isNetworkUrl(url)) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        placeholder: (_, __) => _photoPlaceholder(),
        errorWidget: (_, __, ___) => _photoPlaceholder(),
      );
    }
    return Image.file(File(url), fit: fit,
        errorBuilder: (_, __, ___) => _photoPlaceholder());
  }

  Widget _photoPlaceholder() {
    return Container(
      color: AppTheme.stone100,
      child: const Center(
        child: Icon(Icons.image_outlined, color: AppTheme.stone300, size: 32),
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─── Photo Actions ──────────────────────────────────────────────────────────

  Future<void> _pickAndAddPhoto() async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    String? caption;
    if (mounted) {
      caption = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _CaptionSheet(),
      );
    }

    if (!mounted) return;
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final familyId = provider.activeFamily!.id;
    final photoId = const Uuid().v4();

    setState(() => _isUploading = true);

    final url = await SupabaseService.uploadPhoto(
      familyId: familyId,
      photoId: photoId,
      filePath: file.path,
    );

    if (!mounted) return;
    setState(() => _isUploading = false);

    final photo = Photo(
      id: photoId,
      familyId: familyId,
      uploaderId: provider.activeUser!.id,
      url: url,
      caption: caption?.isEmpty == true ? null : caption,
      tags: [],
      createdAt: DateTime.now(),
    );
    await provider.saveAndSync(
      db.copyWith(photos: [...db.photos, photo]),
      pushTableScope: CloudSyncScope.photoMilestoneBundle,
    );

    try {
      NotificationService.notifyFamilyActivityWithDb(
        provider.db,
        title: 'New photo added 📷',
        body: '${provider.activeUser?.name ?? 'Someone'} added a photo to the family album',
        path: '/photos',
        familyId: provider.activeFamily?.id,
        excludeUserId: provider.activeUser?.id,
      );
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Photo added!'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Future<void> _deletePhoto(String id) async {
    final provider = context.read<AppProvider>();
    final photo = provider.db.photos.cast<Photo?>().firstWhere(
      (p) => p?.id == id,
      orElse: () => null,
    );
    if (photo == null || !_canManagePhoto(provider, photo)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only the uploader or family owner can delete this photo.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
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
          const Text('Delete Photo', style: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
        content: const Text('This photo will be permanently deleted.', style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone600)),
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
    if (SupabaseService.isConfigured && _isNetworkUrl(photo.url)) {
      await SupabaseService.deleteFamilyPhotoFromStorage(photo.url);
    }
    final db = provider.db;
    await provider.saveAndSync(
      db.copyWith(photos: db.photos.where((p) => p.id != id).toList()),
      pushTableScope: CloudSyncScope.photoMilestoneBundle,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Photo deleted'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Future<void> _editCaption(Photo photo) async {
    final provider = context.read<AppProvider>();
    if (!_canManagePhoto(provider, photo)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the uploader or family owner can edit this caption.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final newCaption = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CaptionSheet(initialCaption: photo.caption),
    );
    if (newCaption == null || !mounted) return;

    final db = provider.db;
    final updatedPhotos = db.photos.map((p) {
      if (p.id != photo.id) return p;
      return FamilyPhoto(
        id: p.id,
        familyId: p.familyId,
        uploaderId: p.uploaderId,
        url: p.url,
        caption: newCaption.isEmpty ? null : newCaption,
        takenAt: p.takenAt,
        createdAt: p.createdAt,
        reactions: p.reactions,
        milestoneId: p.milestoneId,
        tags: p.tags,
        visibility: p.visibility,
      );
    }).toList();
    await provider.saveAndSync(
      db.copyWith(photos: updatedPhotos),
      pushTableScope: CloudSyncScope.photoMilestoneBundle,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Caption updated'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Future<void> _reactToPhoto(Photo photo, String emoji) async {
    final provider = context.read<AppProvider>();
    final userId = provider.activeUser?.id ?? '';
    final db = provider.db;

    final existing = photo.reactions.where((r) => r.userId == userId && r.emoji == emoji);
    List<Reaction> newReactions;
    if (existing.isNotEmpty) {
      newReactions = photo.reactions.where((r) => !(r.userId == userId && r.emoji == emoji)).toList();
    } else {
      newReactions = [...photo.reactions, Reaction(userId: userId, emoji: emoji)];
    }

    final updatedPhotos = db.photos.map((p) {
      if (p.id != photo.id) return p;
      return FamilyPhoto(
        id: p.id,
        familyId: p.familyId,
        uploaderId: p.uploaderId,
        url: p.url,
        caption: p.caption,
        takenAt: p.takenAt,
        createdAt: p.createdAt,
        reactions: newReactions,
        milestoneId: p.milestoneId,
        tags: p.tags,
        visibility: p.visibility,
      );
    }).toList();

    await provider.saveAndSync(
      db.copyWith(photos: updatedPhotos),
      pushTableScope: CloudSyncScope.photoMilestoneBundle,
    );
  }

  Future<void> _deleteMilestone(Milestone ms) async {
    final provider = context.read<AppProvider>();
    if (!_canManageMilestone(provider, ms)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only the milestone owner or family owner can delete this milestone.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
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
          const Text('Delete Milestone', style: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
        content: Text('Delete "${ms.title}"?', style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone600)),
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

    final db = provider.db;
    await provider.saveAndSync(
      db.copyWith(milestones: db.milestones.where((m) => m.id != ms.id).toList()),
      pushTableScope: CloudSyncScope.photoMilestoneBundle,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Milestone deleted'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  void _showAddMilestone({Milestone? editing}) {
    final provider = context.read<AppProvider>();
    if (editing != null && !_canManageMilestone(provider, editing)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the milestone owner or family owner can edit this milestone.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddMilestoneSheet(editing: editing),
    );
  }

  void _showPhotoActions(Photo photo) {
    final provider = context.read<AppProvider>();
    final canManage = _canManagePhoto(provider, photo);
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
                  child: const Icon(Icons.photo_rounded, size: 18, color: AppTheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    photo.caption ?? 'Photo',
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.stone900),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
            const Divider(height: 1, color: AppTheme.stone100),
            if (canManage)
              ListTile(
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.primary),
                ),
                title: const Text('Edit Caption', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _editCaption(photo);
                },
              ),
            ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.flag_outlined, size: 18, color: Colors.orange),
              ),
              title: const Text('Report Photo', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                _reportContent(context, 'photo', photo.id);
              },
            ),
            if (canManage)
              ListTile(
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.error),
                ),
                title: const Text('Delete Photo', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  _deletePhoto(photo.id);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showMilestoneActions(Milestone ms) {
    final provider = context.read<AppProvider>();
    final canManage = _canManageMilestone(provider, ms);
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
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(child: Text(ms.emoji ?? '⭐', style: const TextStyle(fontSize: 18))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ms.title,
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.stone900),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
            const Divider(height: 1, color: AppTheme.stone100),
            if (canManage)
              ListTile(
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.primary),
                ),
                title: const Text('Edit Milestone', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _showAddMilestone(editing: ms);
                },
              ),
            if (canManage)
              ListTile(
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.error),
                ),
                title: const Text('Delete Milestone', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMilestone(ms);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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

    final allPhotos = provider.db.photos.where((p) => p.familyId == family.id).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final allMilestones = provider.db.milestones.where((m) => m.familyId == family.id).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final q = _searchQuery.toLowerCase();
    final photos = q.isEmpty
        ? allPhotos
        : allPhotos.where((p) =>
            (p.caption ?? '').toLowerCase().contains(q) ||
            p.tags.any((t) => t.toLowerCase().contains(q))).toList();
    final milestones = q.isEmpty
        ? allMilestones
        : allMilestones.where((m) =>
            m.title.toLowerCase().contains(q) ||
            (m.notes ?? '').toLowerCase().contains(q) ||
            (m.category ?? '').toLowerCase().contains(q)).toList();

    // Group photos by month
    final byMonth = <String, List<Photo>>{};
    for (final p in photos) {
      final key = DateFormat('MMMM yyyy').format(p.createdAt);
      byMonth.putIfAbsent(key, () => []).add(p);
    }

    final totalReactions = photos.fold<int>(0, (n, p) => n + p.reactions.length);

    return Scaffold(
      // backgroundColor handled by theme
      drawer: const AppDrawer(),
      appBar: const MainAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header ───────────────────────────────────────────
            PageHeader(
              title: screenTitleForModulePath('/photos'),
              subtitle: 'Your private family album & milestone moments',
              actions: [
                ActionChipButton(
                  icon: Icons.star_rounded,
                  label: 'Milestone',
                  onTap: () => _showAddMilestone(),
                  backgroundColor: const Color(0xFFD97706),
                ),
                ActionChipButton(
                  icon: Icons.add_a_photo_rounded,
                  label: 'Add Photo',
                  onTap: _pickAndAddPhoto,
                  isPrimary: true,
                ),
              ],
            ),

            // ─── Search ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) {
                  _searchDebounce.run(() {
                    if (!mounted) return;
                    setState(() => _searchQuery = v);
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search photos & milestones...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _searchDebounce.cancel();
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  isDense: true,
                ),
              ),
            ),

            // ─── Upload progress ──────────────────────────────────
            if (_isUploading)
              Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                ),
                child: const Row(children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
                  SizedBox(width: 12),
                  Text('Uploading photo...', style: TextStyle(
                    fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.primary,
                  )),
                ]),
              ),

            // ─── Stat cards ───────────────────────────────────────
            if (photos.isNotEmpty || milestones.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(children: [
                  _MiniStat(
                    icon: Icons.image_rounded,
                    iconColor: AppTheme.primary,
                    value: '${photos.length}',
                    label: 'Photos',
                  ),
                  const SizedBox(width: 10),
                  _MiniStat(
                    icon: Icons.star_rounded,
                    iconColor: const Color(0xFFD97706),
                    value: '${milestones.length}',
                    label: 'Milestones',
                  ),
                  const SizedBox(width: 10),
                  _MiniStat(
                    icon: Icons.favorite_rounded,
                    iconColor: const Color(0xFFF43F5E),
                    value: '$totalReactions',
                    label: 'Reactions',
                  ),
                ]),
              ),

            // ─── Tabs ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AppTabBar(
                tabs: const ['Timeline', 'Milestones'],
                selectedIndex: _tabIndex,
                onSelected: (i) => setState(() => _tabIndex = i),
              ),
            ),
            const SizedBox(height: 16),

            // ─── Tab content ──────────────────────────────────────
            IndexedStack(
              index: _tabIndex,
              children: [
                _buildTimelineTab(photos, byMonth, provider),
                _buildMilestonesTab(milestones, provider),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Timeline Tab ───────────────────────────────────────────────────────────

  Widget _buildTimelineTab(List<Photo> photos, Map<String, List<Photo>> byMonth, AppProvider provider) {
    if (photos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: OnboardingCard(
          emoji: '\u{1F4F8}',
          title: 'No photos yet',
          bullets: [
            'Share photos with your family',
            'Capture and upload special moments',
            'View and manage shared memories',
          ],
          actionLabel: 'Add Photo',
          onAction: _pickAndAddPhoto,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: byMonth.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Month header – ALL CAPS section style
              Padding(
                padding: const EdgeInsets.only(bottom: 10, top: 4),
                child: Row(children: [
                  Text(
                    entry.key.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800,
                      color: AppTheme.stone400, letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${entry.value.length}',
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary),
                    ),
                  ),
                ]),
              ),
              // Photo grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemCount: entry.value.length,
                itemBuilder: (ctx, i) {
                  final photo = entry.value[i];
                  final uploaderName =
                      provider.displayNameForUserId(photo.uploadedBy);
                  return GestureDetector(
                    onTap: () => _openLightbox(context, photo, uploaderName, provider),
                    onLongPress: () => _showPhotoActions(photo),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(fit: StackFit.expand, children: [
                        _photoImage(photo.url),
                        // Reactions badge
                        if (photo.reactions.isNotEmpty)
                          Positioned(
                            top: 4, right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.favorite, size: 10, color: Colors.white),
                                const SizedBox(width: 2),
                                Text('${photo.reactions.length}', style: const TextStyle(
                                  color: Colors.white, fontSize: 9, fontFamily: 'Inter', fontWeight: FontWeight.w700,
                                )),
                              ]),
                            ),
                          ),
                        // Caption overlay
                        if (photo.caption != null)
                          Positioned(
                            bottom: 0, left: 0, right: 0,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(6, 12, 6, 4),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                                ),
                              ),
                              child: Text(
                                photo.caption!,
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontFamily: 'Inter', fontWeight: FontWeight.w500),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                      ]),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ─── Milestones Tab ─────────────────────────────────────────────────────────

  Widget _buildMilestonesTab(List<Milestone> milestones, AppProvider provider) {
    if (milestones.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: OnboardingCard(
          emoji: '⭐',
          title: 'No milestones yet',
          bullets: [
            'Record first steps, first words',
            'Track school achievements',
            'Celebrate family moments',
          ],
          actionLabel: 'Add Milestone',
          onAction: () => _showAddMilestone(),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: milestones.map((ms) {
          final catMeta = _milestoneCategories.firstWhere(
            (c) => c.id == ms.category,
            orElse: () => _milestoneCategories.first,
          );
          final childName = provider.userById(ms.childId)?.name; // FIXED: childId is non-nullable String

          return GestureDetector(
            onLongPress: () => _showMilestoneActions(ms),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.stone100),
              ),
              child: Row(children: [
                // Category icon
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: catMeta.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(ms.emoji ?? catMeta.emoji, style: const TextStyle(fontSize: 20)),
                  ),
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ms.title, style: const TextStyle(
                        fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.stone900,
                      )),
                      const SizedBox(height: 3),
                      Row(children: [
                        Icon(Icons.calendar_today_rounded, size: 11, color: AppTheme.stone400),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('MMM d, yyyy').format(ms.date),
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400),
                        ),
                        if (ms.ageLabel != null && ms.ageLabel!.isNotEmpty) ...[
                          const Text(' · ', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone300)),
                          Text(ms.ageLabel!, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
                        ],
                        if (childName != null) ...[
                          const Text(' · ', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone300)),
                          Text(childName.split(' ').first, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
                        ],
                      ]),
                      if (ms.notes != null && ms.notes!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(ms.notes!, style: const TextStyle(
                          fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500,
                        ), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Category badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: catMeta.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    catMeta.id,
                    style: TextStyle(
                      fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700,
                      color: catMeta.color,
                    ),
                  ),
                ),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Lightbox ───────────────────────────────────────────────────────────────

  void _openLightbox(BuildContext context, Photo photo, String uploaderName, AppProvider provider) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PhotoLightbox(
          photo: photo,
          uploaderName: uploaderName,
          onReact: (emoji) => _reactToPhoto(photo, emoji),
          onDelete: () {
            Navigator.pop(context);
            _deletePhoto(photo.id);
          },
          onEditCaption: () {
            Navigator.pop(context);
            _editCaption(photo);
          },
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

// ─── Caption Sheet ────────────────────────────────────────────────────────────

class _CaptionSheet extends StatefulWidget {
  final String? initialCaption;
  const _CaptionSheet({this.initialCaption});

  @override
  State<_CaptionSheet> createState() => _CaptionSheetState();
}

class _CaptionSheetState extends State<_CaptionSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialCaption);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialCaption != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.text_fields_rounded, size: 18, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isEditing ? 'Edit Caption' : 'Add Caption',
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.stone900),
                  ),
                ]),
                const SizedBox(height: 20),

                // Label
                const Text('Caption', style: TextStyle(
                  fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700,
                )),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Describe this moment...',
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

                Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, isEditing ? '' : null),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.stone200),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text(
                          isEditing ? 'Remove Caption' : 'Skip',
                          style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: AppTheme.stone600),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text(
                          isEditing ? 'Save' : 'Add',
                          style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Photo Lightbox ─────────────────────────────────────────────────────────

class _PhotoLightbox extends StatelessWidget {
  final Photo photo;
  final String uploaderName;
  final void Function(String emoji) onReact;
  final VoidCallback onDelete;
  final VoidCallback onEditCaption;

  const _PhotoLightbox({
    required this.photo,
    required this.uploaderName,
    required this.onReact,
    required this.onDelete,
    required this.onEditCaption,
  });

  bool get _isNetwork => photo.url.startsWith('http://') || photo.url.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          photo.caption ?? 'Photo',
          style: const TextStyle(color: Colors.white, fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.white70, size: 20),
            onPressed: onEditCaption,
            tooltip: 'Edit caption',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70, size: 20),
            onPressed: onDelete,
            tooltip: 'Delete photo',
          ),
        ],
      ),
      body: Column(children: [
        // Photo
        Expanded(
          child: Center(
            child: InteractiveViewer(
              child: _isNetwork
                  ? Image.network(photo.url, fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64))
                  : Image.file(File(photo.url), fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64)),
            ),
          ),
        ),
        // Info + reactions bar
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
          ),
          child: SafeArea(
            top: false,
            child: Column(children: [
              // Photo info row
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.person_outline_rounded, size: 12, color: Colors.white54),
                    const SizedBox(width: 4),
                    Text(uploaderName, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w500)),
                  ]),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.calendar_today_rounded, size: 11, color: Colors.white54),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('MMM d, yyyy').format(photo.createdAt),
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w500),
                    ),
                  ]),
                ),
                if (photo.reactions.isNotEmpty) ...[
                  const Spacer(),
                  Text(
                    '${photo.reactions.length} reaction${photo.reactions.length == 1 ? '' : 's'}',
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white38, fontWeight: FontWeight.w500),
                  ),
                ],
              ]),
              const SizedBox(height: 12),
              // Emoji reaction row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _reactionEmojis.map((emoji) {
                  final count = photo.reactions.where((r) => r.emoji == emoji).length;
                  return GestureDetector(
                    onTap: () => onReact(emoji),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: count > 0 ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: count > 0 ? Colors.white24 : Colors.white12),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(emoji, style: const TextStyle(fontSize: 18)),
                        if (count > 0) ...[
                          const SizedBox(width: 4),
                          Text('$count', style: const TextStyle(
                            fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white,
                          )),
                        ],
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ─── Add / Edit Milestone Sheet ─────────────────────────────────────────────

class _AddMilestoneSheet extends StatefulWidget {
  final Milestone? editing;
  const _AddMilestoneSheet({this.editing});

  @override
  State<_AddMilestoneSheet> createState() => _AddMilestoneSheetState();
}

class _AddMilestoneSheetState extends State<_AddMilestoneSheet> {
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _ageLabelCtrl = TextEditingController();
  late String _category;
  late String _emoji;
  late DateTime _date;
  bool _saving = false;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final ms = widget.editing!;
      _titleCtrl.text = ms.title;
      _notesCtrl.text = ms.notes ?? '';
      _ageLabelCtrl.text = ms.ageLabel ?? '';
      _category = ms.category ?? 'Firsts';
      _emoji = ms.emoji ?? '⭐';
      _date = ms.date;
    } else {
      _category = 'Firsts';
      _emoji = '⭐';
      _date = DateTime.now();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    _ageLabelCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please enter a title'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    setState(() => _saving = true);

    final provider = context.read<AppProvider>();
    final db = provider.db;

    if (_isEditing) {
      final updatedMilestones = db.milestones.map((m) {
        if (m.id != widget.editing!.id) return m;
        return Milestone(
          id: m.id,
          familyId: m.familyId,
          childId: m.childId,
          title: _titleCtrl.text.trim(),
          emoji: _emoji,
          category: _category,
          date: _date,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          ageLabel: _ageLabelCtrl.text.trim().isEmpty ? null : _ageLabelCtrl.text.trim(),
          createdAt: m.createdAt,
        );
      }).toList();
      await provider.saveAndSync(
        db.copyWith(milestones: updatedMilestones),
        pushTableScope: CloudSyncScope.photoMilestoneBundle,
      );
    } else {
      final milestone = Milestone(
        id: const Uuid().v4(),
        familyId: provider.activeFamily!.id,
        childId: provider.activeUser!.id,
        title: _titleCtrl.text.trim(),
        emoji: _emoji,
        category: _category,
        date: _date,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        ageLabel: _ageLabelCtrl.text.trim().isEmpty ? null : _ageLabelCtrl.text.trim(),
        createdAt: DateTime.now(),
      );
      await provider.saveAndSync(
        db.copyWith(milestones: [...db.milestones, milestone]),
        pushTableScope: CloudSyncScope.photoMilestoneBundle,
      );
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isEditing ? 'Milestone updated' : 'Milestone added!'),
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
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF59E0B)),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _isEditing ? 'Edit Milestone' : 'Add Milestone',
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.stone900),
                    ),
                  ]),
                  const SizedBox(height: 20),

                  // Category selector
                  const Text('CATEGORY', style: TextStyle(
                    fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800,
                    color: AppTheme.stone400, letterSpacing: 1.1,
                  )),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _milestoneCategories.map((cat) {
                      final isSelected = _category == cat.id;
                      return GestureDetector(
                        onTap: () => setState(() {
                          _category = cat.id;
                          _emoji = cat.emoji;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: isSelected ? cat.color.withValues(alpha: 0.12) : AppTheme.stone50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? cat.color : AppTheme.stone200,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(cat.emoji, style: const TextStyle(fontSize: 14)),
                            const SizedBox(width: 5),
                            Text(cat.id, style: TextStyle(
                              fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700,
                              color: isSelected ? cat.color : AppTheme.stone600,
                            )),
                          ]),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // Title
                  const Text('Title', style: TextStyle(
                    fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700,
                  )),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _titleCtrl,
                    autofocus: !_isEditing,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'e.g. First Steps',
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
                  const SizedBox(height: 16),

                  // Date picker
                  const Text('Date', style: TextStyle(
                    fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700,
                  )),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _pickDate,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.stone50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.stone200),
                      ),
                      child: Row(children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(Icons.calendar_today_rounded, size: 15, color: AppTheme.primary),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          DateFormat('EEEE, MMMM d, yyyy').format(_date),
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.stone800),
                        ),
                        const Spacer(),
                        const Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.stone400),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Age label
                  const Text('Age (optional)', style: TextStyle(
                    fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700,
                  )),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _ageLabelCtrl,
                    decoration: InputDecoration(
                      hintText: 'e.g. 11 months',
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
                  const SizedBox(height: 16),

                  // Notes
                  const Text('Notes (optional)', style: TextStyle(
                    fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700,
                  )),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Any notes about this moment...',
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
                              _isEditing ? 'Save Changes' : 'Add Milestone',
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
