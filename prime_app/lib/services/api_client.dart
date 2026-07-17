import 'dart:convert';
import 'dart:typed_data';
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

  // ---- Dynamic service management ----

  Future<List<dynamic>> listServices() async {
    final res = await _get('/services');
    return res['services'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> restartService(String serviceName) =>
      _post('/services/$serviceName/restart');

  // ---- Filesystem ----

  Future<Map<String, dynamic>> listDir(String path) => _get('/fs/list', {'path': path});

  Future<Map<String, dynamic>> previewPath(String path) => _get('/fs/preview', {'path': path});

  Future<Map<String, dynamic>> deletePath(String path) => _post('/fs/delete', {'path': path});

  Future<Map<String, dynamic>> movePath(String src, String dst) =>
      _post('/fs/move', {'src': src, 'dst': dst});

  Future<Map<String, dynamic>> renamePath(String path, String newName) =>
      _post('/fs/rename', {'path': path, 'new_name': newName});

  Future<Uint8List> downloadFile(String path) async {
    final uri = _uri('/fs/download', {'path': path});
    try {
      final res = await http.get(uri, headers: _headers).timeout(const Duration(minutes: 5));
      if (res.statusCode != 200) {
        String detail = 'HTTP ${res.statusCode}';
        try {
          detail = (jsonDecode(res.body) as Map<String, dynamic>)['detail'] ?? detail;
        } catch (_) {}
        throw ApiException('Download failed: $detail');
      }
      return res.bodyBytes;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Could not reach the laptop: $e');
    }
  }

  Future<Map<String, dynamic>> uploadFile(String targetDir, String filename, List<int> bytes) async {
    final uri = _uri('/fs/upload');
    try {
      final request = http.MultipartRequest('POST', uri);
      request.headers['X-Auth-Token'] = _token ?? '';
      request.fields['target_dir'] = targetDir;
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
      final streamed = await request.send().timeout(const Duration(minutes: 5));
      final res = await http.Response.fromStream(streamed);
      return _handleResponse(res);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Could not reach the laptop: $e');
    }
  }

  // ---- Packages ----

  Future<Map<String, dynamic>> getInstalledPackages() => _get('/packages/installed');

  Future<Map<String, dynamic>> searchPackages(String query, {int limit = 20}) =>
      _get('/packages/search', {'query': query, 'limit': '$limit'});

  Future<Map<String, dynamic>> installPackage(String package) =>
      _post('/packages/install', {'package': package});

  Future<Map<String, dynamic>> uninstallPackage(String package) =>
      _post('/packages/uninstall', {'package': package});

  Future<Map<String, dynamic>> getPackageJob(String jobId) =>
      _get('/packages/jobs/$jobId');

  // ---- Media / Volume ----

  Future<Map<String, dynamic>> getNowPlaying() => _get('/media/now-playing');

  Future<Map<String, dynamic>> mediaPlayPause() => _post('/media/play-pause');

  Future<Map<String, dynamic>> mediaNext() => _post('/media/next');

  Future<Map<String, dynamic>> mediaPrevious() => _post('/media/previous');

  Future<Map<String, dynamic>> getVolume() => _get('/audio/volume');

  Future<Map<String, dynamic>> setVolume(int level) => _post('/audio/volume', {'level': level});

  Future<Map<String, dynamic>> toggleMute() => _post('/audio/mute-toggle');

  Future<Map<String, dynamic>> getBrightness() => _get('/display/brightness');

  Future<Map<String, dynamic>> setBrightness(int level) => _post('/display/brightness', {'level': level});

  Future<Map<String, dynamic>> getKbdBacklight() => _get('/keyboard/backlight');

  Future<Map<String, dynamic>> setKbdBacklight(int level) => _post('/keyboard/backlight', {'level': level});

  // ---- Network ----

  Future<Map<String, dynamic>> getWifiNetworks() => _get('/network/wifi');

  Future<Map<String, dynamic>> connectWifi(String ssid) => _post('/network/wifi/connect', {'ssid': ssid});

  Future<Map<String, dynamic>> getBluetoothDevices() => _get('/network/bluetooth');

  Future<Map<String, dynamic>> connectBluetooth(String mac) => _post('/network/bluetooth/connect', {'mac': mac});

  Future<Map<String, dynamic>> getWifiRadio() => _get('/network/wifi/power');

  Future<Map<String, dynamic>> setWifiRadio(bool enabled) => _post('/network/wifi/power', {'enabled': enabled});

  Future<Map<String, dynamic>> disconnectWifi() => _post('/network/wifi/disconnect');

  Future<Map<String, dynamic>> getBluetoothRadio() => _get('/network/bluetooth/power');

  Future<Map<String, dynamic>> setBluetoothRadio(bool enabled) => _post('/network/bluetooth/power', {'enabled': enabled});

  Future<Map<String, dynamic>> disconnectBluetooth(String mac) => _post('/network/bluetooth/disconnect', {'mac': mac});

  // ---- Processes ----

  Future<Map<String, dynamic>> getProcesses() => _get('/processes');

  Future<Map<String, dynamic>> killProcess(int pid) => _post('/processes/$pid/kill');

  Future<Map<String, dynamic>> getLockStatus() => _get('/power/lock-status');

  Future<Map<String, dynamic>> unlockScreen(String password) => _post('/power/unlock', {'password': password});

  /// Builds the request for the most recently captured screenshot.
  /// Includes a cache-busting timestamp so repeated captures don't get stuck
  /// showing a cached image.
  ({String url, Map<String, String> headers}) screenshotImageRequest() {
    final url = 'http://$_host:8420/commands/screenshot/image?t=${DateTime.now().millisecondsSinceEpoch}';
    return (url: url, headers: {'X-Auth-Token': _token ?? ''});
  }

  /// Builds the proxied art URL + auth header for a local file:// art path.
  /// Returns null if art shouldn't be proxied (empty, or already a direct http(s) URL).
  ({String url, Map<String, String> headers})? proxiedArtRequest(String? artUrl) {
    if (artUrl == null || artUrl.isEmpty) return null;
    if (!artUrl.startsWith('file://')) return null;
    if (_host == null) return null;
    final url = 'http://$_host:8420/media/art?file_url=${Uri.encodeQueryComponent(artUrl)}';
    return (url: url, headers: {'X-Auth-Token': _token ?? ''});
  }
}
