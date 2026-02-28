import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ion_model.dart';
import '../services/local_log_service.dart';
import '../services/api_key_store.dart';
import '../services/ai_advice_service.dart';
import 'ion_card.dart';

class DashboardCanvas extends StatelessWidget {
  final List<IonModel> ions;
  final Map<String, double> intensity;

  final bool connected;
  final String timeText;
  final double Function(String ion, double I) toConcentration;
  final String Function(String ion) unitOf;

  final LocalLogService logService;

  final String statusOverride;
  final VoidCallback onRetry;

  const DashboardCanvas({
    super.key,
    required this.ions,
    required this.intensity,
    required this.connected,
    required this.timeText,
    required this.toConcentration,
    required this.unitOf,
    required this.logService,
    required this.statusOverride,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;

      final cols = w >= 980 ? 3 : 2;

      final scale = (w / 390.0).clamp(0.85, 1.35);
      final pad = (16.0 * scale).clamp(14.0, 22.0);
      final gap = (12.0 * scale).clamp(10.0, 16.0);

      final headerH = (96.0 * scale).clamp(78.0, 124.0);
      final bottomH = (52.0 * scale).clamp(44.0, 76.0);
      final gapTop = (12.0 * scale).clamp(10.0, 16.0);
      final gapBottom = (12.0 * scale).clamp(10.0, 16.0);

      final usableH = h - pad * 2;
      final gridH =
      (usableH - headerH - bottomH - gapTop - gapBottom).clamp(0.0, double.infinity);

      const totalTiles = 6;
      final rows = (totalTiles / cols).ceil();

      final usableW = w - pad * 2;
      final tileW = (usableW - gap * (cols - 1)) / cols;
      final tileH = (gridH - gap * (rows - 1)) / rows;

      final aspect = (tileW / tileH).isFinite && tileH > 0 ? (tileW / tileH) : 1.0;

      final tiles = <Widget>[];
      for (final m in ions) {
        final I = intensity[m.ion] ?? 0;
        final C = toConcentration(m.ion, I);
        tiles.add(
          IonCard(
            model: m,
            intensity: I,
            concentration: C,
            unit: unitOf(m.ion),
          ),
        );
      }

      tiles.add(
        _AdviceCard(
          ions: ions,
          intensity: intensity,
          toConcentration: toConcentration,
          unitOf: unitOf,
          logService: logService,
        ),
      );

      return Padding(
        padding: EdgeInsets.all(pad),
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
            SizedBox(height: gapTop),
            Expanded(
              child: GridView.count(
                crossAxisCount: cols,
                mainAxisSpacing: gap,
                crossAxisSpacing: gap,
                childAspectRatio: aspect,
                physics: const NeverScrollableScrollPhysics(),
                children: tiles.take(totalTiles).toList(),
              ),
            ),
            SizedBox(height: gapBottom),
            SizedBox(height: bottomH, child: _BottomHint(scale: scale)),
          ],
        ),
      );
    });
  }
}

class _AdviceCard extends StatefulWidget {
  final List<IonModel> ions;
  final Map<String, double> intensity;
  final double Function(String ion, double I) toConcentration;
  final String Function(String ion) unitOf;
  final LocalLogService logService;

  const _AdviceCard({
    required this.ions,
    required this.intensity,
    required this.toConcentration,
    required this.unitOf,
    required this.logService,
  });

  @override
  State<_AdviceCard> createState() => _AdviceCardState();
}

class _AdviceCardState extends State<_AdviceCard> {
  static const _kUserInfoKey = 'ai_user_info_v1';

  final ApiKeyStore _keyStore = ApiKeyStore();

  bool _loading = false;
  String? _err;
  AiAdviceResult? _result;

  // 用户信息表单（固定字段，用户只需关注这部分）
  final TextEditingController _diet = TextEditingController();
  final TextEditingController _water = TextEditingController();
  final TextEditingController _activity = TextEditingController();
  final TextEditingController _symptoms = TextEditingController();
  final TextEditingController _avoid = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  @override
  void dispose() {
    _diet.dispose();
    _water.dispose();
    _activity.dispose();
    _symptoms.dispose();
    _avoid.dispose();
    super.dispose();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kUserInfoKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        _diet.text = (j['diet'] ?? '').toString();
        _water.text = (j['water_liters'] ?? '').toString();
        _activity.text = (j['activity'] ?? '').toString();
        _symptoms.text = (j['symptoms'] ?? '').toString();
        _avoid.text = (j['avoid'] ?? '').toString();
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _saveUserInfo(Map<String, String> info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserInfoKey, jsonEncode(info));
  }

  Map<String, String> _collectUserInfo() {
    final m = <String, String>{
      'diet': _diet.text.trim(),
      'water_liters': _water.text.trim(),
      'activity': _activity.text.trim(),
      'symptoms': _symptoms.text.trim(),
      'avoid': _avoid.text.trim(),
    };
    // 清掉空字段
    m.removeWhere((k, v) => v.trim().isEmpty);
    return m;
  }

  IonSnapshot _currentSnapshot() {
    final conc = <String, double>{};
    final unit = <String, String>{};
    final inten = <String, double>{};

    for (final m in widget.ions) {
      final I = widget.intensity[m.ion] ?? 0;
      final C = widget.toConcentration(m.ion, I);
      conc[m.ion] = C;
      unit[m.ion] = widget.unitOf(m.ion);
      inten[m.ion] = I;
    }

    return IonSnapshot(
      ts: DateTime.now(),
      concentration: conc,
      unit: unit,
      intensity: inten,
    );
  }

  Future<String> _requireApiKey() async {
    final key = await _keyStore.readOpenAiKey();
    if (key == null || key.trim().isEmpty) {
      throw Exception('未设置 API Key（点右上角钥匙设置）');
    }
    return key.trim();
  }

  Future<void> _runQuickAdvice() async {
    setState(() {
      _loading = true;
      _err = null;
    });

    try {
      final key = await _requireApiKey();

      final latest = _currentSnapshot();
      final history = await widget.logService.recent(60);
      final merged = [...history, latest];

      final svc = AiAdviceService(apiKey: key);
      final r = await svc.generateQuickAdvice(latest: latest, history: merged);

      if (!mounted) return;
      setState(() => _result = r);
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _runAdviceWithUserInfo(Map<String, String> userInfo) async {
    setState(() {
      _loading = true;
      _err = null;
    });

    try {
      final key = await _requireApiKey();

      final latest = _currentSnapshot();
      final history = await widget.logService.recent(60);
      final merged = [...history, latest];

      final svc = AiAdviceService(apiKey: key);
      final r = await svc.generateAdviceWithUserInfo(
        latest: latest,
        history: merged,
        userInfo: userInfo,
      );

      if (!mounted) return;
      setState(() => _result = r);
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _showKeyDialog() async {
    final ctl = TextEditingController();
    final saved = await _keyStore.readOpenAiKey();
    if (saved != null) ctl.text = saved;

    if (!mounted) return;

    final res = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('设置 OpenAI API Key'),
          content: TextField(
            controller: ctl,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: 'sk-...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, '__CLEAR__'), child: const Text('清除')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('保存')),
          ],
        );
      },
    );

    if (res == null) return;

    if (res == '__CLEAR__') {
      await _keyStore.clearOpenAiKey();
      if (!mounted) return;
      setState(() {
        _result = null;
        _err = null;
      });
      return;
    }

    if (res.trim().isNotEmpty) {
      await _keyStore.writeOpenAiKey(res.trim());
      if (!mounted) return;
      setState(() {});
    }
  }

  /// 📝 填写后建议：先填表单 → 只预览“用户填写信息” → 可修改 → 确认发送
  Future<void> _flowFillPreviewSend() async {
    // Step 1: 填写表单
    final ok = await _showUserFormDialog();
    if (ok != true) return;

    // Step 2: 预览（只显示用户填写信息）
    final info = _collectUserInfo();
    await _saveUserInfo(info);

    final confirmedInfo = await _showPreviewDialogOnlyUserInfo(info);
    if (confirmedInfo == null) return;

    await _saveUserInfo(confirmedInfo);
    await _runAdviceWithUserInfo(confirmedInfo);
  }

  Future<bool?> _showUserFormDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('填写补充信息'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                _field(_diet, '饮食情况', hint: '例如：午饭吃了米饭+鸡胸肉+蔬菜'),
                const SizedBox(height: 10),
                _field(_water, '饮水量(L)', hint: '例如：1.5', keyboard: TextInputType.number),
                const SizedBox(height: 10),
                _field(_activity, '运动/活动', hint: '例如：走路8000步/跑步20分钟'),
                const SizedBox(height: 10),
                _field(_symptoms, '不适/症状', hint: '例如：无/头晕/乏力/腹泻等'),
                const SizedBox(height: 10),
                _field(_avoid, '偏好/忌口/补剂', hint: '例如：低盐/不吃海鲜/有补镁补钾'),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('下一步')),
          ],
        );
      },
    );
  }

  /// ✅ 只预览“用户填写信息”，不展示离子浓度
  Future<Map<String, String>?> _showPreviewDialogOnlyUserInfo(Map<String, String> info) async {
    // 用可编辑控件承接“是否要修改”
    final cDiet = TextEditingController(text: info['diet'] ?? '');
    final cWater = TextEditingController(text: info['water_liters'] ?? '');
    final cActivity = TextEditingController(text: info['activity'] ?? '');
    final cSymptoms = TextEditingController(text: info['symptoms'] ?? '');
    final cAvoid = TextEditingController(text: info['avoid'] ?? '');

    final res = await showDialog<Map<String, String>?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('发送给AI的用户信息（可修改）'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                Text(
                  '下面这些内容会发送给 AI（仅包含你填写的部分）。\n如需修改，请直接在这里改完再确认。',
                  style: TextStyle(color: Colors.black.withOpacity(0.65), fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                _field(cDiet, '饮食情况'),
                const SizedBox(height: 10),
                _field(cWater, '饮水量(L)', keyboard: TextInputType.number),
                const SizedBox(height: 10),
                _field(cActivity, '运动/活动'),
                const SizedBox(height: 10),
                _field(cSymptoms, '不适/症状'),
                const SizedBox(height: 10),
                _field(cAvoid, '偏好/忌口/补剂'),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('返回')),
            FilledButton(
              onPressed: () {
                final m = <String, String>{
                  'diet': cDiet.text.trim(),
                  'water_liters': cWater.text.trim(),
                  'activity': cActivity.text.trim(),
                  'symptoms': cSymptoms.text.trim(),
                  'avoid': cAvoid.text.trim(),
                }..removeWhere((k, v) => v.trim().isEmpty);

                Navigator.pop(ctx, m);
              },
              child: const Text('确认发送'),
            ),
          ],
        );
      },
    );

    cDiet.dispose();
    cWater.dispose();
    cActivity.dispose();
    cSymptoms.dispose();
    cAvoid.dispose();

    return res;
  }

  Widget _field(
      TextEditingController ctl,
      String label, {
        String? hint,
        TextInputType keyboard = TextInputType.text,
      }) {
    return TextField(
      controller: ctl,
      keyboardType: keyboard,
      minLines: 1,
      maxLines: 3,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        isDense: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = _err != null
        ? '⚠ 生成失败：$_err\n\n你可以：\n• 检查 key 是否有效\n• 检查网络\n• 稍后重试'
        : (_result != null ? _result!.toDisplayText() : '• 你可以选择“快速建议”（不填写）或“填写后建议”（先填再确认发送）。');

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white,
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.06),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('建议', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const Spacer(),
                IconButton(
                  tooltip: '设置 API Key',
                  onPressed: _showKeyDialog,
                  icon: const Icon(Icons.key_rounded),
                ),
              ],
            ),

            // ✅ 两个模式按钮
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _runQuickAdvice,
                    icon: const Icon(Icons.flash_on_rounded),
                    label: const Text('快速建议'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _flowFillPreviewSend,
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('填写后建议'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, height: 1.35),
                ),
              ),
            ),

            if (_loading) ...[
              const SizedBox(height: 10),
              Row(
                children: const [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('AI 生成中…', style: TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ],
          ],
        ),
      ),
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
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 6),
                Text('Last update · $timeText',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white.withOpacity(0.9))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(statusOverride,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Colors.white)),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
                  onPressed: onRetry,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomHint extends StatelessWidget {
  final double scale;
  const _BottomHint({required this.scale});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Colors.black.withOpacity(0.55)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '提示：快速建议无需填写；填写后建议会先展示“将发送给AI的用户信息”（仅你填写的部分）供你确认/修改。',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Colors.black.withOpacity(0.65),
              ),
            ),
          ),
        ],
      ),
    );
  }
}