import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/app_settings.dart';
import 'services/exercise_repository.dart';
import 'services/protocol_repository.dart';
import 'services/replay_engine.dart';
import 'services/session_repository.dart';
import 'services/unity_connection_service.dart';
import 'services/unity_launch_service.dart';
import 'theme/app_theme.dart';
import 'screens/exercises/exercise_library_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/live_monitor/live_monitor_screen.dart';
import 'screens/protocol/protocol_builder_screen.dart';
import 'screens/replay/replay_screen.dart';
import 'screens/settings/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = AppSettings();
  await settings.init();

  final repository = SessionRepository()..setRoot(settings.sessionsRoot);

  final protocols = ProtocolRepository()..setRoot(settings.protocolsRoot);

  final exercises = ExerciseRepository()..setRoot(settings.exercisesRoot);

  final connection = UnityConnectionService()
    ..setMocks(
      motion: settings.mockMotion,
      fsr: settings.mockFsr,
      eeg: settings.mockEeg,
    );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: repository),
        ChangeNotifierProvider.value(value: protocols),
        ChangeNotifierProvider.value(value: exercises),
        ChangeNotifierProvider.value(value: connection),
        ChangeNotifierProvider(create: (_) => UnityLaunchService()),
        ChangeNotifierProvider(create: (_) => ReplayEngine()),
      ],
      child: const TelerehabApp(),
    ),
  );
}

class TelerehabApp extends StatelessWidget {
  const TelerehabApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    AppColors.setDark(settings.darkMode);
    return MaterialApp(
      title: 'TeleRehab Dashboard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.current,
      initialRoute: '/',
      routes: {
        '/': (_) => const HomeScreen(),
        '/monitor': (_) => const LiveMonitorScreen(),
        '/protocols': (_) => const ProtocolBuilderScreen(),
        '/exercises': (_) => const ExerciseLibraryScreen(),
        '/replay': (_) => const ReplayScreen(),
        '/settings': (_) => const SettingsScreen(),
      },
    );
  }
}
