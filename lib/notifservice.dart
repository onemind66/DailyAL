import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:dailyanimelist/api/dalapi.dart';
import 'package:dailyanimelist/api/maluser.dart';
import 'package:dailyanimelist/constant.dart';
import 'package:dailyanimelist/enums.dart';
import 'package:dailyanimelist/generated/l10n.dart';
import 'package:dailyanimelist/main.dart';
import 'package:dailyanimelist/screens/openscreen.dart';
import 'package:dailyanimelist/user/user.dart';
import 'package:dailyanimelist/widgets/user/contentlistwidget.dart';
import 'package:dailyanimelist/util/linux_desktop_helper.dart';
import 'package:dal_commons/commons.dart';
import 'package:dal_commons/dal_commons.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationChannel {
  final String channelName;
  final String channelId;
  final String channelDescription;
  NotificationChannel._({
    required this.channelName,
    required this.channelId,
    required this.channelDescription,
  });
  static NotificationChannel planToWatch() {
    return NotificationChannel._(
      channelName: 'PlanToWatch List Anime',
      channelId: 'PlanToWatch',
      channelDescription: S.current.PlanToWatchDesc,
    );
  }

  static NotificationChannel watching() {
    return NotificationChannel._(
      channelName: 'Watching List Anime',
      channelId: 'Watching',
      channelDescription: S.current.WatchingDesc,
    );
  }
}

class NotificationService {
  static final NotificationService _notificationService =
      NotificationService._internal();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  // Keep references to Linux timers so pending callbacks can be cancelled.
  final Map<int, Timer> _linuxNotificationTimers = <int, Timer>{};

  factory NotificationService() {
    return _notificationService;
  }

  NotificationService._internal();

  Future<void> init() async {
    final AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_stat_name');

    tz.initializeTimeZones();

    final InitializationSettings initializationSettings =
        InitializationSettings(
            android: initializationSettingsAndroid,
            iOS: null,
            macOS: null,
            linux: LinuxInitializationSettings(defaultActionName: 'Open'));

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveBackgroundNotificationResponse:
          onDidReceiveBackgroundNotificationResponse,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );
  }

  Future<Node?> onSelectWhileAsleep() async {
    try {
      var details = await NotificationService()
          .flutterLocalNotificationsPlugin
          .getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        logDal('Notif launched dal');
        Node _node = Node.fromJson(
            jsonDecode(details?.notificationResponse?.payload ?? '{}'));
        logDal(_node.toJson());
        if (_node.id != null) {
          return _node;
        }
      } else {
        logDal('auto dal');
      }
    } catch (e) {
      logDal(e);
    }

    return null;
  }

  static void selectNotification(String? payload) async {
    try {
      Node _node = Node.fromJson(jsonDecode(payload ?? '{}'));

      final context = MyApp.navigatorKey.currentContext;
      if (_node.id != null && context != null) {
        logDal("--> payload works for MAL id=${_node.id}");
        if (Platform.isLinux) {
          await windowManager.show();
          await windowManager.focus();
        }
        gotoPage(
            context: context,
            newPage: OpenScreen(notifNode: _node));
      } else {
        logDal("--> ignoring invalid notification payload");
      }
    } catch (e) {
      logDal("--> payload error $e");
    }
  }

  Future<void> scheduledNotifcation() async {
    final nowDate = DateTime.now();
    final notifPref = user.pref.notifPref;

    // Turning both notification categories off must remove previously scheduled
    // reminders even when the device is offline.
    if (!notifPref.onWatchingListUpdated &&
        !notifPref.onPTWGoesToWatching) {
      await _cancelStaleScheduledNotifications(const <int>{});
      return;
    }

    if (!await hasConnection()) {
      logDal('Skipping notification sync while offline; keeping existing reminders');
      return;
    }

    if (user.status != AuthStatus.AUTHENTICATED) {
      logDal('Skipping notification sync: a signed-in MAL account is required.');
      return;
    }

    Map<int, ScheduleData>? scheduleData;
    List<BaseNode>? listItems;
    try {
      // Use the user's own list rather than the current seasonal catalogue,
      // so older anime that are still being watched are not silently omitted.
      DalApi.i.resetScheduleForMalIds();
      final results = await Future.wait<Object>([
        MalUser.getAllUserList(
          '@me',
          'anime',
          status: 'watching',
          fromCache: true,
          fields: 'main_picture,status,num_episodes',
          requireComplete: true,
        ),
        MalUser.getAllUserList(
          '@me',
          'anime',
          status: 'plan_to_watch',
          fromCache: true,
          fields: 'main_picture,status,num_episodes',
          requireComplete: true,
        ),
        DalApi.i.scheduleForMalIds,
      ]);
      final watching = results[0] as SearchResult;
      final planToWatch = results[1] as SearchResult;
      scheduleData = results[2] as Map<int, ScheduleData>;
      listItems = <BaseNode>[
        ...?watching.data,
        ...?planToWatch.data,
      ];
    } catch (e, stackTrace) {
      logDal('Skipping notification reconciliation because list/schedule data failed: $e');
      logDal(stackTrace);
      return;
    }

    if (listItems == null) {
      logDal('Skipping notification reconciliation: MAL list response has no data.');
      return;
    }
    if (scheduleData == null ||
        (scheduleData.isEmpty && listItems.isNotEmpty)) {
      // A missing schedule response is not proof that reminders are stale.
      // A genuinely empty, successfully fetched MAL list can still be reconciled.
      logDal('Skipping notification reconciliation: schedule data is empty.');
      return;
    }

    const validMyListStatus = ["watching", "plan_to_watch"];
    final expectedNotificationIds = <int>{};
    var allSchedulesSucceeded = true;

    for (var baseNode in listItems) {
      var node = baseNode.content;
      if (node == null || node.id == null) {
        allSchedulesSucceeded = false;
        continue;
      }
      node.title = getNodeTitle(node);
      if (node.myListStatus is MyAnimeListStatus) {
        var myListStatus = node?.myListStatus as MyAnimeListStatus;
        if (myListStatus.status == null) {
          expectedNotificationIds.add(2100 + node.id!);
          allSchedulesSucceeded = false;
          continue;
        }
        if (!validMyListStatus.contains(myListStatus.status)) {
          continue;
        }
        if (myListStatus.status!.equals("watching")) {
          if (!user.pref.notifPref.onWatchingListUpdated) {
            continue;
          }
        }

        if (myListStatus.status!.equals("plan_to_watch")) {
          if (!user.pref.notifPref.onPTWGoesToWatching) {
            continue;
          }
        }
        String body;
        NotificationChannel channel;
        if (myListStatus.status!.equals("watching")) {
          body = S.current.Notif_Update_watchList;
          channel = NotificationChannel.watching();
        } else {
          body = S.current.Notif_Update_PTW;
          channel = NotificationChannel.planToWatch();
        }

        if (scheduleData.containsKey(node.id)) {
          final liveSchedule = scheduleData[node.id]!;
          final timestamp = liveSchedule.timestamp;
          if (timestamp == null) {
            expectedNotificationIds.add(2100 + node.id!);
            allSchedulesSucceeded = false;
            logDal("Missing schedule timestamp for ${node.title}; preserving existing reminder.");
            continue;
          }

          final nextDate = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
          if (!nextDate.isAfter(nowDate)) {
            logDal("Skipping expired schedule for ${node.title}");
            continue;
          }

          final scheduled = await _scheduleUsingLiveChart(
            liveSchedule,
            myListStatus,
            node,
            nowDate,
            body,
            channel,
          );
          if (scheduled) {
            expectedNotificationIds.add(2100 + node.id!);
          } else {
            allSchedulesSucceeded = false;
            expectedNotificationIds.add(2100 + node.id!);
            logDal('Failed to schedule reminder for MAL id=' + node.id.toString() +
                '; preserving existing reminders.');
          }
        } else {
          expectedNotificationIds.add(2100 + node.id!);
          allSchedulesSucceeded = false;
          logDal("No schedule data for ${node.title}; preserving existing reminder.");
        }
      } else {
        expectedNotificationIds.add(2100 + node.id!);
        allSchedulesSucceeded = false;
      }
    }

    // Do not cancel any existing reminder if even one replacement failed.
    if (!allSchedulesSucceeded) return;

    final reconciled =
        await _cancelStaleScheduledNotifications(expectedNotificationIds);
    if (!reconciled) {
      logDal('Notification reconciliation failed; sync timestamp was not updated.');
      return;
    }
    user.pref.notifPref.daySubscribed = nowDate;
    await user.setIntance();
  }

  Future<bool> _cancelStaleScheduledNotifications(
      Set<int> expectedNotificationIds) async {
    if (Platform.isLinux) {
      final staleIds = _linuxNotificationTimers.keys
          .where((id) => !expectedNotificationIds.contains(id))
          .toList(growable: false);
      for (final id in staleIds) {
        _linuxNotificationTimers.remove(id)?.cancel();
        logDal('Cancelled stale Linux anime reminder id=$id');
      }
      return true;
    }

    try {
      final pending = await flutterLocalNotificationsPlugin
          .pendingNotificationRequests();

      for (final request in pending) {
        if (request.payload == null) continue;

        dynamic payload;
        try {
          payload = jsonDecode(request.payload!);
        } catch (e) {
          logDal('Unable to decode pending notification id=${request.id}: $e');
          continue;
        }
        if (payload is! Map<String, dynamic>) continue;
        final nodeId = payload['id'];
        if (nodeId is! int || request.id != 2100 + nodeId) continue;
        if (expectedNotificationIds.contains(request.id)) continue;

        try {
          await flutterLocalNotificationsPlugin.cancel(id: request.id);
          logDal('Cancelled stale anime reminder id=${request.id}, malId=$nodeId');
        } catch (e) {
          logDal('Failed to cancel stale anime reminder id=${request.id}: $e');
          return false;
        }
      }
      return true;
    } catch (e) {
      logDal('Failed to reconcile pending anime notifications: $e');
      return false;
    }
  }

  Future<bool> _scheduleUsingLiveChart(
    ScheduleData scheduleData,
    MyAnimeListStatus myListStatus,
    Node node,
    DateTime nowDate,
    String body,
    NotificationChannel channel,
  ) async {
    final timestamp = scheduleData.timestamp;
    if (timestamp == null) {
      logDal('Cannot schedule reminder without timestamp for MAL id=' + node.id.toString() + '.');
      return false;
    }
    final nextDate = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final title = "Ep: ${scheduleData.episode} of ${node.title} is out!";

    return _showNotificationAndReport(
      serviceId: 21,
      title: title,
      body: body,
      node: node,
      exactDate: nextDate,
      channel: channel,
      downloadImage: true,
    );
  }

  static final iconPath =
      'https://play-lh.googleusercontent.com/ZR5oY99qg9mdL9EGDlP3uKDeu0icE3wCGFor3IaAL0xVXXXYQciXavnUVvXFzcQx59w=w240-h480-rw';

  Future<bool> showNotification({
    int episode = 1,
    int serviceId = 21,
    Node? node,
    String? title,
    String? body,
    DateTime? exactDate,
    Duration addTime = const Duration(milliseconds: 300),
    required NotificationChannel channel,
  }) async {
    return _showNotificationAndReport(
      episode: episode,
      serviceId: serviceId,
      node: node,
      title: title,
      body: body,
      exactDate: exactDate,
      addTime: addTime,
      channel: channel,
    );
  }

  Future<bool> _showNotificationAndReport({
    int episode = 1,
    int serviceId = 21,
    Node? node,
    String? title,
    String? body,
    DateTime? exactDate,
    Duration addTime = const Duration(milliseconds: 300),
    required NotificationChannel channel,
    bool downloadImage = true,
  }) async {
    final notificationNode = node;
    final nodeId = notificationNode?.id;
    if (notificationNode == null || nodeId == null) {
      logDal('Skipping notification without a valid MAL id.');
      return false;
    }

    if (exactDate != null && !exactDate.isAfter(DateTime.now())) {
      logDal(
          'Skipping notification scheduled in the past for MAL id=' +
              nodeId.toString() +
              '.');
      return false;
    }

    logDal(
        "${serviceId * 100 + nodeId} -> $title - $body - scheduled for ${exactDate ?? DateTime.now().add(addTime)}");

    String? imagePath;
    FilePathAndroidBitmap? largeIconBitmap;
    if (downloadImage &&
        notificationNode.mainPicture?.large != null &&
        notificationNode.title != null) {
      imagePath = await _downloadAndSaveFile(
        notificationNode.mainPicture!.large!,
        nodeId,
      );
    }

    StyleInformation? styleInfo;
    if (imagePath != null) {
      largeIconBitmap = FilePathAndroidBitmap(imagePath);
      if (user.pref.notifPref.preferLargeImage) {
        styleInfo = BigPictureStyleInformation(
          FilePathAndroidBitmap(imagePath),
          largeIcon: largeIconBitmap,
          contentTitle: title,
          htmlFormatContentTitle: true,
          summaryText: body,
          htmlFormatSummaryText: true,
          hideExpandedLargeIcon: true,
        );
      }
    }

    try {
      if (Platform.isLinux) {
        final notificationId = serviceId * 100 + nodeId;
        _linuxNotificationTimers.remove(notificationId)?.cancel();
        final delay = exactDate?.difference(DateTime.now()) ?? addTime;
        late final Timer timer;
        timer = Timer(delay, () async {
          if (identical(_linuxNotificationTimers[notificationId], timer)) {
            _linuxNotificationTimers.remove(notificationId);
          }
          await _showLinuxNotification(serviceId, notificationNode, title, body,
              episode, imagePath);
        });
        _linuxNotificationTimers[notificationId] = timer;
      } else {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          id: serviceId * 100 + nodeId,
          title: _replaceTags(title) ??
              "DailyAnimeList - ${S.current.Episode_Reminder}",
          body: _replaceTags(body) ??
              "${notificationNode.title} - Episode $episode ${S.current.just_got_aired}!!",
          scheduledDate: exactDate != null
              ? tz.TZDateTime.from(exactDate, tz.local)
              : tz.TZDateTime.now(tz.local).add(addTime),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              channel.channelId,
              channel.channelName,
              channelDescription: channel.channelDescription,
              priority: Priority.high,
              styleInformation: styleInfo,
              icon: 'ic_stat_name',
              largeIcon: largeIconBitmap,
              category: AndroidNotificationCategory.reminder,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: jsonEncode(notificationNode.toJson()),
        );
      }
    } catch (e, stackTrace) {
      logDal('Failed to schedule notification for MAL id=' +
          nodeId.toString() +
          ': $e');
      logDal(stackTrace);
      return false;
    }
    return true;
  }

  Future<void> _showLinuxNotification(int serviceId, Node node, String? title,
      String? body, int episode, String? imagePath) async {
    final cleanTitle =
        _replaceTags(title) ?? "DailyAnimeList - ${S.current.Episode_Reminder}";
    final cleanBody = _replaceTags(body) ??
        "${node.title} - Episode $episode ${S.current.just_got_aired}!!";

    if (LinuxDesktopHelper.hasLibNotify) {
      try {
        final iconPath = LinuxDesktopHelper.appIconPath;
        final hasAnimeImage = imagePath != null && File(imagePath).existsSync();
        final LinuxNotificationIcon? linuxIcon = hasAnimeImage
            ? FilePathLinuxIcon(imagePath)
            : (iconPath != null ? FilePathLinuxIcon(iconPath) : null);

        await flutterLocalNotificationsPlugin.show(
          id: serviceId * 100 + node.id!,
          title: cleanTitle,
          body: cleanBody,
          notificationDetails: NotificationDetails(
            linux: LinuxNotificationDetails(
              urgency: LinuxNotificationUrgency.normal,
              icon: linuxIcon,
            ),
          ),
          payload: jsonEncode(node.toJson()),
        );
      } catch (e) {
        logDal('Native Linux notification failed, falling back to overlay: $e');
        showToast('$cleanTitle\n$cleanBody');
      }
    } else {
      showToast('$cleanTitle\n$cleanBody');
    }
  }

  String? _replaceTags(String? body) {
    if (body == null) return null;
    return body
        .replaceAll('<b>', '')
        .replaceAll('</b>', '')
        .replaceAll('<i>', '')
        .replaceAll('</i>', '');
  }

  Future<String?> _downloadAndSaveFile(String url, int malId) async {
    try {
      final imageUri = Uri.tryParse(url);
      if (imageUri == null ||
          (imageUri.scheme != 'https' && imageUri.scheme != 'http') ||
          imageUri.host.isEmpty) {
        logDal('Skipping notification image for MAL id=$malId: invalid image URL.');
        return null;
      }

      final Directory appDirectory = await getApplicationDocumentsDirectory();
      final Directory imageDirectory =
          Directory('${appDirectory.path}/notification_images');
      await imageDirectory.create(recursive: true);

      // Cache the image before making a network request. A fixed extension is
      // intentional: Android/Linux image decoders inspect the file contents.
      final File imageFile = File('${imageDirectory.path}/$malId.img');
      if (await imageFile.exists()) {
        final cachedLength = await imageFile.length();
        if (cachedLength > 0 && cachedLength <= 8 * 1024 * 1024) {
          return imageFile.path;
        }
        await imageFile.delete();
      }

      final http.Response response = await http
          .get(imageUri)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        logDal(
            'Notification image download failed for MAL id=$malId: HTTP ${response.statusCode}.');
        return null;
      }
      if (response.bodyBytes.isEmpty ||
          response.bodyBytes.length > 8 * 1024 * 1024) {
        logDal(
            'Skipping notification image for MAL id=$malId: empty image or image exceeds 8 MiB.');
        return null;
      }

      final contentType =
          response.headers['content-type']?.split(';').first.trim().toLowerCase();
      if (contentType != null &&
          !contentType.startsWith('image/') &&
          contentType != 'application/octet-stream') {
        logDal(
            'Skipping notification image for MAL id=$malId: unexpected content type $contentType.');
        return null;
      }

      await imageFile.writeAsBytes(response.bodyBytes, flush: true);
      logDal('Downloaded notification image for MAL id=$malId (${response.bodyBytes.length} bytes).');
      return imageFile.path;
    } catch (e, stackTrace) {
      logDal('Notification image download failed for MAL id=$malId: $e');
      logDal(stackTrace);
      return null;
    }
  }

  Future<void> askForPermission() async {
    if (Platform.isLinux) return;
    if (!user.pref.notifPref.onPTWGoesToWatching &&
        !user.pref.notifPref.onWatchingListUpdated) {
      return;
    }

    final notifPerm = await Permission.notification.status;
    final alarmPerm = await Permission.scheduleExactAlarm.status;
    if (notifPerm.isGranted && alarmPerm.isGranted) return;

    final allowed = await showConfirmationDialog(
      alertTitle: S.current.ConfirmNotifPerm,
      desc: S.current.ConfirmNotifPermDesc,
      context: MyApp.navigatorKey.currentContext!,
    );
    final permissionsGranted =
        allowed && await _askNotifPermissionUsingLocal();

    if (!permissionsGranted) {
      user.pref.notifPref.onPTWGoesToWatching = false;
      user.pref.notifPref.onWatchingListUpdated = false;
      await user.setIntance();
    }
  }

  Future<bool> _askNotifPermissionUsingLocal() async {
    if (Platform.isLinux) return true;
    FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    // Request both permissions independently: denying exact alarms should not
    // prevent Android from presenting the notification-permission prompt.
    final alarmGranted =
        (await _getAlarmPerm(flutterLocalNotificationsPlugin)) ?? false;
    final notificationsGranted =
        (await _getNotificationPerm(flutterLocalNotificationsPlugin)) ?? false;
    return alarmGranted && notificationsGranted;
  }

  Future<bool?> _getAlarmPerm(
      FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin) async {
    return await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();
  }

  Future<bool?> _getNotificationPerm(
      FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin) async {
    return await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static void onDidReceiveBackgroundNotificationResponse(
      NotificationResponse details) {
    logDal(details);
  }

  static void onDidReceiveNotificationResponse(NotificationResponse details) {
    selectNotification(details.payload);
  }
}
