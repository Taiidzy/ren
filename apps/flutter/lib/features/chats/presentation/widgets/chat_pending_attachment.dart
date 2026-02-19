import 'dart:typed_data';

enum PendingAttachmentState { queued, sending, failed }

class PendingChatAttachment {
  final String clientId;
  final Uint8List? bytes;
  final String filename;
  final String mimetype;
  final int sizeBytes;
  final String? localPath;
  final PendingAttachmentState state;
  final String? error;

  const PendingChatAttachment({
    required this.clientId,
    this.bytes,
    required this.filename,
    required this.mimetype,
    required this.sizeBytes,
    this.localPath,
    this.state = PendingAttachmentState.queued,
    this.error,
  });

  PendingChatAttachment copyWith({
    Uint8List? bytes,
    String? filename,
    String? mimetype,
    int? sizeBytes,
    String? localPath,
    PendingAttachmentState? state,
    String? error,
    bool clearError = false,
  }) {
    return PendingChatAttachment(
      clientId: clientId,
      bytes: bytes ?? this.bytes,
      filename: filename ?? this.filename,
      mimetype: mimetype ?? this.mimetype,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      localPath: localPath ?? this.localPath,
      state: state ?? this.state,
      error: clearError ? null : (error ?? this.error),
    );
  }

  bool get isQueued => state == PendingAttachmentState.queued;
  bool get isSending => state == PendingAttachmentState.sending;
  bool get isFailed => state == PendingAttachmentState.failed;
  bool get canRetry => isFailed;
  bool get canRemove => !isSending;
  bool get canSend => isQueued;

  PendingChatAttachment markQueued() =>
      copyWith(state: PendingAttachmentState.queued, clearError: true);

  PendingChatAttachment markSending() =>
      copyWith(state: PendingAttachmentState.sending, clearError: true);

  PendingChatAttachment markFailed([String? reason]) =>
      copyWith(state: PendingAttachmentState.failed, error: reason);
}
