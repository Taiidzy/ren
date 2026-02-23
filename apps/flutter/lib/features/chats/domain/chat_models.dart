class ChatUser {
  final String id;
  final String name;
  final String? nickname;
  final String avatarUrl;
  final bool isOnline;

  const ChatUser({
    required this.id,
    required this.name,
    this.nickname,
    required this.avatarUrl,
    required this.isOnline,
  });

  static const Object _unset = Object();

  ChatUser copyWith({
    String? id,
    String? name,
    Object? nickname = _unset,
    String? avatarUrl,
    bool? isOnline,
  }) {
    return ChatUser(
      id: id ?? this.id,
      name: name ?? this.name,
      nickname: identical(nickname, _unset)
          ? this.nickname
          : nickname as String?,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}

class ChatMessage {
  final String id;
  final String chatId;
  final bool isMe;
  final String text;
  final List<ChatAttachment> attachments;
  final DateTime sentAt;
  final String? replyToMessageId;
  final bool isDelivered;
  final bool isRead;
  final String? senderName;
  final String? senderAvatarUrl;

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.isMe,
    required this.text,
    this.attachments = const [],
    required this.sentAt,
    this.replyToMessageId,
    this.isDelivered = false,
    this.isRead = false,
    this.senderName,
    this.senderAvatarUrl,
  });

  static const Object _unset = Object();

  ChatMessage copyWith({
    String? id,
    String? chatId,
    bool? isMe,
    String? text,
    List<ChatAttachment>? attachments,
    DateTime? sentAt,
    Object? replyToMessageId = _unset,
    bool? isDelivered,
    bool? isRead,
    Object? senderName = _unset,
    Object? senderAvatarUrl = _unset,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      isMe: isMe ?? this.isMe,
      text: text ?? this.text,
      attachments: attachments ?? this.attachments,
      sentAt: sentAt ?? this.sentAt,
      replyToMessageId: identical(replyToMessageId, _unset)
          ? this.replyToMessageId
          : replyToMessageId as String?,
      isDelivered: isDelivered ?? this.isDelivered,
      isRead: isRead ?? this.isRead,
      senderName: identical(senderName, _unset)
          ? this.senderName
          : senderName as String?,
      senderAvatarUrl: identical(senderAvatarUrl, _unset)
          ? this.senderAvatarUrl
          : senderAvatarUrl as String?,
    );
  }
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

  ChatAttachment copyWith({
    String? localPath,
    String? filename,
    String? mimetype,
    int? size,
  }) {
    return ChatAttachment(
      localPath: localPath ?? this.localPath,
      filename: filename ?? this.filename,
      mimetype: mimetype ?? this.mimetype,
      size: size ?? this.size,
    );
  }

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
  final int unreadCount;
  final String myRole;
  final bool lastMessageIsMine;
  final bool lastMessageIsPending;
  final bool lastMessageIsDelivered;
  final bool lastMessageIsRead;

  const ChatPreview({
    required this.id,
    required this.peerId,
    required this.kind,
    required this.user,
    this.isFavorite = false,
    required this.lastMessage,
    required this.lastMessageAt,
    this.unreadCount = 0,
    this.myRole = 'member',
    this.lastMessageIsMine = false,
    this.lastMessageIsPending = false,
    this.lastMessageIsDelivered = false,
    this.lastMessageIsRead = false,
  });

  static const Object _unset = Object();

  ChatPreview copyWith({
    String? id,
    Object? peerId = _unset,
    String? kind,
    ChatUser? user,
    bool? isFavorite,
    String? lastMessage,
    DateTime? lastMessageAt,
    int? unreadCount,
    String? myRole,
    bool? lastMessageIsMine,
    bool? lastMessageIsPending,
    bool? lastMessageIsDelivered,
    bool? lastMessageIsRead,
  }) {
    return ChatPreview(
      id: id ?? this.id,
      peerId: identical(peerId, _unset) ? this.peerId : peerId as int?,
      kind: kind ?? this.kind,
      user: user ?? this.user,
      isFavorite: isFavorite ?? this.isFavorite,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      myRole: myRole ?? this.myRole,
      lastMessageIsMine: lastMessageIsMine ?? this.lastMessageIsMine,
      lastMessageIsPending: lastMessageIsPending ?? this.lastMessageIsPending,
      lastMessageIsDelivered:
          lastMessageIsDelivered ?? this.lastMessageIsDelivered,
      lastMessageIsRead: lastMessageIsRead ?? this.lastMessageIsRead,
    );
  }
}

class ChatMember {
  final int userId;
  final String username;
  final String? nickname;
  final String avatarUrl;
  final String role;
  final DateTime joinedAt;

  const ChatMember({
    required this.userId,
    required this.username,
    this.nickname,
    required this.avatarUrl,
    required this.role,
    required this.joinedAt,
  });
}
