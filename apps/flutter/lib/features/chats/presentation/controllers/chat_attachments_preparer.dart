import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:ren/features/chats/data/chats_repository.dart';
import 'package:ren/features/chats/domain/chat_models.dart';
import 'package:ren/features/chats/presentation/widgets/chat_pending_attachment.dart';

class ChatAttachmentsPreparer {
  const ChatAttachmentsPreparer();

  Future<List<ChatAttachment>> buildOptimisticAttachments(
    List<PendingChatAttachment> pendingToSend,
  ) async {
    if (pendingToSend.isEmpty) return const <ChatAttachment>[];
    final out = <ChatAttachment>[];
    for (final pending in pendingToSend) {
      out.add(await resolveOptimisticAttachment(pending));
    }
    return out;
  }

  Future<List<OutgoingAttachment>> buildOutgoingAttachments(
    List<PendingChatAttachment> pendingToSend,
  ) async {
    final outgoing = <OutgoingAttachment>[];
    for (final pending in pendingToSend) {
      final bytes = await readPendingAttachmentBytes(pending);
      outgoing.add(
        OutgoingAttachment(
          bytes: bytes,
          filename: pending.filename,
          mimetype: pending.mimetype,
        ),
      );
    }
    return outgoing;
  }

  Future<ChatAttachment> resolveOptimisticAttachment(
    PendingChatAttachment attachment,
  ) async {
    final safeName = attachment.filename.isNotEmpty
        ? attachment.filename
        : 'file_${DateTime.now().millisecondsSinceEpoch}';

    final existingPath = attachment.localPath;
    if (existingPath != null && existingPath.isNotEmpty) {
      final existing = File(existingPath);
      if (await existing.exists()) {
        final size = attachment.sizeBytes > 0
            ? attachment.sizeBytes
            : await existing.length();
        return ChatAttachment(
          localPath: existingPath,
          filename: safeName,
          mimetype: attachment.mimetype,
          size: size,
        );
      }
    }

    final bytes = attachment.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Attachment bytes are missing');
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$safeName';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return ChatAttachment(
      localPath: path,
      filename: safeName,
      mimetype: attachment.mimetype,
      size: attachment.sizeBytes > 0 ? attachment.sizeBytes : bytes.length,
    );
  }

  Future<Uint8List> readPendingAttachmentBytes(
    PendingChatAttachment attachment,
  ) async {
    final inMemory = attachment.bytes;
    if (inMemory != null && inMemory.isNotEmpty) {
      return inMemory;
    }

    final path = attachment.localPath;
    if (path == null || path.isEmpty) {
      throw StateError('Attachment path is missing');
    }
    return await File(path).readAsBytes();
  }
}
