import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/unity_connection_service.dart';
import 'services/unity_launch_service.dart';
import 'theme/app_theme.dart';
import 'screens/home/home_screen.dart';
import 'screens/live_monitor/live_monitor_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UnityLaunchService()),
        ChangeNotifierProvider(create: (_) => UnityConnectionService()..enableDemoMode()),
      ],
      child: const TelerehabApp(),
    ),
  );
}

class TelerehabApp extends StatelessWidget {
  const TelerehabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Telerehab Dashboard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      initialRoute: '/',
      routes: {
        '/':        (_) => const HomeScreen(),
        '/monitor': (_) => const LiveMonitorScreen(),
      },
    );
  }
}
