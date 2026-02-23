import 'package:flutter/material.dart';

/// P0-5: Group E2EE Warning Banner
/// 
/// Displays a warning banner in group/channel chats informing users
/// that group messages are NOT end-to-end encrypted.
class GroupE2EEWarning extends StatelessWidget {
  final String chatKind; // 'group', 'channel', 'private'
  
  const GroupE2EEWarning({
    super.key,
    required this.chatKind,
  });
  
  bool get _shouldShow {
    final kind = chatKind.trim().toLowerCase();
    return kind == 'group' || kind == 'channel';
  }
  
  @override
  Widget build(BuildContext context) {
    if (!_shouldShow) {
      return const SizedBox.shrink();
    }
    
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(isDark ? 0.15 : 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.amber.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Colors.amber.shade700,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Групповые сообщения не защищены E2EE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber.shade800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Сообщения в группах и каналах шифруются на сервере, но не имеют сквозного шифрования. Только приватные чаты 1-на-1 защищены End-to-End.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.amber.shade800.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
