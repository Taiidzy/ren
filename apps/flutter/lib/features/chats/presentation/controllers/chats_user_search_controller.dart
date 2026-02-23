import 'dart:async';

import 'package:ren/features/chats/data/chats_repository.dart';
import 'package:ren/features/chats/domain/chat_models.dart';

class ChatsUserSearchSnapshot {
  final String query;
  final bool isSearching;
  final String? error;
  final List<ChatUser> users;

  const ChatsUserSearchSnapshot({
    required this.query,
    required this.isSearching,
    required this.error,
    required this.users,
  });

  static const ChatsUserSearchSnapshot initial = ChatsUserSearchSnapshot(
    query: '',
    isSearching: false,
    error: null,
    users: <ChatUser>[],
  );

  ChatsUserSearchSnapshot copyWith({
    String? query,
    bool? isSearching,
    Object? error = _unset,
    List<ChatUser>? users,
  }) {
    return ChatsUserSearchSnapshot(
      query: query ?? this.query,
      isSearching: isSearching ?? this.isSearching,
      error: identical(error, _unset) ? this.error : error as String?,
      users: users ?? this.users,
    );
  }

  static const Object _unset = Object();
}

class ChatsUserSearchController {
  final ChatsRepository _repo;
  final Duration _debounceDuration;
  final void Function(ChatsUserSearchSnapshot snapshot) _onChanged;

  Timer? _debounce;
  int _searchSeq = 0;
  ChatsUserSearchSnapshot _snapshot = ChatsUserSearchSnapshot.initial;

  ChatsUserSearchController({
    required ChatsRepository repo,
    required void Function(ChatsUserSearchSnapshot snapshot) onChanged,
    Duration debounceDuration = const Duration(milliseconds: 250),
  }) : _repo = repo,
       _onChanged = onChanged,
       _debounceDuration = debounceDuration;

  void onTextChanged(String rawText) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      final nextQuery = rawText.trim();
      if (nextQuery == _snapshot.query) return;
      _setSnapshot(_snapshot.copyWith(query: nextQuery));
      _runSearch(nextQuery);
    });
  }

  void _runSearch(String query) {
    final q = query.trim();
    final seq = ++_searchSeq;

    if (q.isEmpty) {
      _setSnapshot(
        _snapshot.copyWith(
          isSearching: false,
          error: null,
          users: const <ChatUser>[],
        ),
      );
      return;
    }

    _setSnapshot(_snapshot.copyWith(isSearching: true, error: null));

    _repo
        .searchUsers(q)
        .then((users) {
          if (seq != _searchSeq) return;
          _setSnapshot(
            _snapshot.copyWith(isSearching: false, error: null, users: users),
          );
        })
        .catchError((e) {
          if (seq != _searchSeq) return;
          _setSnapshot(
            _snapshot.copyWith(
              isSearching: false,
              error: e.toString(),
              users: const <ChatUser>[],
            ),
          );
        });
  }

  void _setSnapshot(ChatsUserSearchSnapshot next) {
    _snapshot = next;
    _onChanged(next);
  }

  void dispose() {
    _debounce?.cancel();
    _debounce = null;
  }
}
