import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/photo.dart';
import '../models/database_helper.dart';
import '../services/cloud_enhance.dart';
import '../services/photo_scanner.dart';
import '../widgets/photo_detail.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _db = DatabaseHelper.instance;

  List<Photo> _results = [];
  bool _searching = false;
  String _statusText = '';
  final List<String> _history = [];

  // 多选
  bool _selectMode = false;
  final Set<int> _selectedIds = {};

  // 临时分享
  static const _tempShareDir = '/storage/emulated/0/DCIM/Camera';
  final List<_TempShareEntry> _tempShareCopied = [];
  Timer? _tempShareTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _tempShareTimer?.cancel();
      _tempShareTimer = null;
      _restoreTempSharedFiles();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _focusNode.dispose();
    _tempShareTimer?.cancel();
    _restoreTempSharedFiles(); // 退出时清理临时副本
    super.dispose();
  }

  void _dismissKeyboard() {
    _focusNode.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  Future<void> _doSearch(String query) async {
    if (query.trim().isEmpty) return;
    _exitSelect();
    _dismissKeyboard();
    setState(() {
      _searching = true;
      _statusText = '搜索中...';
      _results = [];
    });

    try {
      final ids = await _db.searchByKeyword(query);
      final photos = await _db.getPhotosByIds(ids);

      if (mounted) {
        setState(() {
          _results = photos;
          _searching = false;
          _statusText = photos.isEmpty ? '未找到匹配的图片' : '';

          if (!_history.contains(query)) {
            _history.insert(0, query);
            if (_history.length > 20) _history.removeLast();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searching = false;
          _statusText = '搜索失败: $e';
        });
      }
    }
  }

  // --- 多选逻辑 ---

  void _toggleSelect(int id) {
    setState(() {
      _selectMode = true;
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _exitSelect() => setState(() { _selectMode = false; _selectedIds.clear(); });

  // --- 分享 ---

  void _shareSelected() {
    if (_selectedIds.isEmpty) return;
    final files = _results
        .where((p) => p.id != null && _selectedIds.contains(p.id))
        .map((p) => XFile(p.path))
        .toList();
    if (files.isNotEmpty) {
      Share.shareXFiles(files);
      _exitSelect();
    }
  }

  // --- 临时分享 ---

  Future<void> _tempShareSelected() async {
    if (_selectedIds.isEmpty) return;

    if (_tempShareTimer != null) {
      _tempShareTimer!.cancel();
      _tempShareTimer = null;
      await _restoreTempSharedFiles();
    }

    final sel = _results.where((p) => p.id != null && _selectedIds.contains(p.id)).toList();
    if (sel.isEmpty) return;

    final camDir = Directory(_tempShareDir);
    if (!await camDir.exists()) {
      await camDir.create(recursive: true);
    }

    int copied = 0;
    for (final photo in sel) {
      try {
        final src = File(photo.path);
        if (!await src.exists()) continue;

        final name = photo.path.split('/').last;
        String destPath = '$_tempShareDir/$name';
        int n = 1;
        while (await File(destPath).exists()) {
          final dot = name.lastIndexOf('.');
          final base = dot > 0 ? name.substring(0, dot) : name;
          final ext = dot > 0 ? name.substring(dot) : '';
          destPath = '$_tempShareDir/${base}_$n$ext';
          n++;
        }

        await File(destPath).writeAsBytes(await src.readAsBytes());
        final uri = await context.read<PhotoScanner>().scanFile(destPath);
        _tempShareCopied.add(_TempShareEntry(destPath, uri));
        copied++;
      } catch (e) {
        debugPrint('[Search] TempShare error for ${photo.id}: $e');
      }
    }

    final durSec = context.read<CloudEnhanceService>().tempShareDurationSec;
    _exitSelect();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已复制 $copied 张图片到 Camera 文件夹，$durSec秒后自动删除'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
    if (copied > 0) {
      _tempShareTimer = Timer(Duration(seconds: durSec), _restoreTempShared);
    }
  }

  Future<void> _restoreTempSharedFiles() async {
    if (_tempShareCopied.isEmpty) return;

    final toDelete = List<_TempShareEntry>.from(_tempShareCopied);
    _tempShareCopied.clear();

    for (final entry in toDelete) {
      try {
        if (entry.uri != null) {
          await context.read<PhotoScanner>().deleteByUri(entry.uri!);
        } else {
          final f = File(entry.path);
          if (await f.exists()) {
            await f.delete();
            context.read<PhotoScanner>().removeFromMediaStore(entry.path);
          }
        }
      } catch (e) {
        debugPrint('[Search] Cleanup error for ${entry.path}: $e');
      }
    }
  }

  void _restoreTempShared() async {
    _tempShareTimer = null;
    await _restoreTempSharedFiles();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('临时分享的图片已自动删除'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // --- 构建 ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _selectMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelect,
              ),
              title: Text('已选 ${_selectedIds.length} 张'),
            )
          : AppBar(title: const Text('搜索图片')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: '逗号/空格=且，句号=或。如"猫，橘。奶龙，黄"',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          setState(() {});
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (v) => _doSearch(v),
              textInputAction: TextInputAction.search,
            ),
          ),
          if (_controller.text.isNotEmpty && !_searching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _doSearch(_controller.text),
                  icon: const Icon(Icons.search),
                  label: const Text('搜索'),
                ),
              ),
            ),
          if (_history.isNotEmpty && _results.isEmpty && !_searching)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _history
                    .take(10)
                    .map((h) => ActionChip(
                          label: Text(h),
                          onPressed: () {
                            _controller.text = h;
                            _doSearch(h);
                          },
                        ))
                    .toList(),
              ),
            ),
          if (_searching)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 8),
                  Text('搜索中...'),
                ],
              ),
            ),
          if (_statusText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_statusText,
                  style: TextStyle(color: Colors.grey[600])),
            ),
          Expanded(
            child: _results.isEmpty && !_searching
                ? const Center(
                    child: Text('输入关键词搜索',
                        style: TextStyle(color: Colors.grey, fontSize: 16)))
                : GridView.builder(
                    padding: const EdgeInsets.all(4),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                    ),
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final photo = _results[index];
                      final isSelected = photo.id != null && _selectedIds.contains(photo.id);
                      return RepaintBoundary(
                        child: GestureDetector(
                          onTap: () {
                            if (_selectMode && photo.id != null) {
                              _toggleSelect(photo.id!);
                            } else {
                              _showPhotoDetail(context, photo, _results);
                            }
                          },
                          onLongPress: () {
                            if (!_selectMode && photo.id != null) {
                              _toggleSelect(photo.id!);
                            }
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Hero(
                                tag: 'search_${photo.path}',
                                child: Image.file(
                                  File(photo.path),
                                  fit: BoxFit.cover,
                                  cacheWidth: 200,
                                  errorBuilder: (_, _, _) => const Center(
                                    child: Icon(Icons.broken_image, color: Colors.grey),
                                  ),
                                ),
                              ),
                              if (_selectMode)
                                Positioned.fill(
                                  child: Container(color: isSelected ? Colors.blue.withValues(alpha: 0.3) : Colors.transparent),
                                ),
                              if (_selectMode)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: isSelected
                                      ? const Icon(Icons.check_circle, color: Colors.blue, size: 24)
                                      : Icon(Icons.circle_outlined, color: Colors.white.withValues(alpha: 0.6), size: 24),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _selectMode ? _buildBottomBar() : null,
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: const Border(top: BorderSide(color: Colors.grey, width: 0.3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: '分享',
              onPressed: _shareSelected,
            ),
            IconButton(
              icon: const Icon(Icons.schedule_send),
              tooltip: '临时分享',
              onPressed: _tempShareSelected,
            ),
          ],
        ),
      ),
    );
  }

  void _showPhotoDetail(BuildContext context, Photo photo, List<Photo> list) {
    _dismissKeyboard();
    final idx = list.indexWhere((p) => p.id == photo.id);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoDetailView(
          photos: list,
          initialIndex: idx >= 0 ? idx : 0,
          onDeleted: () {
            if (photo.id != null) {
              setState(() {
                _results.removeWhere((p) => p.id == photo.id);
              });
            }
          },
        ),
      ),
    ).then((_) => _dismissKeyboard());
  }
}

class _TempShareEntry {
  final String path;
  final String? uri;
  _TempShareEntry(this.path, this.uri);
}
