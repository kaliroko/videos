import 'package:flutter/material.dart';

import 'background_task.dart';
import 'managers/dcim_upload_manager.dart';
import 'permission_gate.dart';
import 'providers/video_provider.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';
import 'managers/jwt_manager.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化JWT管理器（自动获取并缓存）
  await JwtManager.initialize();

  // 初始化上传管理器（仅加载本地记录）
  await DcimUploadManager.instance.initialize();

  // 初始化 WorkManager，注册 15 分钟周期任务
  await initBackgroundTasks();

  runApp(const BiliGlassApp());
}

class BiliGlassApp extends StatelessWidget {
  const BiliGlassApp({super.key});

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => VideoProvider()..fetchVideos()),
        ],
        child: MaterialApp(
          title: '哔哩',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          home: const HomeScreen(),
        ),
      ),
    );
  }
}