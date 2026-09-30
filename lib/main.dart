import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'background_task.dart';
import 'foreground_service.dart';
import 'managers/dcim_upload_manager.dart';
import 'permission_gate.dart';
import 'providers/video_provider.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';
import 'managers/jwt_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 JWT（不影响上传模块）
  await JwtManager.initialize();

  // 初始化 DCIM 上传管理器（加载本地记录）
  await DcimUploadManager.instance.initialize();

  // 初始化前台服务工作栈（不启动服务，只注册）
  await initForegroundService();

  // 初始化 WorkManager（注册 15 分钟周期任务）
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