import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  PackageActivityItem({
    required this.id,
    required this.packageName,
    required this.action,
    this.status = PackageActivityStatus.running,
    required this.startedAt,
    this.finishedAt,
    this.errorMessage,
    this.read = false,
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
