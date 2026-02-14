import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:ren/features/chats/domain/chat_models.dart';
import 'package:ren/shared/widgets/avatar.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

class ChatPageAppBar extends StatelessWidget implements PreferredSizeWidget {
  final ChatPreview chat;
  final bool selectionMode;
  final int selectedCount;
  final bool peerOnline;
  final bool peerTyping;
  final bool isSyncing;

  final VoidCallback onBack;
  final VoidCallback onShareSelected;
  final VoidCallback onDeleteSelected;
  final VoidCallback onMenu;

  const ChatPageAppBar({
    super.key,
    required this.chat,
    required this.selectionMode,
    required this.selectedCount,
    required this.peerOnline,
    required this.peerTyping,
    required this.isSyncing,
    required this.onBack,
    required this.onShareSelected,
    required this.onDeleteSelected,
    required this.onMenu,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: const GlassAppBarBackground(),
      centerTitle: true,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: onBack,
      ),
      title: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: double.infinity,
            child: Center(
              child: GlassSurface(
                borderRadius: 18,
                blurSigma: 12,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                borderColor: baseInk.withOpacity(isDark ? 0.18 : 0.10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selectionMode)
                      Text(
                        'Выбрано: $selectedCount',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      )
                    else ...[
                      RenAvatar(
                        url: chat.user.avatarUrl,
                        name: chat.user.name,
                        isOnline: peerOnline,
                        size: 36,
                      ),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              chat.user.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  peerTyping
                                      ? 'Печатает...'
                                      : (peerOnline ? 'Online' : 'Offline'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.65),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  child: isSyncing
                                      ? SizedBox(
                                          key: const ValueKey('chat_syncing'),
                                          width: 10,
                                          height: 10,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.8,
                                            color: theme.colorScheme.onSurface
                                                .withOpacity(0.75),
                                          ),
                                        )
                                      : const SizedBox(
                                          key: ValueKey('chat_idle'),
                                          width: 10,
                                          height: 10,
                                        ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        if (selectionMode) ...[
          IconButton(
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedArrowTurnForward,
              color: theme.colorScheme.onSurface,
              size: 24.0,
            ),
            onPressed: selectedCount == 0 ? null : onShareSelected,
          ),
          IconButton(
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedDelete01,
              color: theme.colorScheme.error,
              size: 24.0,
            ),
            onPressed: selectedCount == 0 ? null : onDeleteSelected,
          ),
        ] else
          IconButton(
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedMenu01,
              color: theme.colorScheme.onSurface,
              size: 24.0,
            ),
            onPressed: onMenu,
          ),
      ],
    );
  }
}
