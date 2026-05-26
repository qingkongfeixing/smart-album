import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/cloud_enhance.dart';
import '../services/photo_scanner.dart';
import '../models/database_helper.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _photoCount = 0;
  bool _scanning = false;
  bool _cloudExpanded = false;
  List<String> _allFolders = [];
  int _modelCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _modelCount = context.read<CloudEnhanceService>().models.length;
  }

  Future<void> _loadStats() async {
    final db = DatabaseHelper.instance;
    final photoCount = await db.getPhotoCount();
    final photos = await db.getAllPhotos();
    final folders = <String>{};
    for (final p in photos) {
      folders.add(p.path.substring(0, p.path.lastIndexOf('/')));
    }
    if (mounted) {
      setState(() {
        _photoCount = photoCount;
        _allFolders = folders.toList()..sort();
      });
    }
  }

  Future<void> _scanFromSettings() async {
    setState(() => _scanning = true);
    await context.read<PhotoScanner>().scanPhotos();
    await _loadStats();
    if (mounted) setState(() => _scanning = false);
  }

  void _showExcludedFoldersDialog(CloudEnhanceService cloud) {
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final excludedList =
              _allFolders.where((f) => cloud.isFolderExcluded(f)).toList();
          return AlertDialog(
            title: const Text('排除文件夹'),
            content: SizedBox(
              width: double.maxFinite,
              child: excludedList.isEmpty
                  ? const Text('暂无被排除的文件夹')
                  : ListView(
                      shrinkWrap: true,
                      children: excludedList.map((folder) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _showFolderPathDialog(folder),
                                  child: Text(
                                    folder.split('/').last,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 15),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: IconButton(
                                  icon: const Icon(Icons.settings_backup_restore,
                                      size: 19),
                                  tooltip: '恢复',
                                  padding: EdgeInsets.zero,
                                  onPressed: () async {
                                    await cloud.removeExcludedFolder(folder);
                                    setDialogState(() {});
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('完成'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showFolderPathDialog(String folderPath) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('文件夹路径'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(folderPath.split('/').last,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 8),
            SelectableText(folderPath,
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: folderPath));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('已复制到剪贴板'),
                        duration: Duration(seconds: 1)),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('复制路径'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cloudService = context.watch<CloudEnhanceService>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const _SectionHeader('相册扫描'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _scanning ? null : _scanFromSettings,
                icon: _scanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync),
                label: Text(_scanning ? '扫描中...' : '扫描相册'),
              ),
            ),
          ),
          const _SectionHeader('数据统计'),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('已索引图片'),
            trailing: Text('$_photoCount 张'),
          ),
          InkWell(
            onTap: () => setState(() => _cloudExpanded = !_cloudExpanded),
            child: ListTile(
              leading: Icon(
                Icons.cloud,
                color: cloudService.isEnabled ? Colors.green : Colors.grey,
              ),
              title: const Text('云端解析'),
              subtitle: Text(cloudService.isEnabled
                  ? '已配置 ${cloudService.enabledModels.length} 个模型'
                  : '未配置模型'),
              trailing:
                  Icon(_cloudExpanded ? Icons.expand_less : Icons.expand_more),
            ),
          ),
          if (_cloudExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('说明'),
                    subtitle: Text(
                        '填入 API 配置后，扫描时自动调用云端视觉大模型生成图片描述标签。\n最多配置 5 个模型，批量解析时自动分配并行处理。'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(cloudService.models.length, (i) {
                    return _ModelConfigCard(
                      index: i,
                      model: cloudService.models[i],
                      canRemove: cloudService.models.length > 1,
                      onChanged: () => setState(() {}),
                      onRemove: () async {
                        await cloudService.removeModel(i);
                        setState(() {});
                      },
                    );
                  }),
                  if (cloudService.models.length < CloudEnhanceService.maxModels)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            cloudService.addModel();
                            setState(() {});
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(
                              '添加模型 (${cloudService.models.length}/${CloudEnhanceService.maxModels})'),
                        ),
                      ),
                    ),
                ],
              ),
            ),

          if (_allFolders.isNotEmpty) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.folder_off),
              title: const Text('排除文件夹'),
              subtitle: Text(cloudService.excludedFolders.isEmpty
                  ? '未排除任何文件夹'
                  : '${cloudService.excludedFolders.length} 个文件夹被隐藏'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showExcludedFoldersDialog(cloudService),
            ),
          ],

          const Divider(),
          const _SectionHeader('隐私说明'),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '1. 本软件仅用于为本地图片生成 AI 标签，不收集、不上传任何用户数据。\n\n'
              '2. 云端标签功能依赖用户自行配置的第三方 API（如 OpenAI 等），图片传输仅发生在该 API 调用过程中，与本软件无关。\n\n'
              '3. 云端解析默认关闭，需用户主动开启。\n\n'
              '4. 所有标签和 OCR 文字仅存储在本地数据库，应用完全离线可用。',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个模型配置卡片
class _ModelConfigCard extends StatefulWidget {
  final int index;
  final ModelConfig model;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _ModelConfigCard({
    required this.index,
    required this.model,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_ModelConfigCard> createState() => _ModelConfigCardState();
}

class _ModelConfigCardState extends State<_ModelConfigCard> {
  late TextEditingController _modelNameCtrl;
  late TextEditingController _baseUrlCtrl;
  late TextEditingController _apiKeyCtrl;
  bool _showKey = false;

  @override
  void initState() {
    super.initState();
    _modelNameCtrl = TextEditingController(text: widget.model.modelName);
    _baseUrlCtrl = TextEditingController(text: widget.model.apiBaseUrl);
    _apiKeyCtrl = TextEditingController(text: widget.model.apiKey);
  }

  @override
  void didUpdateWidget(_ModelConfigCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model.modelName != widget.model.modelName &&
        _modelNameCtrl.text != widget.model.modelName) {
      _modelNameCtrl.text = widget.model.modelName;
    }
    if (oldWidget.model.apiBaseUrl != widget.model.apiBaseUrl &&
        _baseUrlCtrl.text != widget.model.apiBaseUrl) {
      _baseUrlCtrl.text = widget.model.apiBaseUrl;
    }
    if (oldWidget.model.apiKey != widget.model.apiKey &&
        _apiKeyCtrl.text != widget.model.apiKey) {
      _apiKeyCtrl.text = widget.model.apiKey;
    }
  }

  @override
  void dispose() {
    _modelNameCtrl.dispose();
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(CloudEnhanceService cloud) async {
    await cloud.setModelName(widget.index, _modelNameCtrl.text);
    await cloud.setApiBaseUrl(widget.index, _baseUrlCtrl.text);
    await cloud.setApiKey(widget.index, _apiKeyCtrl.text);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.read<CloudEnhanceService>();
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.model.isEnabled
                        ? Colors.green.shade50
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.model.isEnabled
                          ? Colors.green.shade300
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.model.isEnabled
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 14,
                        color: widget.model.isEnabled
                            ? Colors.green
                            : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '模型 ${widget.index + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: widget.model.isEnabled
                              ? Colors.green.shade800
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (widget.canRemove)
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: '移除此模型',
                      padding: EdgeInsets.zero,
                      onPressed: widget.onRemove,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _modelNameCtrl,
              decoration: const InputDecoration(
                labelText: '模型名称',
                hintText: 'gpt-4o / claude-3-opus / gemini-2.0-flash',
                prefixIcon: Icon(Icons.model_training, size: 20),
                isDense: true,
              ),
              onChanged: (_) => _save(cloud),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _baseUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'API Base URL',
                hintText: 'https://your-api.com/v1/chat/completions',
                prefixIcon: Icon(Icons.link, size: 20),
                isDense: true,
              ),
              onChanged: (_) => _save(cloud),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _apiKeyCtrl,
              obscureText: !_showKey,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: 'sk-or-v1-...',
                prefixIcon: const Icon(Icons.key, size: 20),
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                    _showKey ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _showKey = !_showKey),
                ),
              ),
              onChanged: (_) => _save(cloud),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
