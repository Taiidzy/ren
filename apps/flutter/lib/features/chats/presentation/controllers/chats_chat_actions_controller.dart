import 'package:ren/features/chats/data/chats_repository.dart';
import 'package:ren/features/chats/domain/chat_models.dart';

class ChatsChatActionsController {
  final ChatsRepository _repo;

  ChatsChatActionsController(this._repo);

  Future<void> toggleFavorite(ChatPreview chat) async {
    final chatId = int.tryParse(chat.id) ?? 0;
    if (chatId <= 0) {
      throw Exception('Некорректный chat id');
    }
    await _repo.setFavorite(chatId, favorite: !chat.isFavorite);
  }

  Future<void> deleteOrLeaveChat({
    required ChatPreview chat,
    required bool forAll,
  }) async {
    final chatId = int.tryParse(chat.id) ?? 0;
    if (chatId <= 0) {
      throw Exception('Некорректный chat id');
    }
    await _repo.deleteChat(chatId, forAll: forAll);
  }
}
