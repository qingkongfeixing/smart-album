# 贡献指南

感谢你的关注！本项目是个人开源作品，欢迎提交 Issue 和 PR。

## 提交 Issue

- 使用清晰的标题描述问题
- 附上复现步骤、预期行为和实际行为
- 如果是功能建议，说明使用场景

## 提交 PR

1. Fork 本仓库
2. 创建功能分支：`git checkout -b feature/xxx`
3. 确保通过 `flutter analyze`（无新增 warning）
4. 提交时写明改动内容和原因
5. 发起 PR 到 `main` 分支

## 代码风格

- 遵循 Dart 官方风格指南
- 不加多余的注释（代码自解释）
- 不引入不必要的抽象

## 本地开发

```bash
flutter pub get
flutter analyze          # 静态检查
flutter build apk --release  # 构建 APK
```
