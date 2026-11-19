import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:wobot/pages/voice_lab_page.dart';
import 'package:wobot/voice/speech_failure.dart';

/// Read-only native checks; never grants permission or records the microphone.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android speech capability and unsupported-device guidance',
    (tester) async {
      const channel = MethodChannel('wobot/device');
      final offline = await channel.invokeMethod<bool>(
        'isOnDeviceRecognitionAvailable',
      );
      final permission = await channel.invokeMethod<bool>(
        'hasMicrophonePermission',
      );
      expect(offline, isA<bool>());
      expect(permission, isA<bool>());
      await tester.pumpWidget(const MaterialApp(home: VoiceLabPage()));
      await tester.pumpAndSettle();
      if (offline == false) {
        await tester.tap(find.byIcon(Icons.mic));
        await tester.pumpAndSettle();
        expect(find.text(SpeechFailure.unavailable.message), findsOneWidget);
        expect(
          await channel.invokeMethod<bool>('hasMicrophonePermission'),
          permission,
        );
      }
      binding.reportData = {
        'on_device_recognition_available': offline,
        'microphone_already_allowed': permission,
      };
      debugPrint(
        'Android speech native check: offline=$offline, microphone=$permission',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: kIsWeb || defaultTargetPlatform != TargetPlatform.android,
  );
}
