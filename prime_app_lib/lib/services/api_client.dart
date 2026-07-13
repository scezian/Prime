import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Thrown when the daemon returns an error response or the request fails.
class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

/// Handles all communication with the Prime daemon running on the laptop.
/// Host + token are persisted locally via SharedPreferences.
class ApiClient {
  static const _hostKey = 'prime_host';
  static const _tokenKey = 'prime_token';

  String? _host;
  String? _token;

  /// Loads saved host/token from local storage. Call once at app startup.
  Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    _host = prefs.getString(_hostKey);
    _token = prefs.getString(_tokenKey);
  }

  Future<void> saveConfig({required String host, required String token}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostKey, host);
    await prefs.setString(_tokenKey, token);
    _host = host;
    _token = token;
  }

  bool get isConfigured => _host != null && _host!.isNotEmpty && _token != null && _token!.isNotEmpty;

  String? get host => _host;
  String? get token => _token;

  Uri _uri(String path, [Map<String, String>? query]) {
    if (_host == null || _host!.isEmpty) {
      throw ApiException('Prime is not configured yet. Set the laptop address in Settings.');
    }
    return Uri.parse('http://$_host:8420$path').replace(queryParameters: query);
  }

  Map<String, String> get _headers => {
        'X-Auth-Token': _token ?? '',
        'Content-Type': 'application/json',
      };

  Future<Map<String, dynamic>> _get(String path, [Map<String, String>? query]) async {
    try {
      final res = await http
          .get(_uri(path, query), headers: _headers)
          .timeout(const Duration(seconds: 15));
      return _handleResponse(res);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Could not reach the laptop: $e');
    }
  }

  Future<Map<String, dynamic>> _post(String path, [Map<String, dynamic>? body]) async {
    try {
      final res = await http
          .post(_uri(path), headers: _headers, body: jsonEncode(body ?? {}))
          .timeout(const Duration(minutes: 12)); // installs can take a while
      return _handleResponse(res);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Could not reach the laptop: $e');
    }
  }

  Map<String, dynamic> _handleResponse(http.Response res) {
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Unexpected response from daemon (HTTP ${res.statusCode})');
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return decoded;
    }

    final detail = decoded['detail'] ?? 'Unknown error';
    throw ApiException('$detail (HTTP ${res.statusCode})');
  }

  // ---- Health / Status ----

  Future<bool> checkHealth() async {
    try {
      final res = await http
          .get(Uri.parse('http://$_host:8420/health'))
          .timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getStatus() => _get('/status');

  // ---- Predefined commands ----

  Future<List<dynamic>> listCommands() async {
    final res = await _get('/commands');
    return res['commands'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> runCommand(String commandId) async {
    final res = await _post('/commands/$commandId/run');
    return res['result'] as Map<String, dynamic>;
  }

  // ---- Filesystem ----

  Future<Map<String, dynamic>> listDir(String path) => _get('/fs/list', {'path': path});

  Future<Map<String, dynamic>> previewPath(String path) => _get('/fs/preview', {'path': path});

  Future<Map<String, dynamic>> deletePath(String path) => _post('/fs/delete', {'path': path});

  Future<Map<String, dynamic>> movePath(String src, String dst) =>
      _post('/fs/move', {'src': src, 'dst': dst});

  Future<Map<String, dynamic>> renamePath(String path, String newName) =>
      _post('/fs/rename', {'path': path, 'new_name': newName});

  // ---- Packages ----

  Future<Map<String, dynamic>> searchPackages(String query, {int limit = 20}) =>
      _get('/packages/search', {'query': query, 'limit': '$limit'});

  Future<Map<String, dynamic>> installPackage(String package) =>
      _post('/packages/install', {'package': package});

  Future<Map<String, dynamic>> uninstallPackage(String package) =>
      _post('/packages/uninstall', {'package': package});
}
