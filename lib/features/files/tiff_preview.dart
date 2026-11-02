import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

// Decode one page at a time, keeping only display-sized PNGs for the gallery.
// Called with compute() so decoding does not block input or scrolling.
List<Uint8List> decodeTiffPages(Uint8List bytes) {
  final decoder = img.TiffDecoder();
  if (decoder.startDecode(bytes) == null || decoder.numFrames() == 0) {
    throw const FormatException('Unable to read TIFF image.');
  }
  return List.generate(decoder.numFrames(), (index) {
    final page = decoder.decodeFrame(index);
    if (page == null) {
      throw FormatException('Unable to read TIFF page ${index + 1}.');
    }
    final oriented = img.bakeOrientation(page);
    final preview = oriented.width > 2048 || oriented.height > 2048
        ? img.copyResize(
            oriented,
            width: oriented.width >= oriented.height ? 2048 : null,
            height: oriented.height > oriented.width ? 2048 : null,
          )
        : oriented;
    return img.encodePng(preview);
  });
}

class TiffPreviewGallery extends StatelessWidget {
  const TiffPreviewGallery({super.key, required this.pages});

  final List<Uint8List> pages;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: pages.length,
      separatorBuilder: (_, __) => const SizedBox(height: 20),
      itemBuilder: (context, index) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              pages[index],
              width: double.infinity,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}
