import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

import 'package:ren/features/chats/presentation/widgets/chat_pending_attachment.dart';

class ChatAttachmentsPickerController {
  ChatAttachmentsPickerController({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<List<PendingChatAttachment>> pickPhotos({
    required String Function() newClientId,
    required bool Function(int sizeBytes) canAttachFileSize,
  }) async {
    try {
      final files = await _picker.pickMultiImage();
      if (files.isEmpty) return const <PendingChatAttachment>[];

      final added = <PendingChatAttachment>[];
      for (final file in files) {
        final name = file.name.isNotEmpty
            ? file.name
            : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final path = file.path;
        final size = path.isNotEmpty ? await File(path).length() : 0;
        if (!canAttachFileSize(size)) continue;
        added.add(
          PendingChatAttachment(
            clientId: newClientId(),
            filename: name,
            mimetype: _mimetypeFromImageName(name),
            sizeBytes: size,
            localPath: path,
          ),
        );
      }
      return added;
    } catch (e) {
      debugPrint('pick photos failed: $e');
      return const <PendingChatAttachment>[];
    }
  }

  Future<PendingChatAttachment?> takePhoto({
    required String Function() newClientId,
    required bool Function(int sizeBytes) canAttachFileSize,
  }) async {
    try {
      final file = await _picker.pickImage(source: ImageSource.camera);
      if (file == null) return null;

      final name = file.name.isNotEmpty
          ? file.name
          : 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final size = await File(file.path).length();
      if (!canAttachFileSize(size)) return null;

      return PendingChatAttachment(
        clientId: newClientId(),
        filename: name,
        mimetype: 'image/jpeg',
        sizeBytes: size,
        localPath: file.path,
      );
    } catch (e) {
      debugPrint('take photo failed: $e');
      return null;
    }
  }

  Future<List<PendingChatAttachment>> pickFiles({
    required String Function() newClientId,
    required bool Function(int sizeBytes) canAttachFileSize,
  }) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );
      if (res == null) return const <PendingChatAttachment>[];

      final added = <PendingChatAttachment>[];
      for (final file in res.files) {
        final path = file.path;
        if (path == null || path.isEmpty) continue;
        final name = file.name.isNotEmpty
            ? file.name
            : 'file_${DateTime.now().millisecondsSinceEpoch}';
        final mime = lookupMimeType(path) ?? 'application/octet-stream';
        final size = file.size > 0 ? file.size : await File(path).length();
        if (!canAttachFileSize(size)) continue;
        added.add(
          PendingChatAttachment(
            clientId: newClientId(),
            filename: name,
            mimetype: mime,
            sizeBytes: size,
            localPath: path,
          ),
        );
      }
      return added;
    } catch (e) {
      debugPrint('pick files failed: $e');
      return const <PendingChatAttachment>[];
    }
  }

  String _mimetypeFromImageName(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }
}
