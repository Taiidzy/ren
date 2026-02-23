import 'dart:collection';

import 'package:ren/features/chats/presentation/widgets/chat_pending_attachment.dart';

class ChatPendingAttachmentsController {
  final int maxSingleAttachmentBytes;
  final int maxPendingAttachmentsBytes;

  ChatPendingAttachmentsController({
    required this.maxSingleAttachmentBytes,
    required this.maxPendingAttachmentsBytes,
  });

  final List<PendingChatAttachment> _pending = <PendingChatAttachment>[];
  int _pendingIdCounter = 0;

  List<PendingChatAttachment> get pending =>
      UnmodifiableListView<PendingChatAttachment>(_pending);

  String newPendingId() {
    _pendingIdCounter += 1;
    return 'pending_${DateTime.now().microsecondsSinceEpoch}_$_pendingIdCounter';
  }

  List<PendingChatAttachment> queuedPendingAttachments() {
    return _pending.where((p) => p.canSend).toList(growable: false);
  }

  void setStateByIds(
    Set<String> ids,
    PendingAttachmentState state, {
    String? error,
  }) {
    if (ids.isEmpty) return;
    for (var i = 0; i < _pending.length; i++) {
      final current = _pending[i];
      if (!ids.contains(current.clientId)) continue;
      switch (state) {
        case PendingAttachmentState.queued:
          _pending[i] = current.markQueued();
          break;
        case PendingAttachmentState.sending:
          _pending[i] = current.markSending();
          break;
        case PendingAttachmentState.failed:
          _pending[i] = current.markFailed(error);
          break;
      }
    }
  }

  void add(PendingChatAttachment attachment) {
    _pending.add(attachment);
  }

  void addAll(Iterable<PendingChatAttachment> attachments) {
    _pending.addAll(attachments);
  }

  bool canRemoveAt(int index) {
    if (index < 0 || index >= _pending.length) return false;
    return _pending[index].canRemove;
  }

  bool canRetryAt(int index) {
    if (index < 0 || index >= _pending.length) return false;
    return _pending[index].canRetry;
  }

  void removeAt(int index) {
    if (index < 0 || index >= _pending.length) return;
    _pending.removeAt(index);
  }

  void retryAt(int index) {
    if (index < 0 || index >= _pending.length) return;
    _pending[index] = _pending[index].markQueued();
  }

  void removeByIds(Set<String> ids) {
    if (ids.isEmpty) return;
    _pending.removeWhere((p) => ids.contains(p.clientId));
  }

  String? validateNextAttachmentSize(int sizeBytes) {
    if (sizeBytes <= 0) return null;
    if (sizeBytes > maxSingleAttachmentBytes) {
      return 'Файл слишком большой (${_formatBytes(sizeBytes)}). Лимит: ${_formatBytes(maxSingleAttachmentBytes)}.';
    }
    final nextTotal = _pendingTotalBytes + sizeBytes;
    if (nextTotal > maxPendingAttachmentsBytes) {
      return 'Слишком много вложений. Лимит очереди: ${_formatBytes(maxPendingAttachmentsBytes)}.';
    }
    return null;
  }

  int get _pendingTotalBytes {
    var total = 0;
    for (final p in _pending) {
      total += p.sizeBytes;
    }
    return total;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const kb = 1024;
    const mb = 1024 * 1024;
    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    }
    if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}
