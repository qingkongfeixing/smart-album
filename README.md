# 随搜相册

[![Flutter](https://img.shields.io/badge/Flutter-3.12+-02569B?logo=flutter)](https://flutter.dev)
[![License](https://img.shields.io/badge/license-MIT-green)](./LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android-blue)](https://developer.android.com)

基于 Flutter 的本地相册应用，支持 AI 图片语义搜索。利用云端视觉大模型自动为图片生成描述标签，实现自然语言关键词搜索，让你能用日常词汇快速找到照片。

**当前阶段：云端增强版** — 通过用户自行配置的第三方 API（兼容 OpenAI/Claude 等视觉模型）为图片生成标签，所有数据本地存储。

## 功能

### 相册管理

- **文件夹视图**：自动扫描手机相册，按文件夹分组展示，卡片显示封面、图片数量和已解析进度
- **日期分组**：进入文件夹后照片按日期（天）分组，支持今天/昨天/具体日期标签
- **缩放动画**：点击文件夹以缩放动画进入照片网格，返回时反向缩放退出
- **下拉刷新**：重新扫描相册，检测新增/删除/移动的文件
- **文件移动追踪**：图片移动到其他文件夹后通过文件名+哈希指纹匹配，自动更新路径，无需重新云端解析
- **拖拽日期导航**：照片网格右侧日期滑块，上下拖拽快速跳转到对应日期
- **文件夹隐藏/显示**：隐藏的文件夹不在主页显示，也不参与云端解析
- **系统文件管理器**：进入文件夹后可跳转系统文件管理器查看原文件

### 图片多选 & 操作

- **照片多选**：长按图片进入多选模式，底部栏提供复制/剪切/粘贴/删除/分享/单击云端解析/临时分享
- **全选**：一键选中当前文件夹所有图片
- **文件夹多选**：长按文件夹卡片进入多选，支持批量云端解析、批量隐藏/显示
- **复制/剪切/粘贴**：多选后复制或剪切到剪贴板，可在其他文件夹粘贴（自动处理重名冲突）
- **剪贴板状态**：有复制/剪切内容时 AppBar 显示提示标签和粘贴按钮
- **分享**：多张照片一次性分享到其他应用

### 快速打标签

- 进入文件夹后点击标签按钮，打开全屏打标签页面
- 输入标签文字后，点击图片即可批量写入标签
- 支持连续为多批图片打不同标签

### 搜索

- **复合搜索语法**：逗号/空格表示 AND（且），句号表示 OR（或）
  - 例如 `"猫，橘。奶龙，黄"` → `(猫 AND 橘) OR (奶龙 AND 黄)`
- **同时搜索**标签（tags）和 OCR 文字（ocr_text）字段
- **标签浏览**：未搜索时显示全部标签云，字号按频率缩放，点击标签即可筛选对应照片
- **标签筛选**：标签云上方提供筛选输入框，快速定位想要的标签（默认展示前 100 个高频标签）
- **搜索历史**：最近 20 条搜索记录，点击快速重新搜索

### 照片详情

- **大图浏览**：PageView 左右翻页，InteractiveViewer 支持双指缩放
- **标签悬浮条**：图片底部半透明标签条，Wrap 布局展示所有标签，可展开/收起
- **编辑标签**：右上角编辑按钮，弹窗修改逗号分隔的标签
- **单击云端解析**：对单张图片重新调用云端模型生成标签
- **图片信息**：文件名、尺寸、大小、标签、路径一览
- **删除图片**：确认后从磁盘和数据库中同时删除
- **点击隐藏**：点图片可隐藏/显示顶底栏和标签条，长图/竖图不遮挡

### 临时分享

- 选中照片后选择"临时分享"，将照片复制到 Camera 文件夹
- 可配置自动删除时间（5~300 秒），到时自动清理副本和 MediaStore 记录
- 切后台/退出时自动清理临时副本

### 云端解析

- 兼容 OpenAI Chat Completions 接口的视觉模型（GPT-4V、Claude、Gemini、Qwen-VL 等）
- 最多配置 **5 个模型**并行处理，批量解析时图片轮询分配到各模型
- 可自定义 API Base URL、API Key、模型名称
- 单张图片解析、文件夹批量解析、全量解析
- 已解析的图片支持重新解析（新标签与旧标签合并）

### 隐私

- **本软件仅用于为本地图片生成标签，不收集、不上传任何用户数据**
- 云端标签功能依赖用户**自行配置的第三方 API**，图片传输与该 API 调用有关，与本软件无关
- 所有标签和 OCR 文字仅存储在本地 SQLite，不联网也可使用
- 云端解析默认关闭，需用户主动开启

## 工作原理

```
手机相册 ──扫描──▶ SQLite 本地库 ◀──搜索── 用户输入关键词
                     │
              (需用户主动触发)
                     ▼
            第三方视觉大模型 API ──返回──▶ 标签写入本地
           (用户自行配置的 API Key)
```

1. **扫描** — 通过 Android MediaStore 读取本地图片，去重后写入 SQLite
2. **打标签** — 图片压缩为 JPEG base64，调用用户配置的第三方 API 生成标签（含场景、物体、人物特征、角色名、OCR 文字、主色调）
3. **搜索** — 复合布尔语法搜索 tags + ocr_text 字段，支持标签云浏览快速筛选

## 下载

最新 APK 发布在 [Releases](https://github.com/qingkongfeixing/smart-album/releases) 页面。

## 快速开始

### 环境要求

- Flutter SDK >= 3.12.0
- Android SDK (compileSdk 34+)

### 构建

```bash
git clone https://github.com/qingkongfeixing/smart-album.git
cd smart-album

flutter pub get
flutter build apk --release
# 输出: build/app/outputs/flutter-apk/app-release.apk
```

## 云端 API 配置

在设置页展开"云端解析"，可配置最多 **5 个模型**并行处理：

| 字段 | 说明 | 示例 |
|------|------|------|
| 模型名称 | 视觉模型 ID | `gpt-4o`、`claude-3-opus`、`gemini-2.0-flash` |
| API Base URL | Chat Completions 端点 | `https://api.openai.com/v1/chat/completions` |
| API Key | 服务商 API 密钥 | `sk-...` |

API 要求：兼容 OpenAI Chat Completions，支持 `POST` 请求，图片以 base64 `image_url` 传入。

## 技术栈

| 模块 | 技术 |
|------|------|
| 框架 | Flutter (Dart) + Material 3 |
| 状态管理 | Provider |
| 数据库 | SQLite (sqflite) |
| 图片扫描 | Android MediaStore (Platform Channel) |
| 云端 API | HTTP Client，兼容 OpenAI SDK |
| 通知 | flutter_local_notifications |
| 图片压缩 | flutter_image_compress |
| 分享 | share_plus |
| 权限 | permission_handler |

## 项目结构

```
lib/
├── main.dart                     # 入口，Provider 注入，Material 3 主题（亮/暗）
├── models/
│   ├── photo.dart                # Photo 实体类 + SearchResult
│   └── database_helper.dart      # SQLite 单例，CRUD + 关键词搜索 + 标签聚合
├── services/
│   ├── photo_scanner.dart        # 相册扫描 + 批量/单张云端解析编排 + 文件操作
│   ├── cloud_enhance.dart        # 多模型云端 API（最多5个并行轮询）
│   └── notification_service.dart # 扫描/解析进度通知
├── screens/
│   ├── gallery_screen.dart       # 主页（文件夹网格 → 照片网格 + 日期分组 + 多选/复制/粘贴）
│   ├── search_screen.dart        # 关键词搜索 + 标签云浏览 + 临时分享
│   └── settings_screen.dart      # 云端多模型配置 + 扫描触发 + 排除文件夹管理
├── widgets/
│   └── photo_detail.dart         # 大图查看 + PageView 翻页 + 标签悬浮条 + 编辑/删除
└── utils/
    ├── constants.dart            # 默认配置常量
    └── permissions.dart          # 存储权限处理
```

## 路线图

- **Phase 1（当前）**：云端增强版 — 本地存储 + 可选第三方 API 标签
- **Phase 2（计划中）**：端侧推理 — ONNX Runtime + MobileCLIP，离线语义搜索
- **Phase 3**：OCR 深度融合 — FTS5 全文搜索 + 向量检索混合排序

## License

MIT
