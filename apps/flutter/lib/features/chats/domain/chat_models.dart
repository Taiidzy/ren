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
  final DateTime sentAt;

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.isMe,
    required this.text,
    required this.sentAt,
  });
}

class ChatPreview {
  final String id;
  final int? peerId;
  final String kind;
  final ChatUser user;
  final String lastMessage;
  final DateTime lastMessageAt;

  const ChatPreview({
    required this.id,
    required this.peerId,
    required this.kind,
    required this.user,
    required this.lastMessage,
    required this.lastMessageAt,
  });
}
