import 'package:ren/features/chats/domain/chat_models.dart';

class FakeChatsRepository {
  const FakeChatsRepository();

  List<ChatUser> favorites() {
    return const [
      ChatUser(
        id: 'u1',
        name: 'Bob',
        avatarUrl:
            'https://i.pinimg.com/736x/a7/39/43/a73943b7aed2241452dc7d0bd4aa064e.jpg',
        isOnline: true,
      ),
      ChatUser(
        id: 'u2',
        name: 'Bob',
        avatarUrl:
            'https://i.pinimg.com/736x/a7/39/43/a73943b7aed2241452dc7d0bd4aa064e.jpg',
        isOnline: true,
      ),
      ChatUser(
        id: 'u3',
        name: 'Bob',
        avatarUrl:
            'https://i.pinimg.com/736x/a7/39/43/a73943b7aed2241452dc7d0bd4aa064e.jpg',
        isOnline: true,
      ),
      ChatUser(
        id: 'u4',
        name: 'Bob',
        avatarUrl:
            'https://i.pinimg.com/736x/a7/39/43/a73943b7aed2241452dc7d0bd4aa064e.jpg',
        isOnline: true,
      ),
      ChatUser(
        id: 'u5',
        name: 'Bob',
        avatarUrl:
            'https://i.pinimg.com/736x/a7/39/43/a73943b7aed2241452dc7d0bd4aa064e.jpg',
        isOnline: true,
      ),
    ];
  }

  List<ChatPreview> chats() {
    final now = DateTime.now();
    const user = ChatUser(
      id: 'u1',
      name: 'Bob',
      avatarUrl:
          'https://i.pinimg.com/736x/a7/39/43/a73943b7aed2241452dc7d0bd4aa064e.jpg',
      isOnline: true,
    );

    return List.generate(
      10,
      (i) => ChatPreview(
        id: 'c$i',
        user: user,
        lastMessage: 'Какая?',
        lastMessageAt: now.subtract(Duration(minutes: i * 7)),
      ),
    );
  }

  List<ChatMessage> messages(String chatId) {
    final base = DateTime.now().subtract(const Duration(minutes: 15));
    return [
      ChatMessage(
        id: 'm1',
        chatId: chatId,
        isMe: false,
        text: 'Привет',
        sentAt: base,
      ),
      ChatMessage(
        id: 'm2',
        chatId: chatId,
        isMe: true,
        text: 'Привет',
        sentAt: base.add(const Duration(minutes: 1)),
      ),
      ChatMessage(
        id: 'm3',
        chatId: chatId,
        isMe: true,
        text: 'Как дела?',
        sentAt: base.add(const Duration(minutes: 2)),
      ),
      ChatMessage(
        id: 'm4',
        chatId: chatId,
        isMe: false,
        text: 'Нормально. А у тебя?',
        sentAt: base.add(const Duration(minutes: 3)),
      ),
      ChatMessage(
        id: 'm5',
        chatId: chatId,
        isMe: true,
        text: 'Тоже не плохо. У меня есть одна идея',
        sentAt: base.add(const Duration(minutes: 4)),
      ),
      ChatMessage(
        id: 'm6',
        chatId: chatId,
        isMe: false,
        text: 'Какая?',
        sentAt: base.add(const Duration(minutes: 5)),
      ),
    ];
  }
}
