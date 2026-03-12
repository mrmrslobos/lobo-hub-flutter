// lib/screens/photos/photos_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/supabase_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

const _reactionEmojis = ['❤️', '😍', '😂', '🥹', '🎉', '👏'];

const _milestoneCategories = [
  {'id': 'Firsts', 'emoji': '⭐', 'icon': Icons.star_rounded, 'color': Color(0xFFF59E0B)},
  {'id': 'Growing Up', 'emoji': '👶', 'icon': Icons.child_care_rounded, 'color': Color(0xFFEC4899)},
  {'id': 'School', 'emoji': '🎒', 'icon': Icons.school_rounded, 'color': Color(0xFF3B82F6)},
  {'id': 'Activities', 'emoji': '🏆', 'icon': Icons.emoji_events_rounded, 'color': Color(0xFF22C55E)},
  {'id': 'Travel', 'emoji': '✈️', 'icon': Icons.flight_rounded, 'color': Color(0xFF0EA5E9)},
  {'id': 'Celebrations', 'emoji': '🎉', 'icon': Icons.celebration_rounded, 'color': Color(0xFF8B5CF6)},
  {'id': 'Health', 'emoji': '❤️', 'icon': Icons.favorite_rounded, 'color': Color(0xFFF43F5E)},
  {'id': 'Family', 'emoji': '👨‍👩‍👧', 'icon': Icons.people_rounded, 'color': Color(0xFF6366F1)},
];

class PhotosScreen extends StatefulWidget {
  const PhotosScreen({super.key});

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> with SingleTickerProviderStateMixin {
  final _picker = ImagePicker();
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndAddPhoto() async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    String? caption;
    if (mounted) {
      caption = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController();
          return AlertDialog(
            title: const Text('Add Caption'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Caption (optional)'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Skip')),
              TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Add')),
            ],
          );
        },
      );
    }

    if (!mounted) return;
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final familyId = provider.activeFamily!.id;
    final photoId = const Uuid().v4();

    // Upload to Supabase Storage (falls back to local path on failure)
    final url = await SupabaseService.uploadPhoto(
      familyId: familyId,
      photoId: photoId,
      filePath: file.path,
    );

    if (!mounted) return;
    final photo = Photo(
      id: photoId,
      familyId: familyId,
      uploaderId: provider.activeUser!.id,
      url: url,
      caption: caption?.isEmpty == true ? null : caption,
      tags: [],
      createdAt: DateTime.now(),
    );
    await provider.saveAndSync(db.copyWith(photos: [...db.photos, photo]));
  }

  Future<void> _deletePhoto(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Photo'),
        content: const Text('Delete this photo permanently?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(photos: db.photos.where((p) => p.id != id).toList()));
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

    await provider.saveAndSync(db.copyWith(photos: updatedPhotos));
  }

  void _showAddMilestone() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _AddMilestoneSheet(),
    );
  }

  bool _isNetworkUrl(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  Widget _photoImage(String url, {BoxFit fit = BoxFit.cover}) {
    if (_isNetworkUrl(url)) {
      return Image.network(url, fit: fit, errorBuilder: (_, __, ___) => _photoPlaceholder());
    }
    return Image.file(File(url), fit: fit, errorBuilder: (_, __, ___) => _photoPlaceholder());
  }

  Widget _photoPlaceholder() {
    return Container(
      color: AppTheme.stone100,
      child: const Icon(Icons.image_outlined, color: AppTheme.stone300, size: 32),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final photos = provider.db.photos.where((p) => p.familyId == family.id).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final milestones = provider.db.milestones.where((m) => m.familyId == family.id).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    // Group photos by month
    final byMonth = <String, List<Photo>>{};
    for (final p in photos) {
      final key = DateFormat('MMMM yyyy').format(p.createdAt);
      byMonth.putIfAbsent(key, () => []).add(p);
    }

    final totalReactions = photos.fold<int>(0, (n, p) => n + p.reactions.length);

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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: '\u{1F4F8} Family Photos',
              subtitle: 'Your private family album & milestone moments',
              actions: [
                ActionChipButton(
                  icon: Icons.star_rounded,
                  label: 'Milestone',
                  onTap: _showAddMilestone,
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

            // Stats bar
            if (photos.isNotEmpty || milestones.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  children: [
                    _StatChip(icon: Icons.image_rounded, iconColor: AppTheme.primary, value: photos.length, label: 'Photos'),
                    const SizedBox(width: 8),
                    _StatChip(icon: Icons.star_rounded, iconColor: const Color(0xFFD97706), value: milestones.length, label: 'Milestones'),
                    const SizedBox(width: 8),
                    _StatChip(icon: Icons.favorite_rounded, iconColor: const Color(0xFFF43F5E), value: totalReactions, label: 'Reactions'),
                    const SizedBox(width: 8),
                    _StatChip(icon: Icons.calendar_month_rounded, iconColor: const Color(0xFF22C55E), value: byMonth.length, label: 'Months'),
                  ],
                ),
              ),

            // Tabs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.stone100,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(3),
                child: TabBar(
                  controller: _tabCtrl,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)],
                  ),
                  dividerColor: Colors.transparent,
                  labelColor: AppTheme.stone900,
                  unselectedLabelColor: AppTheme.stone400,
                  labelStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13),
                  unselectedLabelStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13),
                  tabs: const [
                    Tab(text: 'Timeline'),
                    Tab(text: 'Milestones'),
                  ],
                  onTap: (_) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Tab content
            IndexedStack(
              index: _tabCtrl.index,
              children: [
                // Timeline tab
                _buildTimelineTab(photos, byMonth, provider),
                // Milestones tab
                _buildMilestonesTab(milestones, provider),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineTab(List<Photo> photos, Map<String, List<Photo>> byMonth, AppProvider provider) {
    if (photos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: OnboardingCard(
          emoji: '\u{1F4F8}',
          title: 'No photos yet',
          bullets: ['Share photos with your family', 'Capture and upload special moments', 'View and manage shared memories'],
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
              // Month header
              Padding(
                padding: const EdgeInsets.only(bottom: 10, top: 4),
                child: Row(
                  children: [
                    Text(
                      entry.key,
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.stone700),
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
                  ],
                ),
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
                  final uploaderName = provider.userById(photo.uploadedBy)?.name ?? 'Member';
                  return GestureDetector(
                    onTap: () => _openLightbox(context, photo, uploaderName, provider),
                    onLongPress: () async {
                      final action = await showModalBottomSheet<String>(
                        context: context,
                        builder: (_) => SafeArea(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            ListTile(
                              leading: const Icon(Icons.delete_outline_rounded, color: AppTheme.error),
                              title: const Text('Delete photo', style: TextStyle(color: AppTheme.error)),
                              onTap: () => Navigator.pop(context, 'delete'),
                            ),
                            ListTile(
                              leading: const Icon(Icons.close_rounded),
                              title: const Text('Cancel'),
                              onTap: () => Navigator.pop(context),
                            ),
                          ]),
                        ),
                      );
                      if (action == 'delete') _deletePhoto(photo.id);
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(fit: StackFit.expand, children: [
                        _photoImage(photo.url),
                        // Reactions indicator
                        if (photo.reactions.isNotEmpty)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.favorite, size: 10, color: Colors.white),
                                const SizedBox(width: 2),
                                Text('${photo.reactions.length}', style: const TextStyle(color: Colors.white, fontSize: 9, fontFamily: 'Inter', fontWeight: FontWeight.w700)),
                              ]),
                            ),
                          ),
                        if (photo.caption != null)
                          Positioned(
                            bottom: 0, left: 0, right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                                ),
                              ),
                              child: Text(photo.caption!, style: const TextStyle(color: Colors.white, fontSize: 9, fontFamily: 'Inter'), maxLines: 1, overflow: TextOverflow.ellipsis),
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

  Widget _buildMilestonesTab(List<Milestone> milestones, AppProvider provider) {
    if (milestones.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: OnboardingCard(
          emoji: '⭐',
          title: 'No milestones yet',
          bullets: ['Record first steps, first words', 'Track school achievements', 'Celebrate family moments'],
          actionLabel: 'Add Milestone',
          onAction: _showAddMilestone,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: milestones.map((ms) {
          final catMeta = _milestoneCategories.firstWhere(
            (c) => c['id'] == ms.category,
            orElse: () => _milestoneCategories.first,
          );
          final childName = ms.childId != null ? provider.userById(ms.childId!)?.name : null;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.stone100),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (catMeta['color'] as Color).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(ms.emoji ?? catMeta['emoji'] as String, style: const TextStyle(fontSize: 20)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ms.title, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.stone900)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
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
                        ],
                      ),
                      if (ms.notes != null && ms.notes!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(ms.notes!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (catMeta['color'] as Color).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    catMeta['id'] as String,
                    style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: catMeta['color'] as Color),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  void _openLightbox(BuildContext context, Photo photo, String uploaderName, AppProvider provider) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PhotoLightbox(
          photo: photo,
          uploaderName: uploaderName,
          onReact: (emoji) => _reactToPhoto(photo, emoji),
          onDelete: () {
            _deletePhoto(photo.id);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }
}

// ─── Stat chip ──────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final int value;
  final String label;

  const _StatChip({required this.icon, required this.iconColor, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.stone100),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(height: 4),
            Text('$value', style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.stone800)),
            Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.stone400)),
          ],
        ),
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

  const _PhotoLightbox({required this.photo, required this.uploaderName, required this.onReact, required this.onDelete});

  bool get _isNetwork => photo.url.startsWith('http://') || photo.url.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(photo.caption ?? 'Photo', style: const TextStyle(color: Colors.white, fontFamily: 'Inter', fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70),
            onPressed: onDelete,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: InteractiveViewer(
                child: _isNetwork
                    ? Image.network(photo.url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.white, size: 64))
                    : Image.file(File(photo.url), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.white, size: 64)),
              ),
            ),
          ),
          // Reaction bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: Colors.black,
            child: Column(
              children: [
                // Photo info
                Row(
                  children: [
                    Text(
                      'By $uploaderName',
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white54),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('MMM d, yyyy').format(photo.createdAt),
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white54),
                    ),
                    if (photo.reactions.isNotEmpty) ...[
                      const Spacer(),
                      Text(
                        '${photo.reactions.length} reaction${photo.reactions.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white54),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                // Emoji reactions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _reactionEmojis.map((emoji) {
                    final count = photo.reactions.where((r) => r.emoji == emoji).length;
                    return GestureDetector(
                      onTap: () => onReact(emoji),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: count > 0 ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: count > 0 ? Colors.white24 : Colors.white12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(emoji, style: const TextStyle(fontSize: 18)),
                            if (count > 0) ...[
                              const SizedBox(width: 4),
                              Text('$count', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Add Milestone Sheet ────────────────────────────────────────────────────

class _AddMilestoneSheet extends StatefulWidget {
  const _AddMilestoneSheet();

  @override
  State<_AddMilestoneSheet> createState() => _AddMilestoneSheetState();
}

class _AddMilestoneSheetState extends State<_AddMilestoneSheet> {
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _ageLabelCtrl = TextEditingController();
  String _category = 'Firsts';
  String _emoji = '⭐';
  DateTime _date = DateTime.now();
  bool _saving = false;

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
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);

    final provider = context.read<AppProvider>();
    final db = provider.db;
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

    await provider.saveAndSync(db.copyWith(milestones: [...db.milestones, milestone]));
    if (mounted) Navigator.pop(context);
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
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Add Milestone', style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.stone900)),
                  const SizedBox(height: 16),

                  // Category selector
                  const Text('Category', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.stone500)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _milestoneCategories.map((cat) {
                      final isSelected = _category == cat['id'];
                      return GestureDetector(
                        onTap: () => setState(() {
                          _category = cat['id'] as String;
                          _emoji = cat['emoji'] as String;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? (cat['color'] as Color).withValues(alpha: 0.15) : AppTheme.stone50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? (cat['color'] as Color) : AppTheme.stone200,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(cat['emoji'] as String, style: const TextStyle(fontSize: 14)),
                            const SizedBox(width: 4),
                            Text(cat['id'] as String, style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: isSelected ? cat['color'] as Color : AppTheme.stone600)),
                          ]),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _titleCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Milestone Title *', hintText: "e.g. First Steps"),
                  ),
                  const SizedBox(height: 12),

                  GestureDetector(
                    onTap: _pickDate,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.stone50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.stone200),
                      ),
                      child: Row(children: [
                        const Icon(Icons.calendar_today_rounded, size: 16, color: AppTheme.stone500),
                        const SizedBox(width: 10),
                        Text(DateFormat('EEEE, MMMM d, yyyy').format(_date), style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone800)),
                        const Spacer(),
                        const Icon(Icons.edit_outlined, size: 14, color: AppTheme.stone400),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _ageLabelCtrl,
                    decoration: const InputDecoration(labelText: 'Age (optional)', hintText: 'e.g. 11 months'),
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Notes (optional)', alignLabelWithHint: true),
                  ),
                  const SizedBox(height: 20),

                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                        : const Text('Add Milestone'),
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
