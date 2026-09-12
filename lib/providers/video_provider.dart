/// 视频数据 Provider — 模拟 API 返回，后续替换为真实接口
library;

import 'package:flutter/foundation.dart';
import 'package:bilibili_glass/models/video_model.dart';

class VideoProvider extends ChangeNotifier {
  List<VideoItem> _videos = [];
  bool _loading = false;
  String? _error;

  List<VideoItem> get videos => _videos;
  bool get loading => _loading;
  String? get error => _error;

  /// 从 API 获取视频列表
  /// TODO: 替换为真实 API URL
  Future<void> fetchVideos() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // 等待一下让 UI 显示 loading 状态
      await Future.delayed(const Duration(milliseconds: 300));

      // TODO: 替换为真实 API
      // final response = await http.get(Uri.parse('YOUR_API_URL'));
      // final data = jsonDecode(response.body) as List;
      // _videos = data.map((e) => VideoItem.fromJson(e)).toList();

      // 模拟数据（占位，等 API 接入后替换）
      _videos = _generateMockVideos();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 模拟视频数据（待真实 API 接入后删除）
  List<VideoItem> _generateMockVideos() {
    return List.generate(20, (i) {
      return VideoItem(
        id: 'video_$i',
        title: _mockTitles[i % _mockTitles.length],
        author: _mockAuthors[i % _mockAuthors.length],
        authorAvatar:
            'https://api.dicebear.com/7.x/initials/svg?seed=${_mockAuthors[i % _mockAuthors.length]}',
        coverUrl:
            'https://picsum.photos/400/225?random=${i + 100}',
        duration: Duration(minutes: i ~/ 5 + 1, seconds: (i * 13) % 60),
        playCount: _mockPlayCounts[i % _mockPlayCounts.length],
        danmakuCount: (i + 1) * 128,
        pubDate: DateTime.now().subtract(Duration(hours: i)),
      );
    });
  }

  static const List<String> _mockTitles = [
    '【4K】震撼视觉！宇宙深空延时摄影，看完再也睡不着',
    '挑战24小时只用一杯咖啡，结果...｜硬核生活实验',
    '程序员的一天：从早晨到深夜，代码与Debug的战争',
    '为什么你学不进去？深度解析大脑的注意力机制',
    '用100天从0学会健身，身材变化记录全公开',
    '这个AI工具太强了！自动生成完整网站演示',
    '日本街头美食探店Vlog｜深夜食堂的真实味道',
    '【入门教程】Flutter 液态玻璃动画全攻略',
    '3分钟学会做一个炫酷的动态图表Dashboard',
    '沉浸式体验：暴雨夜的咖啡馆读书时光 ASMR',
    '如何用Rust重写你的Python项目？性能提升10倍',
    '我花了三个月做了一款APP，从设计到上架全流程',
    '【纪录片】深海11000米——马里亚纳海沟探秘',
    '为什么日本便利店的食物那么好吃？幕后揭秘',
    'Linux 命令行高手速成：从新手到运维工程师',
    '【测评】2025年最值得买的5款降噪耳机横评',
    '一个夜晚的东京街头漫步｜4K 45帧 沉浸式',
    '如何设计一套优雅的系统架构？大厂面试真题解析',
    '从零开始搭建自己的NAS：数据存储完全指南',
    '赛博朋克2077 vs 现实东京：霓虹灯夜景对比',
  ];

  static const List<String> _mockAuthors = [
    '科技美学', '老高与小茉', 'Tim的独立实验室', '稚鱼',
    '老师好我叫何同学', '影视飓风', '才疏学浅的才浅', '半佛仙人',
    '李永乐老师', '小Lin说', '安州牧', '盗月社食遇记',
    '硬核的半佛仙人', '木鱼水心', '大史不出家', '罗翔说刑法',
    '蜡笔和小勋', '小西子Vivi', '手工耿', 'Bigger番茄',
  ];

  static const List<int> _mockPlayCounts = [
    1024000, 856000, 3200000, 512000, 1280000,
    640000, 2100000, 480000, 960000, 1800000,
    750000, 1100000, 2400000, 320000, 1600000,
    890000, 3100000, 430000, 1500000, 670000,
  ];
}
