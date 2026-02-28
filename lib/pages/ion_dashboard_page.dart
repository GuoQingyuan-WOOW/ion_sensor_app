import 'dart:async';

import 'package:flutter/material.dart';
import '../models/calib.dart';
import '../models/ion_model.dart';
import '../services/ble_service.dart';
import '../services/local_log_service.dart';
import '../ui/dashboard_canvas.dart';

class IonDashboardPage extends StatefulWidget {
  const IonDashboardPage({super.key});

  @override
  State<IonDashboardPage> createState() => _IonDashboardPageState();
}

class _IonDashboardPageState extends State<IonDashboardPage> {
  final LocalLogService _log = LocalLogService();

  // UI state
  bool connected = false;
  DateTime lastUpdate = DateTime.now();
  String bleStateText = "BLE: scanning";

  /// ✅ intensity 用 ion 名作为 key（避免 510nm 冲突：Cl- 与 Mg2+ 都是 510nm）
  final Map<String, double> intensity = {
    'K+': 0,
    'Na+': 0,
    'Cl-': 0,
    'Ca2+': 0,
    'Mg2+': 0,
  };

  /// ✅ 校准参数（示例占位：你可后续按实验改）
  final Map<String, Calib> calib = const {
    'K+': Calib(a: 0.00025, b: -0.50, unit: 'mM'),
    'Na+': Calib(a: 0.00018, b: -0.30, unit: 'mM'),
    'Cl-': Calib(a: 0.00030, b: -0.20, unit: 'mM'),
    'Ca2+': Calib(a: 0.00022, b: -0.40, unit: 'mM'),
    'Mg2+': Calib(a: 0.00020, b: -0.35, unit: 'mM'),
  };

  /// ✅ 重点修复：IonModel 里字段名是 c1/c2（Color），不是 colorA/colorB（int）
  late final List<IonModel> ions = const [
    IonModel(
      ion: 'K+',
      wavelengthNm: 405,
      food: '熏食',
      c1: Color(0xFF7C5CFF),
      c2: Color(0xFF36C3FF),
      icon: Icons.local_fire_department,
    ),
    IonModel(
      ion: 'Na+',
      wavelengthNm: 520,
      food: '海鲜',
      c1: Color(0xFFFF5C93),
      c2: Color(0xFFFFC857),
      icon: Icons.set_meal,
    ),
    IonModel(
      ion: 'Cl-',
      wavelengthNm: 510,
      food: '坚果',
      c1: Color(0xFF00C9A7),
      c2: Color(0xFF92FE9D),
      icon: Icons.park,
    ),
    IonModel(
      ion: 'Ca2+',
      wavelengthNm: 575,
      food: '土豆',
      c1: Color(0xFFFF8A00),
      c2: Color(0xFFFFD200),
      icon: Icons.emoji_food_beverage,
    ),
    IonModel(
      ion: 'Mg2+',
      wavelengthNm: 510,
      food: '绿叶菜',
      c1: Color(0xFF4FACFE),
      c2: Color(0xFF00F2FE),
      icon: Icons.grass,
    ),
  ];

  // BLE
  late final Bt04aBleService _bleSvc;
  StreamSubscription<bool>? _connSub;
  StreamSubscription<String>? _statusSub;
  StreamSubscription<double>? _luxSub;

  @override
  void initState() {
    super.initState();

    _bleSvc = Bt04aBleService();

    _connSub = _bleSvc.connectedStream.listen((v) {
      if (!mounted) return;
      setState(() => connected = v);
    });

    _statusSub = _bleSvc.statusStream.listen((s) {
      if (!mounted) return;
      setState(() => bleStateText = s);
    });

    _luxSub = _bleSvc.luxStream.listen((lux) {
      if (!mounted) return;
      setState(() {
        /// ⚠️ 你目前 BLE 只有一个通道的 lux
        /// 这里先把它写到 K+（演示用），其他离子保持 0
        intensity['K+'] = lux;
        lastUpdate = DateTime.now();
      });

      // ✅ 本地记录一条快照（用于后续 AI 建议 + 你的数据分析）
      final conc = <String, double>{};
      final unit = <String, String>{};
      final inten = <String, double>{};
      for (final m in ions) {
        final I = intensity[m.ion] ?? 0;
        conc[m.ion] = toConcentration(m.ion, I);
        unit[m.ion] = unitOf(m.ion);
        inten[m.ion] = I;
      }

      _log.append(IonSnapshot(
        ts: DateTime.now(),
        concentration: conc,
        unit: unit,
        intensity: inten,
      ));
    });

    _bleSvc.startAutoConnect();
  }

  double toConcentration(String ion, double I) {
    final c = calib[ion]!;
    return c.a * I + c.b;
  }

  String unitOf(String ion) => calib[ion]!.unit;

  String _timeText(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';

  Future<void> _retry() async {
    await _bleSvc.startAutoConnect();
  }

  @override
  void dispose() {
    _luxSub?.cancel();
    _connSub?.cancel();
    _statusSub?.cancel();
    _bleSvc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: DashboardCanvas(
          ions: ions,
          intensity: intensity,
          connected: connected,
          timeText: _timeText(lastUpdate),
          toConcentration: toConcentration,
          unitOf: unitOf,
          statusOverride: bleStateText,
          onRetry: _retry,
          logService: _log,
        ),
      ),
    );
  }
}