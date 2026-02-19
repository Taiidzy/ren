import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ren/features/chats/presentation/widgets/chat_pending_attachment.dart';

void main() {
  test('PendingChatAttachment keeps optional localPath', () {
    final attachment = PendingChatAttachment(
      clientId: 'p1',
      bytes: Uint8List.fromList([1, 2, 3]),
      filename: 'image.jpg',
      mimetype: 'image/jpeg',
      sizeBytes: 3,
      localPath: '/tmp/image.jpg',
    );

    expect(attachment.localPath, '/tmp/image.jpg');
  });

  test('PendingChatAttachment localPath defaults to null', () {
    final attachment = PendingChatAttachment(
      clientId: 'p2',
      bytes: Uint8List(0),
      filename: 'file.bin',
      mimetype: 'application/octet-stream',
      sizeBytes: 0,
    );

    expect(attachment.localPath, isNull);
  });
}
