// lib/screens/photos/photos_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

class PhotosScreen extends StatefulWidget {
  const PhotosScreen({super.key});

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  final _picker = ImagePicker();

  Future<void> _pickAndAddPhoto() async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    // Ask for caption
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
              TextButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Add'),
              ),
            ],
          );
        },
      );
    }

    if (!mounted) return;
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final photo = Photo(
      id: const Uuid().v4(),
      familyId: provider.activeFamily!.id,
      uploadedBy: provider.activeUser!.id,
      url: file.path,
      caption: caption?.isEmpty == true ? null : caption,
      tags: [],
      createdAt: DateTime.now(),
    );
    await provider.saveAndSync(db.copyWith(photos: [...db.photos, photo]));
  }

  Future<void> _deletePhoto(String id) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(photos: db.photos.where((p) => p.id != id).toList()));
  }

  void _viewPhoto(BuildContext context, Photo photo, String uploaderName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PhotoViewScreen(photo: photo, uploaderName: uploaderName),
      ),
    );
  }

  bool _isNetworkUrl(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final photos = provider.db.photos.where((p) => p.familyId == family.id).toList();
    photos.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickAndAddPhoto,
        child: const Icon(Icons.add_a_photo_rounded),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('Photos'),
            floating: true,
            actions: [
              IconButton(icon: const Icon(Icons.add_a_photo_rounded), onPressed: _pickAndAddPhoto, tooltip: 'Add photo'),
            ],
          ),
          photos.isEmpty
              ? SliverFillRemaining(
                  child: EmptyState(
                    emoji: '📸',
                    title: 'No photos yet',
                    subtitle: 'Upload photos to share with your family.',
                    actionLabel: 'Add Photo',
                    onAction: _pickAndAddPhoto,
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final photo = photos[i];
                        final uploaderName = provider.userById(photo.uploadedBy)?.name ?? 'Member';
                        return GestureDetector(
                          onTap: () => _viewPhoto(context, photo, uploaderName),
                          onLongPress: () async {
                            final action = await showModalBottomSheet<String>(
                              context: context,
                              builder: (_) => SafeArea(
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  ListTile(leading: const Icon(Icons.delete_outline_rounded, color: AppTheme.error), title: const Text('Delete photo', style: TextStyle(color: AppTheme.error)), onTap: () => Navigator.pop(context, 'delete')),
                                  ListTile(leading: const Icon(Icons.close_rounded), title: const Text('Cancel'), onTap: () => Navigator.pop(context)),
                                ]),
                              ),
                            );
                            if (action == 'delete') _deletePhoto(photo.id);
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Stack(fit: StackFit.expand, children: [
                              _isNetworkUrl(photo.url)
                                  ? Image.network(photo.url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _photoPlaceholder())
                                  : Image.file(File(photo.url), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _photoPlaceholder()),
                              if (photo.caption != null)
                                Positioned(
                                  bottom: 0, left: 0, right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                                      ),
                                    ),
                                    child: Text(photo.caption!, style: const TextStyle(color: Colors.white, fontSize: 9, fontFamily: 'Inter'), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                            ]),
                          ),
                        );
                      },
                      childCount: photos.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _photoPlaceholder() {
    return Container(
      color: AppTheme.stone100,
      child: const Icon(Icons.image_outlined, color: AppTheme.stone300, size: 32),
    );
  }
}

// ─────────────────────────────────────────────
// Photo full-screen view
// ─────────────────────────────────────────────

class _PhotoViewScreen extends StatelessWidget {
  final Photo photo;
  final String uploaderName;

  const _PhotoViewScreen({required this.photo, required this.uploaderName});

  bool get _isNetwork => photo.url.startsWith('http://') || photo.url.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(photo.caption ?? 'Photo', style: const TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded, color: Colors.white),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (_) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (photo.caption != null) ...[
                      Text(photo.caption!, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 8),
                    ],
                    Text('Uploaded by: $uploaderName', style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone600)),
                    const SizedBox(height: 4),
                    Text('Date: ${photo.createdAt.toLocal().toString().split(' ').first}', style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone600)),
                  ]),
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          child: _isNetwork
              ? Image.network(photo.url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.white, size: 64))
              : Image.file(File(photo.url), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.white, size: 64)),
        ),
      ),
    );
  }
}
