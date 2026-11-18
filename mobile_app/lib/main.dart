import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_config.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'services/chat_notifications_service.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Report Flutter framework errors to Firebase Crashlytics.
  FlutterError.onError = (errorDetails) {
    FlutterError.presentError(errorDetails);

    FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
  };

  // Report uncaught asynchronous errors.
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // Native JobService requires this public HTTPS URL while Flutter is closed.
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_base_url', AppConfig.backendBaseUrl);
  } catch (error) {
    debugPrint('Could not initialize native notification URL: $error');
  }

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await ChatNotificationsService.instance.initialize();

  runApp(const WellScreenApp());
}

class WellScreenApp extends StatelessWidget {
  const WellScreenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: ChatNotificationsService.navigatorKey,
      title: 'WellScreen',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const SplashScreen(),
    );
  }
}
