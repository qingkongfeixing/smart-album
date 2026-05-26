import 'package:permission_handler/permission_handler.dart';

class PermissionHelper {
  PermissionHelper._();

  /// 请求相册读取权限（Android 13+ 用 READ_MEDIA_IMAGES，低版本用 READ_EXTERNAL_STORAGE）
  static Future<bool> requestStoragePermission() async {
    final photos = await Permission.photos.request();
    if (photos.isGranted) return true;
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  /// 请求管理所有文件权限（删除/移动/复制需要）
  static Future<bool> requestManageStoragePermission() async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    final result = await Permission.manageExternalStorage.request();
    return result.isGranted;
  }

  /// 检查是否有相册读取权限
  static Future<bool> hasStoragePermission() async {
    if (await Permission.photos.isGranted) return true;
    return await Permission.storage.isGranted;
  }
}
