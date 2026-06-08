import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/http_recipe_import_service.dart' show contentTypeForFilename;
import '../services/repositories.dart';
import '../theme/app_theme.dart';
import 'buttons.dart';
import 'recipe_image.dart';
import 'toast.dart';

/// Editor control for a recipe photo (#80). Shows the current image (or the
/// shared [RecipeImage] placeholder), and lets the user pick an image file,
/// upload it via [uploadsRepo], and report the resulting public [url] back via
/// [onChanged]. A spinner covers the preview while uploading; failures surface
/// as a toast.
///
/// Used by both the recipe editor (detail screen edit mode) and the upload
/// review form so the affordance is identical in both places.
class PhotoField extends StatefulWidget {
  const PhotoField({
    super.key,
    required this.url,
    required this.uploadsRepo,
    required this.onChanged,
  });

  /// The current image URL (possibly empty), e.g. `recipe.image`.
  final String url;
  final UploadsRepository uploadsRepo;

  /// Called with the new image URL (the uploaded public URL, or an empty string
  /// when the photo is removed).
  final ValueChanged<String> onChanged;

  @override
  State<PhotoField> createState() => _PhotoFieldState();
}

class _PhotoFieldState extends State<PhotoField> {
  bool _uploading = false;

  Future<void> _pick() async {
    if (_uploading) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      if (!mounted) return;
      showToast(context, 'Could not read that image');
      return;
    }

    setState(() => _uploading = true);
    try {
      final url = await widget.uploadsRepo.uploadImage(
        bytes: bytes,
        contentType: contentTypeForFilename(file.name),
      );
      if (!mounted) return;
      widget.onChanged(url);
    } catch (_) {
      if (!mounted) return;
      showToast(context, 'Upload failed — please try again');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _remove() {
    if (_uploading) return;
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final hasImage = widget.url.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            borderRadius: RecipeRadius.cardBR,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: rt.hair),
                borderRadius: RecipeRadius.cardBR,
                color: rt.paper2,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RecipeImage(url: widget.url, iconSize: 44),
                  if (_uploading)
                    Container(
                      color: rt.paper2.withValues(alpha: 0.72),
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: rt.accent,
                          backgroundColor: rt.hair2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Btn(
            label: hasImage ? 'Change photo' : 'Add photo',
            icon: Icons.image_outlined,
            size: BtnSize.sm,
            onPressed: _uploading ? null : _pick,
          ),
          if (hasImage)
            Btn(
              label: 'Remove photo',
              icon: Icons.delete_outline,
              variant: BtnVariant.danger,
              size: BtnSize.sm,
              onPressed: _uploading ? null : _remove,
            ),
        ]),
      ],
    );
  }
}
