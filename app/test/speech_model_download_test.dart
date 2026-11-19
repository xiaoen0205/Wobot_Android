import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wobot/voice/speech_failure.dart';
import 'package:wobot/widgets/notes.dart';

void main() {
  const channel = MethodChannel('wobot/device');
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'missing model requests the selected language and awaits readiness',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final pending = Completer<String>();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return pending.future;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpeechErrorNote(
              SpeechFailure.language.message,
              localeId: 'en-US',
            ),
          ),
        ),
      );
      await tester.tap(find.text('Download offline model'));
      await tester.pump();
      expect(calls.single.method, 'downloadSpeechModel');
      expect(calls.single.arguments['localeId'], 'en-US');
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      pending.complete('downloaded');
      await tester.pumpAndSettle();
      expect(
        find.text('Offline model is ready. Tap the microphone to try again.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('scheduled download is not reported as ready', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(channel, (_) async => 'scheduled');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpeechErrorNote(
            SpeechFailure.language.message,
            localeId: 'en-US',
          ),
        ),
      ),
    );
    await tester.tap(find.text('Download offline model'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Download requested.'), findsOneWidget);
    expect(find.textContaining('Offline model is ready.'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('unsupported language does not offer a model download', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpeechErrorNote(
            SpeechFailure.unsupportedLanguage.message,
            localeId: 'zh-TW',
          ),
        ),
      ),
    );
    expect(find.text('Download offline model'), findsNothing);
    expect(
      find.text(SpeechFailure.unsupportedLanguage.message),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
