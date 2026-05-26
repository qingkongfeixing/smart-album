/// 应用全局常量配置
class AppConstants {
  AppConstants._();

  // ── 云端API配置 ──────────────────────────────────────────
  static const String cloudApiBaseUrl = '';
  static const String cloudApiKey = '';
  static const String cloudModel = '';

  // ── 数据库配置 ──────────────────────────────────────────
  static const String dbName = 'smart_album.db';
  static const int dbVersion = 1;

  // ── 搜索配置 ────────────────────────────────────────────
  static const int defaultTopK = 50;
}
