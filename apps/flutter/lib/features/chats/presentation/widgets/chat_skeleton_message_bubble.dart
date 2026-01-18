import 'package:flutter/material.dart';

import 'package:ren/shared/widgets/skeleton.dart';

class ChatSkeletonMessageBubble extends StatelessWidget {
  final bool isMe;

  const ChatSkeletonMessageBubble({
    super.key,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxW = MediaQuery.of(context).size.width * 0.62;
    final w = isMe ? maxW : (maxW * 0.82);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: w),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(0.55),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            RenSkeletonBox(width: 180, height: 12, radius: 8),
            SizedBox(height: 8),
            RenSkeletonBox(width: 140, height: 12, radius: 8),
          ],
        ),
      ),
    );
  }
}
