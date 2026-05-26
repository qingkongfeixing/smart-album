# 修改记录

## 2026-05-24

### 1. 排除文件夹"恢复"按钮优化
**文件**: `lib/screens/settings_screen.dart`
- `TextButton("恢复")` → `IconButton(Icons.settings_backup_restore, size: 20)`，添加 tooltip
- `ListTile` → `Row` + `Expanded` 布局，图标固定在右侧 32×32 区域内，消除右侧空白

### 2. 文件移动检测与解析复用
**文件**: `lib/services/photo_scanner.dart`
- 扫描时用 `文件名 + 文件大小` 构建指纹 Map
- 新图片路径不在库中时，尝试指纹匹配已有记录，命中则只更新路径，保留 OCR/云端标签/解析数据，**不重新走云端解析**
- `scanPhotos` 改为全量查询（`incremental: false`），扫描后清理数据库中已不存在的文件记录
- `scanFolder` 保持增量查询，不做清理

### 3. 文件夹多选：批量解析与隐藏
**文件**: `lib/screens/gallery_screen.dart`
- 长按文件夹卡片进入多选模式，显示蓝色选中框
- AppBar 切换为"已选 N 个文件夹"，提供**批量云端解析**和**批量隐藏/显示**按钮
- 返回键/关闭按钮退出多选

### 4. 图片多选 UI 重构
**文件**: `lib/screens/gallery_screen.dart`
- 右上角操作按钮（解析/复制/剪切/删除）移到**底部横条**（`bottomNavigationBar`）
- 右上角改为**全选按钮**（`Icons.select_all`），一键选中当前文件夹全部图片

### 5. 扫描进度条卡死修复
**文件**: `lib/screens/gallery_screen.dart`
- `_silentRefresh` 加入 300ms Timer 节流，不再逐张图片触发全量 DB 查询
- 添加 `dart:async` import，dispose 时取消 timer

### 6. 跳转系统文件管理器
**文件**: 
- `android/.../MainActivity.kt` — 新增 `openFolder` MethodChannel 方法，用 `DocumentsContract.buildDocumentUri` 构建文档 URI 定位到文件夹
- `android/.../AndroidManifest.xml` — 添加 FileProvider 声明
- `android/.../res/xml/file_paths.xml` — 新建 FileProvider 路径配置
- `lib/services/photo_scanner.dart` — 新增 `openFolder(folderPath)` 方法
- `lib/screens/gallery_screen.dart` — 进入文件夹后右上角显示文件夹图标按钮

### 7. 快速打标签
**文件**: `lib/screens/gallery_screen.dart`
- 进入文件夹后右上角新增标签图标按钮（`Icons.local_offer`）
- 打开全屏打标签页（`_QuickTagScreen`）：顶部输入标签文字 → 点击图片选中/取消 → 右上角"确定"按钮批量写入标签
- 写入后清空选中，保持输入框文字可继续给下一批图片打标

### 8. API 配置整合到云端解析
**文件**: `lib/screens/settings_screen.dart`
- "API 配置"独立区块移除，全部整合到"云端解析"可点击折叠面板内
- 点击"云端解析"行展开/收起，带箭头指示，展开后字段顺序：模型名称 → API Base URL → API Key
- 说明文字也一并移入展开区域

### 9. 文件夹进出动画
**文件**: `lib/screens/gallery_screen.dart`
- 点击文件夹时，照片网格从该文件夹所在屏幕位置向四周缩放扩大（350ms, easeOut）
- 配合淡入效果，文件夹网格保持在底层作为"背景"
- 返回时动画反向：照片网格缩小回文件夹位置并淡出

### 10. 扫描进度条满进度修复
**文件**: `lib/services/photo_scanner.dart`
- 设置 `_state = scanning` 的同时把 `_onProgress` 重置为 `ScanProgress(0, 0, '')`，避免沿用上次扫描结束时的满进度值
