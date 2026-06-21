import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/strings.dart';
import '../services/api_service.dart';

enum MediaType { image, video, file }

class MediaResult {
  final File file;
  final String filename;
  final MediaType type;
  MediaResult(this.file, this.filename, this.type);
}

class MediaUtils {
  static final _picker = ImagePicker();

  static Future<MediaResult?> pickFromGallery() async {
    final xfile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (xfile == null) return null;
    return MediaResult(File(xfile.path), xfile.name, MediaType.image);
  }

  static Future<MediaResult?> pickVideoFromGallery() async {
    final xfile = await _picker.pickVideo(source: ImageSource.gallery);
    if (xfile == null) return null;
    return MediaResult(File(xfile.path), xfile.name, MediaType.video);
  }

  static Future<MediaResult?> capturePhoto() async {
    final xfile = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (xfile == null) return null;
    return MediaResult(File(xfile.path), xfile.name, MediaType.image);
  }

  /// Pick any file (any format) for sending as a document.
  static Future<MediaResult?> pickAnyFile() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.single;
    if (f.path == null) return null;
    return MediaResult(File(f.path!), f.name, MediaType.file);
  }

  static Future<String?> uploadAndGetId(MediaResult result) async {
    try {
      final resp = await ApiService.uploadFile(result.file.path, result.filename);
      return resp['id'] as String?;
    } catch (_) {
      return null;
    }
  }
}

class MediaPreview extends StatelessWidget {
  final String fileId;
  final double? width;
  final double? height;

  const MediaPreview({super.key, required this.fileId, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    final url = ApiService.getFileUrl(fileId);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: width ?? 200,
        height: height ?? 200,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: width ?? 200,
          height: height ?? 200,
          color: Colors.grey[900],
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Container(
            width: width ?? 200,
            height: height ?? 200,
            color: Colors.grey[900],
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        },
      ),
    );
  }
}

class MediaAttachmentBar extends StatelessWidget {
  final VoidCallback onPickPhoto;
  final VoidCallback onPickVideo;
  final VoidCallback onCapturePhoto;
  final VoidCallback onRecordVoice;
  final VoidCallback onOpenVideoCircle;
  final VoidCallback onPickFile;

  const MediaAttachmentBar({
    super.key,
    required this.onPickPhoto,
    required this.onPickVideo,
    required this.onCapturePhoto,
    required this.onRecordVoice,
    required this.onOpenVideoCircle,
    required this.onPickFile,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SafeArea(
        child: Wrap(
          alignment: WrapAlignment.spaceEvenly,
          spacing: 8,
          runSpacing: 12,
          children: [
            _btn(context, s, Icons.photo_library, Strings.t('chat.media.gallery'), onPickPhoto),
            _btn(context, s, Icons.videocam, Strings.t('chat.media.video'), onPickVideo),
            _btn(context, s, Icons.camera_alt, Strings.t('chat.media.camera'), onCapturePhoto),
            _btn(context, s, Icons.mic, Strings.t('chat.media.voice'), onRecordVoice),
            _btn(context, s, Icons.videocam_rounded, Strings.t('chat.media.circle'), onOpenVideoCircle),
            _btn(context, s, Icons.attach_file, 'Файл', onPickFile),
          ],
        ),
      ),
    );
  }

  Widget _btn(BuildContext context, ColorScheme s, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: s.primaryContainer,
            child: Icon(icon, color: s.onPrimaryContainer, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}
