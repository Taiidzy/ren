class ChatUser {
  final String id;
  final String name;
  final String avatarUrl;
  final bool isOnline;

  const ChatUser({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.isOnline,
  });
}

class ChatMessage {
  final String id;
  final String chatId;
  final bool isMe;
  final String text;
  final List<ChatAttachment> attachments;
  final DateTime sentAt;
  final String? replyToMessageId;

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.isMe,
    required this.text,
    this.attachments = const [],
    required this.sentAt,
    this.replyToMessageId,
  });
}

class ChatAttachment {
  final String localPath;
  final String filename;
  final String mimetype;
  final int size;

  const ChatAttachment({
    required this.localPath,
    required this.filename,
    required this.mimetype,
    required this.size,
  });

  bool get isImage => mimetype.startsWith('image/');
  bool get isVideo => mimetype.startsWith('video/');
}

class ChatPreview {
  final String id;
  final int? peerId;
  final String kind;
  final ChatUser user;
  final bool isFavorite;
  final String lastMessage;
  final DateTime lastMessageAt;

  const ChatPreview({
    required this.id,
    required this.peerId,
    required this.kind,
    required this.user,
    this.isFavorite = false,
    required this.lastMessage,
    required this.lastMessageAt,
  });
}

class ChatMember {
  final int userId;
  final String username;
  final String avatarUrl;
  final String role;
  final DateTime joinedAt;

  const ChatMember({
    required this.userId,
    required this.username,
    required this.avatarUrl,
    required this.role,
    required this.joinedAt,
  });
}
