import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:wobot/pages/voice_lab_page.dart';
import 'package:wobot/voice/listener.dart';
import 'package:wobot/voice/speech_failure.dart';

import 'fake_speech.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const device = MethodChannel('wobot/device');
  const speechChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late SpeechToText speech;
  late DeviceSpeechEngine engine;
  late bool offline;
  late bool permission;
  late List<MethodCall> speechCalls;
  late List<String> deviceCalls;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    speech = SpeechToText.withMethodChannel();
    engine = DeviceSpeechEngine(recognizer: speech);
    offline = true;
    permission = true;
    speechCalls = [];
    deviceCalls = [];
    messenger.setMockMethodCallHandler(device, (call) async {
      deviceCalls.add(call.method);
      return switch (call.method) {
        'isOnDeviceRecognitionAvailable' => offline,
        'hasMicrophonePermission' => permission,
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(speechChannel, (call) async {
      speechCalls.add(call);
      return call.method == 'initialize' ? permission : true;
    });
  });

  tearDown(() async {
    await speech.cancel();
    messenger.setMockMethodCallHandler(device, null);
    messenger.setMockMethodCallHandler(speechChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<bool> initialize() =>
      engine.initialize(onError: (_) {}, onStatus: (_) {});

  Future<void> nativeCallback(String method, Object arguments) async {
    final done = Completer<void>();
    // Exercise the real plugin's filtering as well as QuestionListener's state.
    messenger.handlePlatformMessage(
      speechChannel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) => done.complete(),
    );
    await done.future;
  }

  test(
    'native doneNoResult does not suppress a queued language error',
    () async {
      final listener = QuestionListener(
        engine,
        finalWait: const Duration(milliseconds: 50),
      );
      addTearDown(listener.dispose);
      final heard = listener.listen();
      await pumpEventQueue();
      await nativeCallback('notifyStatus', 'doneNoResult');
      await nativeCallback(
        'notifyError',
        jsonEncode({
          'errorMsg': 'error_language_unavailable',
          'permanent': true,
        }),
      );
      await heard;
      expect(listener.error, SpeechFailure.language.message);
      expect(speechCalls.where((call) => call.method == 'stop'), isEmpty);
    },
  );

  test(
    'no offline service never requests permission or starts a recognizer',
    () async {
      offline = false;
      await expectLater(initialize(), throwsA(SpeechFailure.unavailable));
      expect(speechCalls, isEmpty);
    },
  );

  test(
    'permission refusal is distinguished from missing recognition',
    () async {
      permission = false;
      await expectLater(initialize(), throwsA(SpeechFailure.permission));
    },
  );

  test(
    'uses offline recognition and requests no Bluetooth permission',
    () async {
      await initialize();
      expect(speechCalls.single.arguments['noBluetooth'], isTrue);
      await engine.listen(localeId: 'zh-TW', onResult: (_, _) {});
      final call = speechCalls.lastWhere((call) => call.method == 'listen');
      expect(call.arguments['onDevice'], isTrue);
      expect(call.arguments['localeId'], 'zh-TW');
      offline = false;
      final listens = speechCalls
          .where((call) => call.method == 'listen')
          .length;
      await expectLater(
        engine.listen(localeId: 'en-US', onResult: (_, _) {}),
        throwsA(SpeechFailure.unavailable),
      );
      expect(
        speechCalls.where((call) => call.method == 'listen').length,
        listens,
      );
    },
  );

  test(
    'cached native initialization refreshes callbacks and checks revoked permission',
    () async {
      var oldErrors = 0;
      var newErrors = 0;
      await engine.initialize(onError: (_) => oldErrors++, onStatus: (_) {});
      await engine.initialize(onError: (_) => newErrors++, onStatus: (_) {});
      speech.errorListener!(SpeechRecognitionError('error_permission', true));
      expect(oldErrors, 0);
      expect(newErrors, 1);
      expect(
        speechCalls.where((call) => call.method == 'initialize'),
        hasLength(1),
      );
      permission = false;
      await expectLater(initialize(), throwsA(SpeechFailure.permission));
    },
  );

  testWidgets(
    'missing language errors are not presented as microphone silence',
    (tester) async {
      final fake = FakeEngine();
      await tester.pumpWidget(MaterialApp(home: VoiceLabPage(engine: fake)));
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      fake.onError('error_language_unavailable');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text(SpeechFailure.language.message), findsOneWidget);
      expect(find.text('No speech detected. Try again.'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('permission denial offers Android app settings and retry works', (
    tester,
  ) async {
    final fake = FakeEngine()..initializationError = SpeechFailure.permission;
    await tester.pumpWidget(MaterialApp(home: VoiceLabPage(engine: fake)));
    await tester.tap(find.byIcon(Icons.mic));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open Settings'));
    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();
    expect(deviceCalls, contains('openAppSettings'));
    fake.initializationError = null;
    await tester.ensureVisible(find.byIcon(Icons.mic));
    await tester.tap(find.byIcon(Icons.mic));
    await tester.pump();
    fake.say('Test question', isFinal: true);
    await tester.pumpAndSettle();
    expect(find.text('Test question'), findsOneWidget);
    expect(find.text('Open Settings'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
