import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_client.dart';
import '../theme/prime_theme.dart';

class FilesScreen extends StatefulWidget {
  final ApiClient apiClient;

  const FilesScreen({super.key, required this.apiClient});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  static const _roots = <String>['~/Projects', '~/Downloads', '~/.config'];

  String _currentRoot = _roots.first;
  String _currentPath = _roots.first;
  List<dynamic> _entries = [];
  bool _loading = false;
  String? _error;
  String? _actionFile;
  bool _transferBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _atRoot => _currentPath == _currentRoot;

  Future<void> _switchRoot(String root) async {
    setState(() {
      _currentRoot = root;
      _currentPath = root;
      _actionFile = null;
    });
    await _load();
  }

  Future<void> _openDir(String path) async {
    setState(() {
      _currentPath = path;
      _actionFile = null;
    });
    await _load();
  }

  Future<void> _goUp() async {
    final parts = _currentPath.split('/');
    if (parts.length <= 1) return;
    parts.removeLast();
    setState(() {
      _currentPath = parts.join('/');
      _actionFile = null;
    });
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.apiClient.listDir(_currentPath);
      setState(() {
        _entries = res['entries'] as List<dynamic>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _delete(Map<String, dynamic> entry) async {
    setState(() => _actionFile = null);
    try {
      await widget.apiClient.deletePath(entry['path']);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Moved "${entry['name']}" to trash')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _rename(Map<String, dynamic> entry) async {
    setState(() => _actionFile = null);
    final controller = TextEditingController(text: entry['name']);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rename', style: PrimeTheme.mono(fontSize: 15)),
        content: TextField(controller: controller, autofocus: true, style: PrimeTheme.mono(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrimeColors.primary, foregroundColor: PrimeColors.primaryForeground),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (newName == null || newName.trim().isEmpty || !mounted) return;
    try {
      await widget.apiClient.renamePath(entry['path'], newName.trim());
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _move(Map<String, dynamic> entry) async {
    setState(() => _actionFile = null);
    final controller = TextEditingController(text: entry['path']);
    final dest = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Move to', style: PrimeTheme.mono(fontSize: 15)),
        content: TextField(controller: controller, autofocus: true, style: PrimeTheme.mono(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrimeColors.primary, foregroundColor: PrimeColors.primaryForeground),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Move'),
          ),
        ],
      ),
    );
    if (dest == null || dest.trim().isEmpty || !mounted) return;
    try {
      await widget.apiClient.movePath(entry['path'], dest.trim());
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _uploadFromPhone() async {
    final result = await FilePicker.pickFiles(withData: true);
    if (result == null || result.files.isEmpty || !mounted) return;

    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not read the picked file')));
      return;
    }

    setState(() => _transferBusy = true);
    try {
      final res = await widget.apiClient.uploadFile(_currentPath, picked.name, bytes);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uploaded to ${res['saved_to']}')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _transferBusy = false);
    }
  }

  Future<void> _downloadToPhone(Map<String, dynamic> entry) async {
    setState(() {
      _actionFile = null;
      _transferBusy = true;
    });
    try {
      final bytes = await widget.apiClient.downloadFile(entry['path']);
      final dir = await getExternalStorageDirectory();
      if (dir == null) throw Exception('No storage directory available on this device');

      final destFile = File('${dir.path}/${entry['name']}');
      await destFile.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to ${destFile.path}')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _transferBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pathParts = _currentPath.replaceFirst('~/', '~').split('/');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Files'),
        actions: [
          if (_transferBusy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: PrimeColors.primary),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.upload_outlined, size: 19),
              onPressed: _uploadFromPhone,
              tooltip: 'Upload from phone',
            ),
        ],
      ),
      body: Column(
        children: [
          // Root pill tabs
          Row(
            children: _roots.map((root) {
              final label = root.replaceFirst('~/', '');
              final active = _currentRoot == root;
              return Expanded(
                child: InkWell(
                  onTap: () => _switchRoot(root),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: active ? PrimeColors.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        label,
                        style: PrimeTheme.mono(
                          fontSize: 10,
                          letterSpacing: 1.5,
                          color: active ? PrimeColors.primary : PrimeColors.mutedForeground,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const Divider(height: 1),
          // Breadcrumb
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                if (!_atRoot)
                  InkWell(
                    onTap: _goUp,
                    child: const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.chevron_left, size: 16, color: PrimeColors.mutedForeground),
                    ),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      for (int i = 0; i < pathParts.length; i++) ...[
                        if (i > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Icon(Icons.chevron_right, size: 9, color: PrimeColors.mutedForeground.withValues(alpha: 0.5)),
                          ),
                        Flexible(
                          child: Text(
                            pathParts[i],
                            overflow: TextOverflow.ellipsis,
                            style: PrimeTheme.mono(
                              fontSize: 10,
                              color: i == pathParts.length - 1 ? PrimeColors.foreground : PrimeColors.mutedForeground,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_loading) const Expanded(child: Center(child: CircularProgressIndicator(color: PrimeColors.primary))),
          if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, style: PrimeTheme.mono(color: PrimeColors.destructive, fontSize: 12)),
                ),
              ),
            ),
          if (!_loading && _error == null)
            Expanded(
              child: _entries.isEmpty
                  ? Center(
                      child: Text('empty directory', style: PrimeTheme.mono(color: PrimeColors.mutedForeground, fontSize: 12)),
                    )
                  : ListView.builder(
                      itemCount: _entries.length,
                      itemBuilder: (ctx, i) {
                        final entry = _entries[i] as Map<String, dynamic>;
                        final isDir = entry['type'] == 'dir';
                        final isActioning = _actionFile == entry['name'];

                        return Column(
                          children: [
                            InkWell(
                              onTap: () {
                                if (isActioning) {
                                  setState(() => _actionFile = null);
                                } else if (isDir) {
                                  _openDir(entry['path']);
                                } else {
                                  setState(() => _actionFile = entry['name']);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: const BoxDecoration(
                                  border: Border(bottom: BorderSide(color: PrimeColors.border)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
                                      size: 14,
                                      color: isDir ? PrimeColors.primary : PrimeColors.mutedForeground,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        entry['name'],
                                        overflow: TextOverflow.ellipsis,
                                        style: PrimeTheme.mono(fontSize: 13),
                                      ),
                                    ),
                                    if (!isDir && entry['size_bytes'] != null)
                                      Text(
                                        _formatSize(entry['size_bytes']),
                                        style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.mutedForeground),
                                      ),
                                    if (isDir)
                                      const Icon(Icons.chevron_right, size: 12, color: PrimeColors.mutedForeground),
                                  ],
                                ),
                              ),
                            ),
                            if (isActioning)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                color: PrimeColors.secondary.withValues(alpha: 0.6),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: [
                                            _ActionChip(
                                              icon: Icons.delete_outline,
                                              label: 'trash',
                                              color: PrimeColors.destructive,
                                              onTap: () => _delete(entry),
                                            ),
                                            if (entry['type'] != 'dir')
                                              _ActionChip(
                                                icon: Icons.download_outlined,
                                                label: 'save',
                                                color: PrimeColors.primary,
                                                onTap: () => _downloadToPhone(entry),
                                              ),
                                            _ActionChip(
                                              icon: Icons.drive_file_move_outline,
                                              label: 'move',
                                              color: PrimeColors.mutedForeground,
                                              onTap: () => _move(entry),
                                            ),
                                            _ActionChip(
                                              icon: Icons.edit_outlined,
                                              label: 'rename',
                                              color: PrimeColors.mutedForeground,
                                              onTap: () => _rename(entry),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () => setState(() => _actionFile = null),
                                      child: const Padding(
                                        padding: EdgeInsets.only(left: 8),
                                        child: Icon(Icons.close, size: 13, color: PrimeColors.mutedForeground),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
            Text(label, style: PrimeTheme.mono(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }
}
