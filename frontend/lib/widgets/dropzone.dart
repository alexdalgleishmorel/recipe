import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A file the user picked for AI import: its [filename] and raw [bytes].
class PickedFile {
  const PickedFile({required this.filename, required this.bytes});
  final String filename;
  final Uint8List bytes;
}

class Dropzone extends StatefulWidget {
  const Dropzone({super.key, required this.onFile});
  final ValueChanged<PickedFile> onFile;

  @override
  State<Dropzone> createState() => _DropzoneState();
}

class _DropzoneState extends State<Dropzone> {
  bool _hover = false;

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null) return;
    widget.onFile(PickedFile(filename: picked.name, bytes: bytes));
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _pick,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
          decoration: BoxDecoration(
            color: _hover ? rt.accentSoft : rt.paper2,
            border: Border.all(
              color: _hover ? rt.accent : rt.hair2,
              width: 2,
              style: BorderStyle.solid,
            ),
            borderRadius: RecipeRadius.cardBR,
          ),
          child: Column(
            children: [
              Icon(Icons.cloud_upload_outlined, size: 48, color: rt.ink3),
              const SizedBox(height: 16),
              Text(
                'Drop a recipe file here',
                style: RecipeTypography.serif(size: 22, weight: FontWeight.w500, color: rt.ink, letterSpacing: -0.22),
              ),
              const SizedBox(height: 6),
              Text('or click to browse — PDF, image, or URL',
                  style: TextStyle(color: rt.ink3, fontSize: 14)),
              const SizedBox(height: 14),
              Text('PDF · JPG · PNG · TXT',
                  style: RecipeTypography.mono(size: 11, color: rt.ink3, letterSpacing: 0.66)),
            ],
          ),
        ),
      ),
    );
  }
}
