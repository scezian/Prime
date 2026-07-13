import 'package:flutter/material.dart';
import 'services/api_client.dart';
import 'screens/home_screen.dart';
import 'screens/files_screen.dart';
import 'screens/packages_screen.dart';
import 'screens/settings_screen.dart';

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
  int _selectedIndex = 0;

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: !_loaded
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _MainScaffold(
              apiClient: _apiClient,
              selectedIndex: _selectedIndex,
              onIndexChanged: (i) => setState(() => _selectedIndex = i),
            ),
    );
  }
}

class _MainScaffold extends StatelessWidget {
  final ApiClient apiClient;
  final int selectedIndex;
  final ValueChanged<int> onIndexChanged;

  const _MainScaffold({
    required this.apiClient,
    required this.selectedIndex,
    required this.onIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(apiClient: apiClient),
      FilesScreen(apiClient: apiClient),
      PackagesScreen(apiClient: apiClient),
      SettingsScreen(apiClient: apiClient, onSaved: () => onIndexChanged(0)),
    ];

    return Scaffold(
      body: IndexedStack(index: selectedIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onIndexChanged,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Files'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Packages'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
