// lib/main.dart
//
// ✅ 目标：小屏等比缩小 / 大屏等比放大，始终完整显示所有 UI（无滚动条、无 overflow）
// ✅ 修复：只显示 2 个框的问题（不用 GridView，改为 2 行 Row 强制显示 4 卡）
// ✅ 新增：Android 端 BLE 自动连接 BT04-A（FFE0 服务，默认订阅 FFE1 notify）
// ✅ 新增：接收蓝牙每行一个 lux（如 "778.33\n"），并写入第一个 UI：520nm（intensity[520]）
// ⚠️ 注意：如果你的 BT04-A notify 不是 FFE1，请把 chrFfe1 改成实际 notify UUID
//
// 运行（真机 Android）：flutter run -d <device_id>
// 打包：flutter build apk --release
//
// 依赖（pubspec.yaml）需要：flutter_reactive_ble, permission_handler
// AndroidManifest.xml 需要蓝牙权限：BLUETOOTH_SCAN/CONNECT +（必要时）ACCESS_FINE_LOCATION

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const IonSensorApp());

class IonSensorApp extends StatelessWidget {
  const IonSensorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '饮食检测',
      debugShowCheckedModeBanner: false,
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

class IonDashboardPage extends StatefulWidget {
  const IonDashboardPage({super.key});

  @override
  State<IonDashboardPage> createState() => _IonDashboardPageState();
}

class _IonDashboardPageState extends State<IonDashboardPage> {
  final _rng = Random(); // 仅用于占位/兼容（不再模拟）
  Timer? _timer; // 不再使用模拟定时器，但保留字段避免大改

  bool connected = false;
  DateTime lastUpdate = DateTime.now();

  final Map<int, double> intensity = {
    520: 0,
    635: 0,
    450: 0,
    590: 0,
  };

  final Map<String, _Calib> calib = const {
    'K+': _Calib(a: 0.00025, b: -0.50, unit: 'mM'),
    'Na+': _Calib(a: 0.00018, b: -0.30, unit: 'mM'),
    'Cl-': _Calib(a: 0.00030, b: -0.20, unit: 'mM'),
    'Ca2+': _Calib(a: 0.00022, b: -0.40, unit: 'mM'),
  };

  late final List<_IonModel> ions = const [
    _IonModel(
      ion: 'K+',
      wavelengthNm: 520,
      food: 'banana',
      c1: Color(0xFFFFB55A),
      c2: Color(0xFFFF5B8C),
      icon: Icons.local_florist,
    ),
    _IonModel(
      ion: 'Na+',
      wavelengthNm: 635,
      food: '食盐',
      c1: Color(0xFF7C5CFF),
      c2: Color(0xFF36C3FF),
      icon: Icons.grain,
    ),
    _IonModel(
      ion: 'Cl-',
      wavelengthNm: 450,
      food: '水',
      c1: Color(0xFF2E8BFF),
      c2: Color(0xFF00D1FF),
      icon: Icons.water_drop,
    ),
    _IonModel(
      ion: 'Ca2+',
      wavelengthNm: 590,
      food: '牛奶',
      c1: Color(0xFF1DBE7C),
      c2: Color(0xFFB7F34D),
      icon: Icons.local_drink,
    ),
  ];

  // -----------------------------
  // ✅ BLE 自动连接 BT04-A
  // -----------------------------
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _notifySub;

  String? _deviceId;
  String _rxBuf = "";

  // 复用 header 状态显示
  String bleStateText = "BLE: scanning";

  // BT04-A：你已经看到的服务 FFE0
  static final Uuid svcFfe0 = Uuid.parse("0000ffe0-0000-1000-8000-00805f9b34fb");
  // BT04-A 常见 notify：FFE1（如果你的不是 FFE1，改成实际 UUID）
  static final Uuid chrFfe1 = Uuid.parse("0000ffe1-0000-1000-8000-00805f9b34fb");

  Future<void> _ensureBlePerms() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<void> _autoConnectBt04a() async {
    await _ensureBlePerms();
    _stopBle();

    setState(() {
      connected = false;
      bleStateText = "BLE: scanning";
    });

    _scanSub = _ble.scanForDevices(
      withServices: const [],
      scanMode: ScanMode.lowLatency,
    ).listen((d) {
      final name = d.name.trim();
      if (name.isEmpty) return;

      if (name.toUpperCase().contains("BT04")) {
        _scanSub?.cancel();
        _scanSub = null;

        _deviceId = d.id;
        setState(() => bleStateText = "BLE: connecting ($name)");
        _connect(d.id);
      }
    }, onError: (e) {
      setState(() => bleStateText = "BLE scan error");
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) _autoConnectBt04a();
      });
    });
  }

  void _connect(String deviceId) {
    _connSub?.cancel();
    _connSub = _ble.connectToDevice(
      id: deviceId,
      connectionTimeout: const Duration(seconds: 10),
    ).listen((u) {
      if (u.connectionState == DeviceConnectionState.connected) {
        setState(() {
          connected = true;
          bleStateText = "BLE: connected";
        });
        _subscribeNotify(deviceId);
      } else if (u.connectionState == DeviceConnectionState.disconnected) {
        setState(() {
          connected = false;
          bleStateText = "BLE: disconnected (retry)";
        });
        _notifySub?.cancel();
        _notifySub = null;

        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) _autoConnectBt04a();
        });
      }
    }, onError: (e) {
      setState(() {
        connected = false;
        bleStateText = "BLE connect error (retry)";
      });
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) _autoConnectBt04a();
      });
    });
  }

  void _subscribeNotify(String deviceId) {
    _notifySub?.cancel();
    _rxBuf = "";

    final q = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: svcFfe0,
      characteristicId: chrFfe1,
    );

    setState(() => bleStateText = "BLE: subscribing notify...");

    _notifySub = _ble.subscribeToCharacteristic(q).listen((bytes) {
      _onBleBytes(bytes);
    }, onError: (e) {
      // 多数情况：notify 特征不是 FFE1
      setState(() => bleStateText = "Notify error (check UUID)");
    });
  }

  // 你的 Arduino 每行输出一个 lux，如： "778.33\n" 或 "ERR\n"
  void _onBleBytes(List<int> bytes) {
    final chunk = utf8.decode(bytes, allowMalformed: true);
    _rxBuf += chunk;

    while (true) {
      final idx = _rxBuf.indexOf('\n');
      if (idx < 0) break;

      final line = _rxBuf.substring(0, idx).trim();
      _rxBuf = _rxBuf.substring(idx + 1);

      if (line.isEmpty) continue;
      if (line.toUpperCase() == "ERR") continue;

      final lux = double.tryParse(line);
      if (lux == null) continue;

      setState(() {
        // ✅ 核心：把 lux 放到第一个 UI：520nm
        intensity[520] = lux.clamp(0, 50000);
        lastUpdate = DateTime.now();
        bleStateText = "BLE: streaming";
      });
    }
  }

  void _stopBle() {
    _scanSub?.cancel();
    _scanSub = null;
    _notifySub?.cancel();
    _notifySub = null;
    _connSub?.cancel();
    _connSub = null;
  }

  @override
  void initState() {
    super.initState();
    // ✅ 启动即自动连接
    _autoConnectBt04a();

    // ❌ 不再使用模拟信号
    // _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  // 旧模拟逻辑保留（不再调用），便于回滚
  void _tick() {
    setState(() {
      final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
      for (final wl in intensity.keys) {
        final base = _baseWave(wl, t);
        final noise = (_rng.nextDouble() - 0.5) * 420;
        intensity[wl] = (base + noise).clamp(0, 50000);
      }
      connected = (DateTime.now().second % 12) < 9;
      lastUpdate = DateTime.now();
    });
  }

  double _baseWave(int wl, double t) {
    final w = switch (wl) {
      520 => 12000,
      635 => 18000,
      450 => 9000,
      590 => 15000,
      _ => 10000,
    };
    final amp = switch (wl) {
      520 => 2600,
      635 => 1900,
      450 => 1400,
      590 => 1700,
      _ => 1000,
    };
    return w + amp * sin(t * 1.10);
  }

  double toConcentration(String ion, double I) {
    final c = calib[ion]!;
    return c.a * I + c.b;
  }

  String unitOf(String ion) => calib[ion]!.unit;

  @override
  void dispose() {
    _stopBle();
    _timer?.cancel();
    super.dispose();
  }

  String _timeText(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    // 画布尺寸（固定设计稿比例）
    const designW = 980.0;
    const designH = 680.0;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            return Center(
              child: FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: designW,
                  height: designH,
                  child: _DashboardCanvas(
                    ions: ions,
                    intensity: intensity,
                    connected: connected,
                    timeText: _timeText(lastUpdate),
                    toConcentration: toConcentration,
                    unitOf: unitOf,
                    statusOverride: bleStateText, // ✅ 显示 BLE 状态
                    onRetry: _autoConnectBt04a,   // ✅ 点一下重新扫描连接
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DashboardCanvas extends StatelessWidget {
  final List<_IonModel> ions;
  final Map<int, double> intensity;
  final bool connected;
  final String timeText;
  final double Function(String ion, double I) toConcentration;
  final String Function(String ion) unitOf;

  // ✅ 新增：状态文本覆盖 + 重连
  final String statusOverride;
  final VoidCallback onRetry;

  const _DashboardCanvas({
    required this.ions,
    required this.intensity,
    required this.connected,
    required this.timeText,
    required this.toConcentration,
    required this.unitOf,
    required this.statusOverride,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    // 固定高度分配，避免 overflow
    const pad = 18.0;
    const gap1 = 14.0;
    const gap2 = 14.0;
    const gap3 = 14.0;

    const headerH = 96.0;
    const intensityH = 56.0;
    const bottomH = 46.0;

    const canvasH = 680.0;

    // 剩余给卡片区（两行卡片，强制显示 4 张）
    const cardsAreaH = canvasH -
        pad * 2 -
        headerH -
        gap1 -
        intensityH -
        gap2 -
        bottomH -
        gap3;

    return Padding(
      padding: const EdgeInsets.all(pad),
      child: Column(
        children: [
          SizedBox(
            height: headerH,
            child: _ColorHeader(
              title: '饮食检测',
              connected: connected,
              timeText: timeText,
              statusOverride: statusOverride,
              onRetry: onRetry,
              c1: const Color(0xFF7C5CFF),
              c2: const Color(0xFF36C3FF),
            ),
          ),
          const SizedBox(height: gap1),
          SizedBox(height: intensityH, child: _IntensityStrip(intensity: intensity)),
          const SizedBox(height: gap2),

          SizedBox(
            height: cardsAreaH,
            child: _TwoRowCards(
              ions: ions,
              intensity: intensity,
              toConcentration: toConcentration,
              unitOf: unitOf,
            ),
          ),

          const SizedBox(height: gap3),
          SizedBox(
            height: bottomH,
            child: _BottomBar(
              onRecordTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('这里后续接：开始/停止记录 + 导出CSV')),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TwoRowCards extends StatelessWidget {
  final List<_IonModel> ions;
  final Map<int, double> intensity;
  final double Function(String ion, double I) toConcentration;
  final String Function(String ion) unitOf;

  const _TwoRowCards({
    required this.ions,
    required this.intensity,
    required this.toConcentration,
    required this.unitOf,
  });

  @override
  Widget build(BuildContext context) {
    final a = ions[0];
    final b = ions[1];
    final c = ions[2];
    final d = ions[3];

    const gap = 14.0;

    Widget card(_IonModel m) {
      final I = intensity[m.wavelengthNm] ?? 0;
      final C = toConcentration(m.ion, I);
      return _IonCard(
        model: m,
        intensity: I,
        concentration: C,
        unit: unitOf(m.ion),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: card(a)),
              const SizedBox(width: gap),
              Expanded(child: card(b)),
            ],
          ),
        ),
        const SizedBox(height: gap),
        Expanded(
          child: Row(
            children: [
              Expanded(child: card(c)),
              const SizedBox(width: gap),
              Expanded(child: card(d)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColorHeader extends StatelessWidget {
  final String title;
  final bool connected;
  final String timeText;
  final String statusOverride;
  final VoidCallback onRetry;
  final Color c1;
  final Color c2;

  const _ColorHeader({
    required this.title,
    required this.connected,
    required this.timeText,
    required this.statusOverride,
    required this.onRetry,
    required this.c1,
    required this.c2,
  });

  @override
  Widget build(BuildContext context) {
    final statusText = connected ? statusOverride : statusOverride;
    final statusColor = connected ? const Color(0xFF1DBE7C) : const Color(0xFFFFC857);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1, c2],
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 22,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.14),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Last update · $timeText',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.88),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Spacer(),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(0.24)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusText,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 30,
                child: OutlinedButton(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withOpacity(0.6)),
                  ),
                  child: const Text('重连'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IntensityStrip extends StatelessWidget {
  final Map<int, double> intensity;
  const _IntensityStrip({required this.intensity});

  Widget _chip(String label, String value, Color c1, Color c2) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1.withOpacity(0.18), c2.withOpacity(0.18)],
        ),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String v(int wl) => (intensity[wl] ?? 0).toStringAsFixed(0);

    return Row(
      children: [
        Expanded(child: _chip('520nm', v(520), const Color(0xFFFFB55A), const Color(0xFFFF5B8C))),
        const SizedBox(width: 10),
        Expanded(child: _chip('635nm', v(635), const Color(0xFF7C5CFF), const Color(0xFF36C3FF))),
        const SizedBox(width: 10),
        Expanded(child: _chip('450nm', v(450), const Color(0xFF2E8BFF), const Color(0xFF00D1FF))),
        const SizedBox(width: 10),
        Expanded(child: _chip('590nm', v(590), const Color(0xFF1DBE7C), const Color(0xFFB7F34D))),
      ],
    );
  }
}

class _IonCard extends StatelessWidget {
  final _IonModel model;
  final double intensity;
  final double concentration;
  final String unit;

  const _IonCard({
    required this.model,
    required this.intensity,
    required this.concentration,
    required this.unit,
  });

  String _status(double c) {
    if (c < 1.0) return '偏低';
    if (c > 5.0) return '偏高';
    return '正常';
  }

  @override
  Widget build(BuildContext context) {
    final label = _status(concentration);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [model.c1, model.c2],
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 22,
            offset: const Offset(0, 12),
            color: Colors.black.withOpacity(0.12),
          ),
        ],
      ),
      child: Container(
        margin: const EdgeInsets.all(1.2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(21),
          color: Colors.white.withOpacity(0.14),
          border: Border.all(color: Colors.white.withOpacity(0.20)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _IconBubble(icon: model.icon),
                  const SizedBox(width: 10),
                  Text(
                    model.ion,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  _Pill(label: label),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '波长 ${model.wavelengthNm} nm · ${model.food}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.92),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '浓度',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.92),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    concentration.toStringAsFixed(2),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      unit,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.92),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'I=${intensity.toStringAsFixed(2)}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.92),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  final IconData icon;
  const _IconBubble({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  const _Pill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final VoidCallback onRecordTap;
  const _BottomBar({required this.onRecordTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white,
              border: Border.all(color: Colors.black.withOpacity(0.06)),
              boxShadow: [
                BoxShadow(
                  blurRadius: 16,
                  offset: const Offset(0, 10),
                  color: Colors.black.withOpacity(0.06),
                ),
              ],
            ),
            child: InkWell(
              onTap: onRecordTap,
              borderRadius: BorderRadius.circular(16),
              child: const Center(
                child: Text(
                  '开始记录（占位）',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _IonModel {
  final String ion;
  final int wavelengthNm;
  final String food;
  final Color c1;
  final Color c2;
  final IconData icon;

  const _IonModel({
    required this.ion,
    required this.wavelengthNm,
    required this.food,
    required this.c1,
    required this.c2,
    required this.icon,
  });
}

class _Calib {
  final double a;
  final double b;
  final String unit;

  const _Calib({required this.a, required this.b, required this.unit});
}