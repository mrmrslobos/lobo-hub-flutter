import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/exercise_db_service.dart';

/// Shows exercise GIF/image; uses RapidAPI headers when URL is ExerciseDB on RapidAPI.
class ExerciseMediaImage extends StatefulWidget {
  final String? imageUrl;
  final String? exerciseDbId;
  final double? width;
  final double? height;
  final BoxFit fit;

  const ExerciseMediaImage({
    super.key,
    required this.imageUrl,
    this.exerciseDbId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  static bool _needsRapidAuth(String url) =>
      url.contains('exercisedb.p.rapidapi.com');

  @override
  State<ExerciseMediaImage> createState() => _ExerciseMediaImageState();
}

class _ExerciseMediaImageState extends State<ExerciseMediaImage> {
  Uint8List? _bytes;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ExerciseMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.exerciseDbId != widget.exerciseDbId) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final url = widget.imageUrl?.trim();
    if (url == null || url.isEmpty) {
      setState(() => _failed = true);
      return;
    }
    if (!ExerciseMediaImage._needsRapidAuth(url)) {
      return;
    }
    if (!ExerciseDBService.isConfigured) {
      setState(() => _failed = true);
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final res = await http
          .get(Uri.parse(url), headers: ExerciseDBService.rapidApiHeaders())
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty && mounted) {
        setState(() {
          _bytes = res.bodyBytes;
          _loading = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return _placeholder();
    }
    if (ExerciseMediaImage._needsRapidAuth(url)) {
      if (_loading) {
        return _placeholder(loading: true);
      }
      if (_failed || _bytes == null) {
        return _placeholder();
      }
      return Image.memory(
        _bytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      placeholder: (_, __) => _placeholder(loading: true),
      errorWidget: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder({bool loading = false}) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: const Color(0xFFF4F4F5),
      alignment: Alignment.center,
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.fitness_center_rounded,
              size: (widget.width != null && widget.width! < 80) ? 22 : 40,
              color: const Color(0xFFA1A1AA)),
    );
  }
}
