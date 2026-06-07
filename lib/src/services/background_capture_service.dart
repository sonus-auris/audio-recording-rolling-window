import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class BackgroundCaptureService {
  void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'audio_dashcam_capture',
        channelName: 'Audio Dashcam',
        channelDescription: 'Shows while audio capture is active.',
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000),
        allowWakeLock: true,
        allowWifiLock: false,
        allowAutoRestart: true,
        stopWithTask: false,
      ),
    );
  }

  Future<String?> start() async {
    if (!Platform.isAndroid) {
      return null;
    }
    final notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (await FlutterForegroundTask.isRunningService) {
      return null;
    }
    final result = await FlutterForegroundTask.startService(
      serviceId: 500,
      serviceTypes: const [ForegroundServiceTypes.microphone],
      notificationTitle: 'Audio Dashcam is recording',
      notificationText: 'Rolling local window and cloud upload are active.',
      callback: audioDashcamForegroundCallback,
    );
    if (result is ServiceRequestFailure) {
      return result.error.toString();
    }
    return null;
  }

  Future<void> stop() async {
    if (!Platform.isAndroid) {
      return;
    }
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}

@pragma('vm:entry-point')
void audioDashcamForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(AudioDashcamForegroundTaskHandler());
}

class AudioDashcamForegroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    FlutterForegroundTask.sendDataToMain({
      'type': 'foreground-started',
      'timestamp': timestamp.toIso8601String(),
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    FlutterForegroundTask.sendDataToMain({
      'type': 'foreground-heartbeat',
      'timestamp': timestamp.toIso8601String(),
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    FlutterForegroundTask.sendDataToMain({
      'type': 'foreground-stopped',
      'timestamp': timestamp.toIso8601String(),
      'isTimeout': isTimeout,
    });
  }
}
