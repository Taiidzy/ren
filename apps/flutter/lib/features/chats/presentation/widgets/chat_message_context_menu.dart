import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:ren/features/chats/domain/chat_models.dart';
import 'package:ren/shared/widgets/context_menu.dart';
import 'package:ren/shared/widgets/glass_overlays.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

enum ChatMessageMenuAction { edit, reply, copy, share, select, delete }

Future<ChatMessageMenuAction?> showChatMessageContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required bool canEdit,
  required bool hasAttachments,
}) {
  return RenContextMenu.show<ChatMessageMenuAction>(
    context,
    globalPosition: globalPosition,
    entries: [
      if (canEdit)
        RenContextMenuEntry.action(
          RenContextMenuAction<ChatMessageMenuAction>(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedEdit02),
            label: 'Редактировать',
            value: ChatMessageMenuAction.edit,
          ),
        ),
      RenContextMenuEntry.action(
        RenContextMenuAction<ChatMessageMenuAction>(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowTurnBackward),
          label: 'Ответить',
          value: ChatMessageMenuAction.reply,
        ),
      ),
      RenContextMenuEntry.action(
        RenContextMenuAction<ChatMessageMenuAction>(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedCopy01),
          label: 'Копировать',
          value: ChatMessageMenuAction.copy,
        ),
      ),
      RenContextMenuEntry.action(
        RenContextMenuAction<ChatMessageMenuAction>(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowTurnForward),
          label: hasAttachments ? 'Переслать (без файлов)' : 'Переслать',
          value: ChatMessageMenuAction.share,
        ),
      ),
      RenContextMenuEntry.action(
        RenContextMenuAction<ChatMessageMenuAction>(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedTickDouble03),
          label: 'Выбрать',
          value: ChatMessageMenuAction.select,
        ),
      ),
      RenContextMenuEntry.action(
        RenContextMenuAction<ChatMessageMenuAction>(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete02),
          label: 'Удалить',
          danger: true,
          value: ChatMessageMenuAction.delete,
        ),
      ),
    ],
  );
}

Future<ChatPreview?> showForwardTargetChatPicker({
  required BuildContext context,
  required List<ChatPreview> chats,
}) {
  return GlassOverlays.showGlassBottomSheet<ChatPreview>(
    context,
    builder: (ctx) {
      final sheetHeight = (MediaQuery.of(ctx).size.height * 0.55)
          .clamp(280.0, 560.0)
          .toDouble();
      return GlassSurface(
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: sheetHeight,
            child: ListView.builder(
              itemCount: chats.length,
              itemBuilder: (c, i) {
                final it = chats[i];
                return ListTile(
                  title: Text(it.user.name),
                  subtitle: Text('chat ${it.id}'),
                  onTap: () => Navigator.of(ctx).pop(it),
                );
              },
            ),
          ),
        ),
      );
    },
  );
}
