import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bilibili_glass/providers/video_provider.dart';
import 'package:bilibili_glass/screens/home_screen.dart';
import 'package:bilibili_glass/theme/app_theme.dart';
import 'package:bilibili_glass/managers/jwt_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化JWT管理器（自动获取并缓存）
  await JwtManager.initialize();
  
  runApp(const BiliGlassApp());
}

class BiliGlassApp extends StatelessWidget {
  const BiliGlassApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VideoProvider()..fetchVideos()),
      ],
      child: MaterialApp(
        title: '哔哩',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const HomeScreen(),
      ),
    );
  }
}
