import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

enum PackageActivityAction { install, uninstall }

enum PackageActivityStatus { running, success, failed }

class PackageActivityItem {
  final String id;
  final String packageName;
  final PackageActivityAction action;
  PackageActivityStatus status;
  final DateTime startedAt;
  DateTime? finishedAt;
  String? errorMessage;
  bool read;
  int? downloadedBytes;
  int? totalBytes;
  bool isAur;
  int? phaseIndex;
  int? phaseTotal;
  String? phaseLabel;

  PackageActivityItem({
    required this.id,
    required this.packageName,
    required this.action,
    this.status = PackageActivityStatus.running,
    required this.startedAt,
    this.finishedAt,
    this.errorMessage,
    this.read = false,
    this.downloadedBytes,
    this.totalBytes,
    this.isAur = false,
    this.phaseIndex,
    this.phaseTotal,
    this.phaseLabel,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'packageName': packageName,
        'action': action.name,
        'status': status.name,
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'errorMessage': errorMessage,
        'read': read,
        'downloadedBytes': downloadedBytes,
        'totalBytes': totalBytes,
        'isAur': isAur,
        'phaseIndex': phaseIndex,
        'phaseTotal': phaseTotal,
        'phaseLabel': phaseLabel,
      };

  factory PackageActivityItem.fromJson(Map<String, dynamic> json) => PackageActivityItem(
        id: json['id'] as String,
        packageName: json['packageName'] as String,
        action: PackageActivityAction.values.byName(json['action'] as String),
        status: PackageActivityStatus.values.byName(json['status'] as String),
        startedAt: DateTime.parse(json['startedAt'] as String),
        finishedAt: json['finishedAt'] != null ? DateTime.parse(json['finishedAt'] as String) : null,
        errorMessage: json['errorMessage'] as String?,
        read: json['read'] as bool? ?? false,
        downloadedBytes: json['downloadedBytes'] as int?,
        totalBytes: json['totalBytes'] as int?,
        isAur: json['isAur'] as bool? ?? false,
        phaseIndex: json['phaseIndex'] as int?,
        phaseTotal: json['phaseTotal'] as int?,
        phaseLabel: json['phaseLabel'] as String?,
      );
}

/// App-wide log of package install/uninstall activity. Backs the activity
/// icon + panel on the Packages screen. Persisted via shared_preferences so
/// history survives app restarts. A singleton + ChangeNotifier so any
/// screen (the icon badge, the panel itself) can listen for live updates.
class PackageActivityCenter extends ChangeNotifier {
  PackageActivityCenter._internal();
  static final PackageActivityCenter instance = PackageActivityCenter._internal();

  static const _prefsKey = 'prime_package_activity_log';
  static const _maxItems = 100;

  final List<PackageActivityItem> _items = [];
  bool _loaded = false;

  List<PackageActivityItem> get items => List.unmodifiable(_items);
  bool get hasActive => _items.any((i) => i.status == PackageActivityStatus.running);
  int get unreadCount => _items.where((i) => !i.read).length;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        _items.addAll(list.map(PackageActivityItem.fromJson));
        // Anything still "running" from a previous session never got a
        // result — the app was killed mid-operation. Don't leave it
        // spinning forever; mark it unresolved.
        for (final i in _items) {
          if (i.status == PackageActivityStatus.running) {
            i.status = PackageActivityStatus.failed;
            i.errorMessage = 'Interrupted — app closed before this finished';
            i.finishedAt ??= i.startedAt;
          }
        }
      }
    } catch (_) {
      // Corrupt/unreadable data — start fresh rather than crash.
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_items.map((i) => i.toJson()).toList());
    await prefs.setString(_prefsKey, raw);
  }

  /// Starts tracking a new install/uninstall. Returns an id to pass to
  /// [complete] once the daemon responds.
  String start({required String packageName, required PackageActivityAction action}) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _items.insert(
      0,
      PackageActivityItem(id: id, packageName: packageName, action: action, startedAt: DateTime.now()),
    );
    if (_items.length > _maxItems) {
      _items.removeRange(_maxItems, _items.length);
    }
    notifyListeners();
    _persist();
    return id;
  }

  void updateProgress(
    String id, {
    int? downloadedBytes,
    int? totalBytes,
    bool? isAur,
    int? phaseIndex,
    int? phaseTotal,
    String? phaseLabel,
  }) {
    final matches = _items.where((i) => i.id == id);
    if (matches.isEmpty) return;
    final item = matches.first;
    if (downloadedBytes != null) item.downloadedBytes = downloadedBytes;
    if (totalBytes != null) item.totalBytes = totalBytes;
    if (isAur != null) item.isAur = isAur;
    if (phaseIndex != null) item.phaseIndex = phaseIndex;
    if (phaseTotal != null) item.phaseTotal = phaseTotal;
    if (phaseLabel != null) item.phaseLabel = phaseLabel;
    notifyListeners();
    // Deliberately not persisted on every tick — persisted state only
    // needs to know "running" vs finished (for the interrupted-on-restart
    // check above), not live byte counts.
  }

  void complete(String id, {required bool success, String? errorMessage}) {
    final matches = _items.where((i) => i.id == id);
    if (matches.isEmpty) return;
    final item = matches.first;
    item.status = success ? PackageActivityStatus.success : PackageActivityStatus.failed;
    item.finishedAt = DateTime.now();
    item.errorMessage = errorMessage;
    notifyListeners();
    _persist();
  }

  /// Starts an install/uninstall job against the daemon, tracks it as a
  /// new activity item, polls /packages/jobs/{id} until it resolves, and
  /// marks the item success/failed. Centralized here so both the initial
  /// action (packages_screen) and retries (activity screen) share one
  /// implementation instead of duplicating the polling loop.
  ///
  /// Returns the final job status map. Throws if the daemon call itself
  /// fails (network error, bad response) — callers that don't need to
  /// react to that beyond the activity log entry can ignore the error.
  Future<Map<String, dynamic>> run({
    required ApiClient api,
    required String packageName,
    required PackageActivityAction action,
  }) async {
    final id = start(packageName: packageName, action: action);
    try {
      final startResult = action == PackageActivityAction.install
          ? await api.installPackage(packageName)
          : await api.uninstallPackage(packageName);

      final jobId = startResult['job_id'] as String?;
      if (jobId == null) {
        throw Exception('Daemon did not return a job id');
      }

      while (true) {
        await Future.delayed(const Duration(milliseconds: 900));
        final job = await api.getPackageJob(jobId);

        updateProgress(
          id,
          downloadedBytes: (job['downloaded_bytes'] as num?)?.round(),
          totalBytes: (job['total_bytes'] as num?)?.round(),
          isAur: job['is_aur'] as bool?,
          phaseIndex: (job['phase_index'] as num?)?.round(),
          phaseTotal: (job['phase_total'] as num?)?.round(),
          phaseLabel: job['phase_label'] as String?,
        );

        final status = job['status'] as String? ?? 'failed';
        if (status == 'success' || status == 'failed') {
          complete(
            id,
            success: status == 'success',
            errorMessage: status == 'success' ? null : (job['error'] as String? ?? 'Failed'),
          );
          return job;
        }
      }
    } catch (e) {
      complete(id, success: false, errorMessage: e.toString());
      rethrow;
    }
  }

  void markAllRead() {
    for (final i in _items) {
      i.read = true;
    }
    notifyListeners();
    _persist();
  }

  void deleteAll() {
    _items.clear();
    notifyListeners();
    _persist();
  }
}
