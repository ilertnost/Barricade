import 'dart:io' show Platform;
import 'dart:ui' as ui show PlatformDispatcher;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:media_kit/media_kit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'l10n/strings.dart';
import 'services/api_service.dart';
import 'services/ws_service.dart';
import 'services/call_service.dart';
import 'services/fcm_service.dart';
import 'services/theme_controller.dart';
import 'services/locale_controller.dart';
import 'services/quick_reaction_controller.dart';
import 'services/audio_player_service.dart';
import 'services/platform_call_service.dart';
import 'services/mute_service.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';

/// Top-level background FCM handler (runs in a separate isolate).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // When app is killed, just show the native incoming call notification.
  // The WebSocket will reconnect when user opens the app and deliver the offer.
  final data = message.data;
  final type = data['type'];
  if (type == 'call_offer') {
    final callerName = data['caller_name'] ?? '';
    final fromId = data['from_id'] ?? '';
    final channelId = data['channel_id'] ?? '';
    PlatformCallService.showIncomingCall(callerName, fromId, channelId: channelId);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  FlutterError.onError = (details) {
    debugPrint('FLUTTER ERROR: ${details.exception}');
    debugPrint('STACK: ${details.stack}');
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PLATFORM ERROR: $error\n$stack');
    return true;
  };

  if (Platform.isAndroid) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('FIREBASE INIT ERROR: $e');
    }
  }
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.barricade.audio',
    androidNotificationChannelName: 'Воспроизведение',
    androidNotificationOngoing: true,
  );
  if (Platform.isAndroid) {
    try {
      await Permission.notification.request();
    } catch (_) {}
  }
  debugPrint('MAIN: about to runApp');
  runApp(const BarricadeApp());
  debugPrint('MAIN: runApp called');
}

class BarricadeApp extends StatelessWidget {
  const BarricadeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => ThemeController()..load()),
        ChangeNotifierProvider(create: (_) => LocaleController()..load()),
        ChangeNotifierProvider(create: (_) => QuickReactionController()..load()),
        ChangeNotifierProvider(create: (_) => AudioPlayerService()),
        Provider(create: (_) => WsService()),
        ChangeNotifierProvider(create: (ctx) => CallService(ctx.read<WsService>())),
        Provider(create: (ctx) => FcmService(ctx.read<WsService>(), ctx.read<CallService>())),
      ],
      child: Consumer2<ThemeController, LocaleController>(
        builder: (context, themeCtrl, localeCtrl, _) {
          return DynamicColorBuilder(
            builder: (lightDynamic, darkDynamic) {
              ColorScheme lightScheme;
              ColorScheme darkScheme;
              // Follow the device's Material You palette when the user hasn't
              // picked a custom accent and the platform exposes one.
              if (themeCtrl.useSystemAccent && lightDynamic != null && darkDynamic != null) {
                lightScheme = lightDynamic.harmonized();
                darkScheme = darkDynamic.harmonized();
              } else {
                final seed = themeCtrl.seed ?? Colors.indigo;
                lightScheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
                darkScheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
              }
              return MaterialApp(
                title: Strings.t('app.title'),
                debugShowCheckedModeBanner: false,
                locale: localeCtrl.locale,
                supportedLocales: const [Locale('ru'), Locale('en')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                ],
                theme: buildTheme(lightScheme),
                darkTheme: buildTheme(darkScheme),
                themeMode: themeCtrl.mode,
                home: const AuthGate(),
                routes: {
                  '/settings': (_) => const SettingsScreen(),
                },
              );
            },
          );
        },
      ),
    );
  }
}

class AppState extends ChangeNotifier {
  bool _loggedIn = false;
  bool get loggedIn => _loggedIn;
  void setLoggedIn(bool v) { _loggedIn = v; notifyListeners(); }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checking = true;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await MuteService.init();
    if (mounted) _checkAuth();
  }

  Future<void> _checkAuth() async {
    final loggedIn = await ApiService.isLoggedIn();
    if (loggedIn) {
      try {
        await ApiService.getMe();
        if (mounted) context.read<AppState>().setLoggedIn(true);
      } catch (_) {}
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Consumer<AppState>(
      builder: (_, state, __) {
        if (state.loggedIn) {
          if (!_initialized) {
            _initialized = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              context.read<WsService>().connect();
              final fcm = context.read<FcmService>();
              await FcmService.init();
              fcm.setupListeners();
              final token = await fcm.getToken();
              if (token != null) fcm.registerToken(token);
            });
          }
          return const HomeScreen();
        }
        return LoginScreen(onLogin: () => state.setLoggedIn(true));
      },
    );
  }
}
