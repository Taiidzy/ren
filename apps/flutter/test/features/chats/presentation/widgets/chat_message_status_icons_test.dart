import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ren/features/chats/presentation/widgets/chat_message_bubble.dart';

Widget _host(ChatMessageBubble child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('shows pending icon for my pending message', (tester) async {
    await tester.pumpWidget(
      _host(
        const ChatMessageBubble(
          text: 'pending',
          timeLabel: '10:00',
          isMe: true,
          isPending: true,
          isDark: false,
        ),
      ),
    );

    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(find.byIcon(Icons.done_rounded), findsNothing);
    expect(find.byIcon(Icons.done_all_rounded), findsNothing);
  });

  testWidgets('shows single check for sent message', (tester) async {
    await tester.pumpWidget(
      _host(
        const ChatMessageBubble(
          text: 'sent',
          timeLabel: '10:01',
          isMe: true,
          isPending: false,
          isDelivered: false,
          isRead: false,
          isDark: false,
        ),
      ),
    );

    expect(find.byIcon(Icons.done_rounded), findsOneWidget);
    expect(find.byIcon(Icons.schedule_rounded), findsNothing);
  });

  testWidgets('shows double check for delivered message', (tester) async {
    await tester.pumpWidget(
      _host(
        const ChatMessageBubble(
          text: 'delivered',
          timeLabel: '10:02',
          isMe: true,
          isPending: false,
          isDelivered: true,
          isRead: false,
          isDark: false,
        ),
      ),
    );

    expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
    expect(find.byIcon(Icons.schedule_rounded), findsNothing);
  });

  testWidgets('hides status icon for incoming message', (tester) async {
    await tester.pumpWidget(
      _host(
        const ChatMessageBubble(
          text: 'incoming',
          timeLabel: '10:03',
          isMe: false,
          isPending: false,
          isDelivered: false,
          isRead: false,
          isDark: false,
        ),
      ),
    );

    expect(find.byIcon(Icons.schedule_rounded), findsNothing);
    expect(find.byIcon(Icons.done_rounded), findsNothing);
    expect(find.byIcon(Icons.done_all_rounded), findsNothing);
  });
}
