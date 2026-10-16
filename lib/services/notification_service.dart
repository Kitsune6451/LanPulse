import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

typedef NotificationActionCallback = void Function(
  String transferId,
  bool accepted,
);

class NotificationAndBackgroundService {
  static final NotificationAndBackgroundService instance =
      NotificationAndBackgroundService._();
  NotificationAndBackgroundService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  NotificationActionCallback? onFileRequestDecision;
  VoidCallback? onStopBackgroundRequested;
  bool _initialized = false;

  static const int _foregroundServiceNotifId = 1001;
  static const int _progressNotifId = 2001;
  static const int _completionNotifId = 2002;

  Future<void> initialize({
    NotificationActionCallback? onDecision,
    VoidCallback? onStopApp,
  }) async {
    onFileRequestDecision = onDecision;
    onStopBackgroundRequested = onStopApp;
    if (_initialized) return;

    if (Platform.isAndroid) {
      const AndroidInitializationSettings androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initSettings =
          InitializationSettings(android: androidInit);

      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );

      final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();

      await _startAndroidForegroundService(androidPlugin);
    }
    _initialized = true;
  }

  Future<void> _startAndroidForegroundService(
    AndroidFlutterLocalNotificationsPlugin? androidPlugin,
  ) async {
    if (!Platform.isAndroid || androidPlugin == null) return;
    try {
      const AndroidNotificationDetails fgDetails = AndroidNotificationDetails(
        'lanpulse_bg_service',
        'Servizio Background LanPulse',
        channelDescription:
            'Mantiene attivo l\'ascolto P2P sulla rete Wi-Fi in background',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        playSound: false,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            'STOP_BACKGROUND_APP',
            'Chiudi App',
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      );

      await androidPlugin.startForegroundService(
        _foregroundServiceNotifId,
        'LanPulse P2P Attivo',
        'In ascolto sulla rete Wi-Fi • Tocca Chiudi App per terminare',
        notificationDetails: fgDetails,
        foregroundServiceTypes: {
          AndroidServiceForegroundType.foregroundServiceTypeDataSync,
        },
      );
    } catch (_) {}
  }

  void _onNotificationResponse(NotificationResponse response) {
    final String? payload = response.payload;

    if (response.actionId == 'STOP_BACKGROUND_APP') {
      onStopBackgroundRequested?.call();
      return;
    }

    if (payload == null || payload.isEmpty) return;

    if (response.actionId == 'ACCEPT_FILE') {
      onFileRequestDecision?.call(payload, true);
    } else if (response.actionId == 'REJECT_FILE') {
      onFileRequestDecision?.call(payload, false);
    }
  }

  Future<void> showIncomingFileRequestNotification({
    required String transferId,
    required String senderAlias,
    required String fileName,
    required String formattedSize,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      final int notifId = transferId.hashCode.abs() % 100000;
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'lanpulse_requests_channel',
        'Richieste di Invio File',
        channelDescription:
            'Notifiche per accettare o rifiutare file in entrata in background',
        importance: Importance.max,
        priority: Priority.high,
        ongoing: true,
        autoCancel: true,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            'ACCEPT_FILE',
            'Accetta',
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            'REJECT_FILE',
            'Rifiuta',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ],
      );

      await _notifications.show(
        notifId,
        'Richiesta file da $senderAlias',
        '"$fileName" ($formattedSize) • Tocca Accetta o Rifiuta',
        const NotificationDetails(android: androidDetails),
        payload: transferId,
      );
    } catch (_) {}
  }

  Future<void> cancelRequestNotification(String transferId) async {
    if (!Platform.isAndroid) return;
    try {
      final int notifId = transferId.hashCode.abs() % 100000;
      await _notifications.cancel(notifId);
    } catch (_) {}
  }

  Future<void> showTransferProgressNotification({
    required String fileName,
    required String peerAlias,
    required bool isOutgoing,
    required int progressPercent,
    required bool isPaused,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'lanpulse_progress_channel',
        'Avanzamento Trasferimenti',
        channelDescription: 'Stato di avanzamento dei file inviati e ricevuti',
        importance: Importance.low,
        priority: Priority.low,
        onlyAlertOnce: true,
        ongoing: true,
        showProgress: true,
        maxProgress: 100,
        progress: progressPercent.clamp(0, 100),
      );

      final String prefix = isPaused
          ? 'In pausa'
          : (isOutgoing ? 'Invio a $peerAlias' : 'Ricezione da $peerAlias');

      await _notifications.show(
        _progressNotifId,
        '$prefix ($progressPercent%)',
        fileName,
        NotificationDetails(android: androidDetails),
      );
    } catch (_) {}
  }

  Future<void> showTransferCompletedNotification({
    required String fileName,
    required String peerAlias,
    required bool isOutgoing,
    required bool success,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _notifications.cancel(_progressNotifId);

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'lanpulse_completion_channel',
        'Completamento Trasferimenti',
        channelDescription: 'Avvisi di completamento trasferimento file',
        importance: Importance.high,
        priority: Priority.high,
      );

      final String title = success
          ? (isOutgoing
              ? 'File inviato a $peerAlias'
              : 'File ricevuto da $peerAlias')
          : 'Trasferimento interrotto';

      final String body = success
          ? 'Completato: "$fileName"'
          : 'Il trasferimento di "$fileName" è stato annullato o interrotto.';

      await _notifications.show(
        _completionNotifId,
        title,
        body,
        const NotificationDetails(android: androidDetails),
      );
    } catch (_) {}
  }
}
