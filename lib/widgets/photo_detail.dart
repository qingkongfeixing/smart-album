import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/photo.dart';
import '../models/database_helper.dart';
import '../services/cloud_enhance.dart';

class PhotoDetailView extends StatefulWidget {
  final List<Photo> photos;
  final int initialIndex;
  final VoidCallback? onDeleted;
  const PhotoDetailView({
    super.key,
    required this.photos,
    required this.initialIndex,
    this.onDeleted,
  });

  @override
  State<PhotoDetailView> createState() => _PhotoDetailViewState();
}

class _PhotoDetailViewState extends State<PhotoDetailView> {
  bool _barsVisible = true;
  int _fileSize = 0;
  late PageController _pageCtrl;
  late int _currentIndex;
  final TransformationController _transformCtrl = TransformationController();
  bool _isZoomed = false;
  bool _cloudLoading = false;

  Photo get _currentPhoto => widget.photos[_currentIndex];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
    _transformCtrl.addListener(_onTransformChanged);
    _loadFileSize();
  }

  void _onTransformChanged() {
    final zoomed = _transformCtrl.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _isZoomed) setState(() => _isZoomed = zoomed);
  }

  void _loadFileSize() async {
    try {
      final size = await File(_currentPhoto.path).length();
      if (mounted) setState(() => _fileSize = size);
    } catch (_) {}
  }

  void _toggleBars() => setState(() => _barsVisible = !_barsVisible);

  Future<void> _share() async {
    final file = XFile(_currentPhoto.path);
    await Share.shareXFiles([file], subject: '分享图片');
  }

  void _showEditSheet() {
    final tagsCtrl = TextEditingController(text: _currentPhoto.tags ?? '');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('编辑标签'),
        content: TextField(
          controller: tagsCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '标签逗号分隔，如：海滩, 日落, 猫咪',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await DatabaseHelper.instance.updatePhoto(
                _currentPhoto.copyWith(
                  tags: tagsCtrl.text.isEmpty ? null : tagsCtrl.text,
                ),
              );
              if (mounted) {
                setState(() {
                  widget.photos[_currentIndex] = _currentPhoto.copyWith(
                    tags: tagsCtrl.text.isEmpty ? null : tagsCtrl.text,
                  );
                });
                Navigator.pop(context);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _cloudAnalyze() async {
    final cloudService = context.read<CloudEnhanceService>();
    if (!cloudService.isEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中启用云端解析')),
      );
      return;
    }

    final photoPath = _currentPhoto.path;
    final photoId = _currentPhoto.id;
    final existingTags = _currentPhoto.tags ?? '';
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _cloudLoading = true);
    try {
      final result = await cloudService.analyzeImage(photoPath);
      final cloudTags = result['tags'] ?? '';
      final merged = [
        if (existingTags.isNotEmpty) existingTags,
        if (cloudTags.isNotEmpty) cloudTags,
      ].join(', ');

      if (photoId != null) {
        await DatabaseHelper.instance.updatePhoto(
          _currentPhoto.copyWith(tags: merged),
        );
      }

      if (!mounted) return;
      setState(() {
        _cloudLoading = false;
        widget.photos[_currentIndex] = _currentPhoto.copyWith(tags: merged);
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('云端解析完成')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _cloudLoading = false);
      final errMsg = e.toString().replaceFirst(RegExp(r'^Exception: '), '');
      messenger.showSnackBar(
        SnackBar(content: Text('解析失败：$errMsg')),
      );
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('将删除这张图片，此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final file = File(_currentPhoto.path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
    if (_currentPhoto.id != null) {
      await DatabaseHelper.instance.deletePhoto(_currentPhoto.id!);
    }
    widget.onDeleted?.call();
    if (mounted) Navigator.pop(context);
  }

  bool _tagExpanded = false;

  Widget _buildTagStrip(bool isDark) {
    final tagsStr = _currentPhoto.tags;
    final tags = tagsStr != null
        ? tagsStr.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
        : <String>[];
    final hasTags = tags.isNotEmpty;

    final bg = isDark ? Colors.white12 : Colors.black54;
    final fg = isDark ? Colors.white : Colors.white;

    if (!hasTags) {
      return Positioned(
        left: 0, right: 0, bottom: 0,
        child: AnimatedOpacity(
          opacity: _barsVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: GestureDetector(
            onTap: _showEditSheet,
            child: Container(
              color: bg,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('无标签', style: TextStyle(fontSize: 12, color: fg.withAlpha(180))),
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: 14, color: fg.withAlpha(180)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: AnimatedOpacity(
        opacity: _barsVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          color: bg,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          constraints: _tagExpanded
              ? const BoxConstraints(maxHeight: 220)
              : const BoxConstraints(maxHeight: 74),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final t in tags)
                  Chip(
                    label: Text(t, style: TextStyle(fontSize: 12, color: fg)),
                    backgroundColor: Colors.white.withAlpha(30),
                    side: BorderSide.none,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                // 展开/收起箭头
                ActionChip(
                  label: Icon(
                    _tagExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 16,
                    color: fg.withAlpha(200),
                  ),
                  backgroundColor: Colors.transparent,
                  side: BorderSide.none,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  labelPadding: EdgeInsets.zero,
                  onPressed: () => setState(() => _tagExpanded = !_tagExpanded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showInfo() {
    final name = _currentPhoto.path.split('/').last;
    final sizeKB = _fileSize > 0 ? '${(_fileSize / 1024).toStringAsFixed(1)} KB' : '计算中...';

    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('图片信息'),
        children: [
          _infoRow('名称', name),
          _infoRow('尺寸', '${_currentPhoto.width} x ${_currentPhoto.height}'),
          _infoRow('大小', sizeKB),
          _infoRow('标签', _currentPhoto.tags?.isNotEmpty == true ? _currentPhoto.tags! : '无'),
          _infoRow('路径', _currentPhoto.path),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text('$label:', style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.black : Colors.white;
    final barBg = isDark ? Colors.black87 : Colors.white.withAlpha(230);
    final fg = isDark ? Colors.white : Colors.black87;
    final fgDim = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: bg,
      appBar: _barsVisible
          ? AppBar(
              backgroundColor: barBg,
              leading: IconButton(
                icon: Icon(Icons.arrow_back, color: fg),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                '${_currentIndex + 1}/${widget.photos.length}',
                style: TextStyle(color: fgDim, fontSize: 16),
              ),
              actions: [
                IconButton(
                  icon: Icon(Icons.edit, color: fg),
                  tooltip: '编辑标签',
                  onPressed: _showEditSheet,
                ),
                IconButton(
                  icon: Icon(Icons.info_outline, color: fg),
                  onPressed: _showInfo,
                ),
              ],
            )
          : null,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: _toggleBars,
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: widget.photos.length,
              onPageChanged: (i) {
                _transformCtrl.value = Matrix4.identity();
                setState(() {
                  _currentIndex = i;
                  _fileSize = 0;
                  _isZoomed = false;
                  _tagExpanded = false;
                });
                _loadFileSize();
              },
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  transformationController: _transformCtrl,
                  panEnabled: _isZoomed,
                  child: Hero(
                    tag: 'img_${widget.photos[index].path}',
                    child: Image.file(
                      File(widget.photos[index].path),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.broken_image,
                        color: isDark ? Colors.grey : Colors.grey.shade400,
                        size: 48,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_barsVisible) _buildTagStrip(isDark),
        ],
      ),
      bottomNavigationBar: _barsVisible
          ? BottomAppBar(
              color: barBg,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    icon: Icon(Icons.share, color: fg),
                    tooltip: '分享',
                    onPressed: _share,
                  ),
                  IconButton(
                    icon: _cloudLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: fg,
                            ),
                          )
                        : Icon(Icons.cloud_upload, color: fg),
                    tooltip: '云端解析',
                    onPressed: _cloudLoading ? null : _cloudAnalyze,
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: fgDim),
                    tooltip: '删除',
                    onPressed: _delete,
                  ),
                ],
              ),
            )
          : null,
    );
  }

  @override
  void dispose() {
    _transformCtrl.removeListener(_onTransformChanged);
    _transformCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }
}
