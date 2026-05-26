import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/photo.dart';
import '../models/database_helper.dart';
import '../widgets/photo_detail.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _db = DatabaseHelper.instance;

  List<Photo> _results = [];
  bool _searching = false;
  String _statusText = '';
  final List<String> _history = [];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    _focusNode.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  Future<void> _doSearch(String query) async {
    if (query.trim().isEmpty) return;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索图片')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: '多个关键词用空格或逗号分隔，如"海滩 美食"、"猫，狗"',
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
                      return RepaintBoundary(
                        child: GestureDetector(
                          onTap: () => _showPhotoDetail(context, photo, _results),
                          child: Hero(
                            tag: 'img_${photo.path}',
                            child: Image.file(
                              File(photo.path),
                              fit: BoxFit.cover,
                              cacheWidth: 200,
                              errorBuilder: (_, _, _) => const Center(
                                child: Icon(Icons.broken_image, color: Colors.grey),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
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
