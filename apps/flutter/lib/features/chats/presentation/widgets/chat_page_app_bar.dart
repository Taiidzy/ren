import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:ren/shared/widgets/avatar.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

class ChatPageAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String peerName;
  final String peerAvatarUrl;
  final bool selectionMode;
  final int selectedCount;
  final bool peerOnline;
  final bool peerTyping;
  final bool isSyncing;
  final String chatKind;
  final String myRole;
  final bool canSend;

  final VoidCallback onBack;
  final VoidCallback onShareSelected;
  final VoidCallback onDeleteSelected;
  final VoidCallback onMenu;

  const ChatPageAppBar({
    super.key,
    required this.peerName,
    required this.peerAvatarUrl,
    required this.selectionMode,
    required this.selectedCount,
    required this.peerOnline,
    required this.peerTyping,
    required this.isSyncing,
    required this.chatKind,
    required this.myRole,
    required this.canSend,
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
    final kind = chatKind.trim().toLowerCase();
    final role = myRole.trim().toLowerCase();

    String kindLabel() {
      switch (kind) {
        case 'channel':
          return 'CHANNEL';
        case 'group':
          return 'GROUP';
        default:
          return 'PRIVATE';
      }
    }

    String roleLabel() {
      switch (role) {
        case 'owner':
          return 'OWNER';
        case 'admin':
          return 'ADMIN';
        default:
          return 'MEMBER';
      }
    }

    final showRole = kind == 'channel' || kind == 'group';

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
                        url: peerAvatarUrl,
                        name: peerName,
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
                              peerName,
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
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(isDark ? 0.13 : 0.10),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    showRole
                                        ? '${kindLabel()} • ${roleLabel()}'
                                        : kindLabel(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.82),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  peerTyping
                                      ? 'Печатает...'
                                      : (kind == 'channel'
                                            ? (canSend
                                                  ? 'Можно писать'
                                                  : 'Read-only')
                                            : (peerOnline
                                                  ? 'Online'
                                                  : 'Offline')),
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
