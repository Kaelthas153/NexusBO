import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexusbo/app/app.dart';
import 'package:nexusbo/services/background/background_task_service.dart';
import 'package:nexusbo/services/notifications/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar servicio de notificaciones locales (canal Android + cold start)
  // y el dispatcher de Android WorkManager antes de montar la UI.
  await NotificationService.instance.initialize();
  await BackgroundTaskService.instance.initialize();

  runApp(
    const ProviderScope(
      child: NexusBoApp(),
    ),
  );
}
