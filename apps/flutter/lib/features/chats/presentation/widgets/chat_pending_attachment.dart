import 'dart:typed_data';

class PendingChatAttachment {
  final Uint8List bytes;
  final String filename;
  final String mimetype;

  const PendingChatAttachment({
    required this.bytes,
    required this.filename,
    required this.mimetype,
  });
}
