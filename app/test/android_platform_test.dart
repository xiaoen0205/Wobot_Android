import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wobot/pages/robot_lab_page.dart';
import 'package:wobot/robot/link.dart';
import 'package:wobot/robot/robot.dart';
import 'package:wobot_faces/wobot_faces.dart';

import 'fake_robot.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'Android connects a robot without opening the iOS camera channel',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final ble = FakeBle()
        ..inReach.add(const FoundRobot('near', 'Wobot-Robot-AAAA', -40));
      final robot = Robot(
        RobotLink(ble, FakeMemory(), choose: const Duration(milliseconds: 10)),
        faces: phoneFaceSource(),
      );
      addTearDown(robot.dispose);

      await robot.open();

      expect(robot.faces, isNull);
      expect(robot.status.value.connected, isTrue);
      expect(robot.camera.value, isNull);
      await robot.pause();
      expect(robot.status.value.connected, isFalse);
    },
  );

  testWidgets(
    'Android face controls are disabled instead of calling native iOS',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final link = RobotLink(FakeBle(), FakeMemory());
      await tester.pumpWidget(MaterialApp(home: RobotLabPage(link: link)));

      final camera = find.widgetWithText(
        SwitchListTile,
        'Watch the front camera',
      );
      await tester.scrollUntilVisible(
        camera,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.widget<SwitchListTile>(camera).onChanged, isNull);
      expect(
        find.text('Face tracking is not available on this platform yet.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  test('iOS keeps its native face source', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(phoneFaceSource(), isA<PhoneFaceSource>());
  });
}
