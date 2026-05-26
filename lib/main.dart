import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'services/cloud_enhance.dart';
import 'services/photo_scanner.dart';
import 'services/notification_service.dart';
import 'models/database_helper.dart';
import 'screens/gallery_screen.dart';
import 'utils/permissions.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appDir = await getApplicationDocumentsDirectory();
  await DatabaseHelper.instance.init(appDir.path);
  await NotificationService().init();

  // 启动时请求相册权限
  await PermissionHelper.requestStoragePermission();

  final cloudService = CloudEnhanceService();
  await cloudService.loadSettings();
  final scanner = PhotoScanner(cloudService);

  runApp(
    MultiProvider(
      providers: [
        Provider<PhotoScanner>.value(value: scanner),
        Provider<CloudEnhanceService>.value(value: cloudService),
      ],
      child: const SmartAlbumApp(),
    ),
  );
}

class SmartAlbumApp extends StatelessWidget {
  const SmartAlbumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '随搜相册',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          backgroundColor: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const GalleryScreen(),
    );
  }
}
