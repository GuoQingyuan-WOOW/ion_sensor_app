import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 单条采样快照（用于本地记录 + 作为 AI 输入）
///
/// 设计目标：
/// - 结构稳定（方便未来迁移到 Hive / SQLite）
/// - 只保存必要字段（避免 SharedPreferences 过大）
/// - 自动裁剪历史长度
class IonSnapshot {
  final DateTime ts;
  final Map<String, double> concentration; // ion -> C
  final Map<String, String> unit; // ion -> unit
  final Map<String, double> intensity; // ion -> I（可选但这里保留）

  const IonSnapshot({
    required this.ts,
    required this.concentration,
    required this.unit,
    required this.intensity,
  });

  Map<String, dynamic> toJson() => {
    'ts': ts.toIso8601String(),
    'concentration': concentration,
    'unit': unit,
    'intensity': intensity,
  };

  static IonSnapshot fromJson(Map<String, dynamic> j) {
    Map<String, double> _toDoubleMap(dynamic v) {
      if (v is Map) {
        return v.map((k, val) => MapEntry(k.toString(), (val as num).toDouble()));
      }
      return {};
    }

    Map<String, String> _toStringMap(dynamic v) {
      if (v is Map) {
        return v.map((k, val) => MapEntry(k.toString(), val.toString()));
      }
      return {};
    }

    return IonSnapshot(
      ts: DateTime.tryParse(j['ts']?.toString() ?? '') ?? DateTime.now(),
      concentration: _toDoubleMap(j['concentration']),
      unit: _toStringMap(j['unit']),
      intensity: _toDoubleMap(j['intensity']),
    );
  }
}

/// 用 SharedPreferences 做一个“轻量日志”
///
/// 若你未来需要更长历史/更高频采样：建议迁移到 Hive 或 SQLite。
class LocalLogService {
  static const String _kKey = 'ion_history_v1';

  /// 最多保存多少条快照（防止本地存储无限膨胀）
  final int maxItems;

  /// 最小记录间隔（避免每帧都写）
  final Duration minInterval;

  DateTime? _lastWrite;

  LocalLogService({
    this.maxItems = 800,
    this.minInterval = const Duration(seconds: 3),
  });

  Future<void> append(IonSnapshot snap) async {
    final now = DateTime.now();
    if (_lastWrite != null && now.difference(_lastWrite!) < minInterval) return;
    _lastWrite = now;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kKey) ?? <String>[];

    raw.add(jsonEncode(snap.toJson()));

    // 裁剪
    if (raw.length > maxItems) {
      raw.removeRange(0, raw.length - maxItems);
    }

    await prefs.setStringList(_kKey, raw);
  }

  /// 取最近 N 条（按时间从旧到新）
  Future<List<IonSnapshot>> recent(int n) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kKey) ?? <String>[];
    final slice = raw.length <= n ? raw : raw.sublist(raw.length - n);

    final out = <IonSnapshot>[];
    for (final s in slice) {
      try {
        final j = jsonDecode(s) as Map<String, dynamic>;
        out.add(IonSnapshot.fromJson(j));
      } catch (_) {
        // ignore corrupted item
      }
    }
    return out;
  }

  /// 清空历史
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }
}