import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards for the v4.15 widget up-next queue release.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('widget carries a tappable up-next queue', () {
    final provider = read(
      'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/SwaraWidgetProvider.kt',
    );
    expect(provider.contains('KEY_QUEUE = "queue_json"'), isTrue);
    expect(provider.contains('ACTION_PLAY_SLOT'), isTrue);
    expect(provider.contains('setRemoteAdapter('), isTrue);
    expect(provider.contains('notifyAppWidgetViewDataChanged('), isTrue);
    final service = read(
      'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/SwaraWidgetViewsService.kt',
    );
    expect(service.contains('BIND_REMOTEVIEWS'), isFalse);
    expect(service.contains('RemoteViewsService.RemoteViewsFactory'), isTrue);
    expect(service.contains('setOnClickFillInIntent'), isTrue);
    expect(service.contains('JSONArray(raw)'), isTrue);
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    expect(manifest.contains('<service\n            android:name=".SwaraWidgetViewsService"'), isTrue);
    expect(provider.contains('setPendingIntentTemplate('), isTrue);
    expect(provider.contains('FLAG_MUTABLE'), isTrue);
    expect(provider.contains('notifyAppWidgetViewDataChanged('), isTrue);
  });

  test('Dart builds and verifies the queue snapshot', () {
    final main = read('lib/main.dart');
    expect(main.contains("'queueJson': queueJson"), isTrue);
    expect(main.contains('fingerprint != lastQueueFingerprint'), isTrue);
    expect(main.contains("action.startsWith('swara.widget.PLAY_SLOT:')"), isTrue);
    expect(main.contains('service.queuePosForSlot(slotId)'), isTrue);
    expect(main.contains('service.songAtOrderIndex(i)?.filePath == path'), isTrue);
    final activity = read(
      'android/app/src/main/kotlin/com/nikodwidharma/offline_music_player/MainActivity.kt',
    );
    expect(activity.contains('queueJson'), isTrue);
  });

  test('widget layout and strings expose the queue', () {
    final layout = read('android/app/src/main/res/layout/swara_widget.xml');
    expect(layout.contains('@+id/widget_queue'), isTrue);
    final row = read('android/app/src/main/res/layout/swara_widget_queue_row.xml');
    expect(row.contains('@+id/widget_queue_row'), isTrue);
    expect(read('android/app/src/main/res/xml/swara_widget_info.xml')
        .contains('220dp'), isTrue);
    for (final name in ['values/strings.xml', 'values-id/strings.xml']) {
      expect(read('android/app/src/main/res/$name')
          .contains('widget_queue_label'), isTrue);
    }
  });
}
