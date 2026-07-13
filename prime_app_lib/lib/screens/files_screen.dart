import 'package:flutter/material.dart';
import '../services/api_client.dart';

class FilesScreen extends StatefulWidget {
  final ApiClient apiClient;

  const FilesScreen({super.key, required this.apiClient});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  static const _roots = <String>[
    '~/Projects',
    '~/Downloads',
    '~/.config',
  ];

  final List<String> _pathStack = [];
  List<dynamic> _entries = [];
  bool _loading = false;
  String? _error;

  String? get _currentPath => _pathStack.isEmpty ? null : _pathStack.last;

  Future<void> _openRoot(String root) async {
    _pathStack.clear();
    _pathStack.add(root);
    await _load();
  }

  Future<void> _openDir(String path) async {
    _pathStack.add(path);
    await _load();
  }

  Future<void> _goUp() async {
    if (_pathStack.length <= 1) {
      setState(() {
        _pathStack.clear();
        _entries = [];
      });
      return;
    }
    _pathStack.removeLast();
    await _load();
  }

  Future<void> _load() async {
    if (_currentPath == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.apiClient.listDir(_currentPath!);
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

  Future<void> _showItemActions(Map<String, dynamic> entry) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Details'),
              onTap: () => Navigator.pop(ctx, 'details'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: const Text('Move'),
              onTap: () => Navigator.pop(ctx, 'move'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete (to trash)', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (action == null || !mounted) return;

    switch (action) {
      case 'details':
        await _showDetails(entry);
        break;
      case 'rename':
        await _renameEntry(entry);
        break;
      case 'move':
        await _moveEntry(entry);
        break;
      case 'delete':
        await _deleteEntry(entry);
        break;
    }
  }

  Future<void> _showDetails(Map<String, dynamic> entry) async {
    try {
      final preview = await widget.apiClient.previewPath(entry['path']);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(entry['name']),
          content: Text(
            'Size: ${_formatSize(preview['size_bytes'])}\n'
            'Files: ${preview['file_count']}\n'
            'Path: ${entry['path']}',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _renameEntry(Map<String, dynamic> entry) async {
    final controller = TextEditingController(text: entry['name']);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Rename')),
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

  Future<void> _moveEntry(Map<String, dynamic> entry) async {
    final controller = TextEditingController(text: entry['path']);
    final dest = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Full destination path'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Move')),
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

  Future<void> _deleteEntry(Map<String, dynamic> entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete'),
        content: Text('Move "${entry['name']}" to trash?\n\nRecoverable from ~/.prime-trash on the laptop.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await widget.apiClient.deletePath(entry['path']);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final atRoot = _currentPath == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(atRoot ? 'Files' : _currentPath!.split('/').last),
        leading: atRoot
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goUp),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)))
              : atRoot
                  ? ListView(
                      children: _roots
                          .map((root) => ListTile(
                                leading: const Icon(Icons.folder),
                                title: Text(root),
                                onTap: () => _openRoot(root),
                              ))
                          .toList(),
                    )
                  : ListView.builder(
                      itemCount: _entries.length,
                      itemBuilder: (ctx, i) {
                        final entry = _entries[i] as Map<String, dynamic>;
                        final isDir = entry['type'] == 'dir';
                        return ListTile(
                          leading: Icon(isDir ? Icons.folder : Icons.insert_drive_file),
                          title: Text(entry['name']),
                          subtitle: isDir ? null : Text(_formatSize(entry['size_bytes'])),
                          trailing: IconButton(
                            icon: const Icon(Icons.more_vert),
                            onPressed: () => _showItemActions(entry),
                          ),
                          onTap: isDir ? () => _openDir(entry['path']) : () => _showItemActions(entry),
                        );
                      },
                    ),
    );
  }
}
