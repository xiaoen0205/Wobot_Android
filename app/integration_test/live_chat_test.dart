import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wobot/api.dart';
import 'package:wobot/chat.dart';
import 'package:wobot/main.dart' as app;
import 'package:wobot/pages/chat_page.dart';
import 'package:wobot/pages/history_drawer.dart';

const _enabled = bool.fromEnvironment('RUN_LIVE_CHAT_TESTS');
const _expectedEmail = String.fromEnvironment('LIVE_TEST_EMAIL');

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String description, {
  Duration timeout = const Duration(seconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out: $description');
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byTooltip('Send'));
  await tester.pump();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'signed-in chat streams, stops, retries, reopens and deletes its test chat',
    (tester) async {
      expect(
        _expectedEmail.isNotEmpty,
        isTrue,
        reason: 'Set LIVE_TEST_EMAIL in the ignored local configuration.',
      );
      expect(Uri.tryParse(apiBaseUrl)?.scheme, 'https');

      await app.main();
      await tester.pump();
      final user = await FirebaseAuth.instance.authStateChanges().first.timeout(
        const Duration(seconds: 20),
      );
      expect(
        user,
        isNotNull,
        reason: 'Sign in manually in the normal app before running this test.',
      );
      expect(
        user!.email?.toLowerCase() == _expectedEmail.toLowerCase(),
        isTrue,
        reason: 'The signed-in account must match the configured test account.',
      );
      await _until(
        tester,
        () => find.byType(ChatPage).evaluate().isNotEmpty,
        'authenticated chat page',
      );

      final page = tester.widget<ChatPage>(find.byType(ChatPage));
      final api = page.api;
      final chat = page.chat;
      final history = page.history;
      expect(
        page.me.email.toLowerCase() == _expectedEmail.toLowerCase(),
        isTrue,
      );

      // The test never opens or deletes a pre-existing conversation.
      await tester.tap(find.byTooltip('New chat'));
      await tester.pump();
      String? createdId;
      var deleted = false;
      final results = <String, dynamic>{'authenticated': true};
      binding.reportData = results;
      // Keep a real IME from overwriting synthetic editing values between sends.
      tester.testTextInput.register();
      try {
        final tag = DateTime.now().millisecondsSinceEpoch;
        await _send(
          tester,
          'Android QA $tag: Please reply with one short English sentence about testing an app.',
        );
        await _until(
          tester,
          () => chat.conversation != null,
          'test chat creation',
        );
        createdId = chat.conversation!.id;
        await _until(tester, () => !chat.busy, 'English reply');
        expect(chat.turns.single.state, TurnState.completed);
        expect(chat.turns.single.text.trim(), isNotEmpty);
        expect(chat.conversation!.title?.trim(), isNotEmpty);
        results['english_and_title'] = true;
        debugPrint('LIVE_CHAT: English reply and title passed.');

        const chinese = '這是 Android 測試。請用繁體中文簡短回覆一句話。';
        await _send(tester, chinese);
        await _until(tester, () => !chat.busy, 'Chinese reply');
        expect(chat.turns.last.question, chinese);
        expect(chat.turns.last.state, TurnState.completed);
        expect(
          RegExp(r'[\u3400-\u9fff]').hasMatch(chat.turns.last.text),
          isTrue,
        );
        results['chinese'] = true;
        debugPrint('LIVE_CHAT: Chinese reply passed.');

        await _send(
          tester,
          'Android cancellation check: Write 30 numbered complete sentences about testing a mobile app. '
          'Include every number from 1 to 30 without abbreviations or ellipses.',
        );
        await _until(
          tester,
          () => chat.turns.last.saved && chat.turns.last.text.isNotEmpty,
          'first streamed text',
        );
        expect(chat.busy, isTrue, reason: 'Stop must run before completion.');
        final prefix = chat.turns.last.text;
        final turnId = chat.turns.last.id;
        final attempt = chat.turns.last.attempt;
        await tester.tap(find.byTooltip('Stop'));
        await tester.pump();
        await _until(tester, () => !chat.busy, 'stopped UI');
        expect(chat.turns.last.state, TurnState.cancelled);
        final stoppedText = chat.turns.last.text;
        expect(stoppedText.startsWith(prefix), isTrue);

        // Check the server too: closing a Cloud Run stream alone cannot stop it.
        final stopDeadline = DateTime.now().add(const Duration(seconds: 15));
        while (true) {
          final record = (await api.turns(createdId)).items.last;
          if (record.status == 'cancelled') {
            expect(record.turnId, turnId);
            expect(record.replyText, stoppedText);
            break;
          }
          if (DateTime.now().isAfter(stopDeadline)) {
            fail('The server did not persist the stop.');
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        results['stop_preserves_streamed_text'] = true;
        debugPrint('LIVE_CHAT: Stop and server persistence passed.');

        await tester.pump();
        await tester.ensureVisible(find.text('Retry'));
        await tester.tap(find.text('Retry'));
        await tester.pump();
        await _until(tester, () => !chat.busy, 'retried reply');
        expect(chat.turns.last.state, TurnState.completed);
        expect(chat.turns.last.attempt, attempt + 1);
        expect(chat.turns.last.id, turnId);
        expect(chat.turns, hasLength(3));
        results['retry_without_duplicate_turn'] = true;
        debugPrint('LIVE_CHAT: Retry passed.');

        final saved = (await api.turns(createdId)).items;
        expect(saved, hasLength(3));
        expect(saved[1].userText, chinese);
        expect(saved.last.status, 'completed');
        expect(saved.last.attempt, attempt + 1);
        final finalReply = saved.last.replyText;

        await tester.tap(find.byTooltip('New chat'));
        await tester.pump();
        expect(chat.turns, isEmpty);
        await history.refresh();
        final conversation = history.conversations.firstWhere(
          (c) => c.id == createdId,
        );
        final title = conversation.title!;
        await tester.tap(find.byTooltip('Chats'));
        await tester.pump(const Duration(milliseconds: 400));
        final historyRow = find
            .descendant(
              of: find.byType(HistoryDrawer),
              matching: find.widgetWithText(ListTile, title),
            )
            .first;
        expect(history.conversations.first.id, createdId);
        await tester.tap(historyRow);
        await _until(
          tester,
          () => !chat.loading && chat.turns.length == 3,
          'history reopening',
        );
        expect(chat.turns.last.text, finalReply);
        expect(chat.turns.last.attempt, attempt + 1);
        results['history_reopens_saved_reply'] = true;
        debugPrint('LIVE_CHAT: History reopening passed.');

        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byTooltip('Chats'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.longPress(historyRow);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Delete chat?'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Delete'));
        await _until(
          tester,
          () => history.conversations.every((c) => c.id != createdId),
          'test chat deletion',
        );
        await expectLater(
          api.turns(createdId),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 404),
          ),
        );
        deleted = true;
        results['test_chat_deleted'] = true;
        debugPrint('LIVE_CHAT: Test chat deletion passed.');
      } finally {
        try {
          await chat.stop();
          await chat.startNew();
          if (createdId != null && !deleted) {
            try {
              await history.delete(createdId);
            } on ApiException catch (error) {
              if (error.statusCode != 404) rethrow;
            }
          }
        } finally {
          tester.testTextInput.unregister();
        }
      }
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
