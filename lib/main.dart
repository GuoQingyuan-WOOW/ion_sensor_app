import 'package:flutter/material.dart';
import 'pages/ion_dashboard_page.dart';

void main() => runApp(const IonSensorApp());

class IonSensorApp extends StatelessWidget {
  const IonSensorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '饮食检测',
      debugShowCheckedModeBanner: false,

      // ✅ 关键：限制系统/浏览器字体缩放，避免桌面端 textScaleFactor 导致布局挤爆
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final ts = mq.textScaleFactor.clamp(0.95, 1.10); // 你可调范围
        return MediaQuery(
          data: mq.copyWith(textScaleFactor: ts),
          child: child ?? const SizedBox.shrink(),
        );
      },

      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        fontFamilyFallback: const ['Segoe UI', 'PingFang SC', 'Microsoft YaHei'],
      ),
      home: const IonDashboardPage(),
    );
  }
}