import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Shows exercise GIF/image from a public URL (e.g. static.exercisedb.dev).
class ExerciseMediaImage extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return _placeholder();
    }
    return Semantics(
      label: 'Exercise illustration',
      image: true,
      child: CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: fit,
        placeholder: (_, __) => _placeholder(loading: true),
        errorWidget: (_, __, ___) => _placeholder(),
      ),
    );
  }

  Widget _placeholder({bool loading = false}) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFF4F4F5),
      alignment: Alignment.center,
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.fitness_center_rounded,
              size: (width != null && width! < 80) ? 22 : 40,
              color: const Color(0xFFA1A1AA)),
    );
  }
}
