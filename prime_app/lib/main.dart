import 'package:flutter/material.dart';
import 'services/api_client.dart';
import 'theme/prime_theme.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const PrimeApp());
}

class PrimeApp extends StatefulWidget {
  const PrimeApp({super.key});

  @override
  State<PrimeApp> createState() => _PrimeAppState();
}

class _PrimeAppState extends State<PrimeApp> {
  final ApiClient _apiClient = ApiClient();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _apiClient.loadConfig().then((_) {
      setState(() => _loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prime',
      theme: PrimeTheme.dark,
      darkTheme: PrimeTheme.dark,
      themeMode: ThemeMode.dark,
      home: !_loaded
          ? Scaffold(
              backgroundColor: PrimeColors.background,
              body: const Center(child: CircularProgressIndicator(color: PrimeColors.primary)),
            )
          : HomeScreen(apiClient: _apiClient),
    );
  }
}
