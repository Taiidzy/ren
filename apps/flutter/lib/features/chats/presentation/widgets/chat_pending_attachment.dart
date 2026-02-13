import 'dart:typed_data';

class PendingChatAttachment {
  final Uint8List bytes;
  final String filename;
  final String mimetype;
  final String? localPath;

  const PendingChatAttachment({
    required this.bytes,
    required this.filename,
    required this.mimetype,
    this.localPath,
  });
}
