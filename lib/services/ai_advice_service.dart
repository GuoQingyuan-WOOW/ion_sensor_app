import 'dart:convert';
import 'package:http/http.dart' as http;

import 'local_log_service.dart';

class AiAdviceResult {
  final List<String> advice;
  final List<String> risks;
  final String disclaimer;
  final String rawText;

  const AiAdviceResult({
    required this.advice,
    required this.risks,
    required this.disclaimer,
    required this.rawText,
  });

  String toDisplayText() {
    final sb = StringBuffer();
    if (advice.isNotEmpty) {
      sb.writeln('A) 饮食/生活方式建议：');
      for (final a in advice) sb.writeln('• $a');
      sb.writeln();
    }
    if (risks.isNotEmpty) {
      sb.writeln('B) 风险提示：');
      for (final r in risks) sb.writeln('⚠ $r');
      sb.writeln();
    }
    sb.writeln('免责声明：${disclaimer.trim().isEmpty ? "此建议仅供参考，不能替代医生诊断。" : disclaimer.trim()}');
    return sb.toString().trim();
  }
}

class AiAdviceService {
  final String apiKey;
  final String model;
  final Uri endpoint;

  AiAdviceService({
    required this.apiKey,
    this.model = 'gpt-4o-mini',
    Uri? endpoint,
  }) : endpoint = endpoint ?? Uri.parse('https://api.openai.com/v1/responses');

  /// 快速建议：只用采集数据（latest + history）
  Future<AiAdviceResult> generateQuickAdvice({
    required IonSnapshot latest,
    required List<IonSnapshot> history,
  }) {
    return _generateAdviceCore(latest: latest, history: history, userInfo: null);
  }

  /// 填写后建议：采集数据 + 用户补充信息
  Future<AiAdviceResult> generateAdviceWithUserInfo({
    required IonSnapshot latest,
    required List<IonSnapshot> history,
    required Map<String, String> userInfo,
  }) {
    return _generateAdviceCore(latest: latest, history: history, userInfo: userInfo);
  }

  Future<AiAdviceResult> _generateAdviceCore({
    required IonSnapshot latest,
    required List<IonSnapshot> history,
    Map<String, String>? userInfo,
  }) async {
    final hist = history
        .map((e) => {
      'ts': e.ts.toIso8601String(),
      'concentration': e.concentration,
      'unit': e.unit,
    })
        .toList();

    final payload = <String, dynamic>{
      'latest': {
        'ts': latest.ts.toIso8601String(),
        'concentration': latest.concentration,
        'unit': latest.unit,
        'intensity': latest.intensity,
      },
      'history': hist,
      if (userInfo != null && userInfo.isNotEmpty) 'user_info': userInfo,
    };

    // ✅ 重点：输出固定 JSON，且如果 user_info 提供了，必须引用其中至少 2 个细节
    final instructions = [
      '你是一位“饮食与风险提示助手”。请基于用户的离子检测数据生成建议。',
      '你必须只输出 JSON，不能输出任何其他文字。',
      '',
      '输出 JSON 结构：',
      '{',
      '  "advice": [string, ...],',
      '  "risks": [string, ...],',
      '  "disclaimer": "此建议仅供参考，不能替代医生诊断。"',
      '}',
      '',
      '规则：',
      '1) advice 输出 3-6 条，risks 输出 1-2 条；具体、可执行，中文。',
      '2) 如果数据明显不合理（例如大量负值、长期为0、波动异常），必须在 risks 明确提示“可能标定/传感器/数据异常，需要复核”。',
      '3) 如果提供了 user_info（用户填写信息），你必须在 advice/risks 中明确引用至少 2 个 user_info 细节并据此调整建议。',
      '4) 不要诊断，不要给药；强调一般建议即可。',
    ].join('\n');

    final inputText = '用户数据(JSON)：\n${const JsonEncoder.withIndent('  ').convert(payload)}';

    final req = {
      'model': model,
      'instructions': instructions,
      'input': inputText,
      'temperature': 0.25,
    };

    final resp = await http.post(
      endpoint,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(req),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('OpenAI API error ${resp.statusCode}: ${resp.body}');
    }

    final j = jsonDecode(resp.body) as Map<String, dynamic>;

    // 兼容取 text
    String text = '';
    final direct = j['output_text'];
    if (direct is String) text = direct;
    if (text.trim().isEmpty) {
      final output = j['output'];
      if (output is List) {
        final buf = StringBuffer();
        for (final item in output) {
          if (item is Map && item['type'] == 'message') {
            final content = item['content'];
            if (content is List) {
              for (final c in content) {
                if (c is Map) {
                  final t = c['type']?.toString();
                  if (t == 'output_text' || t == 'text') {
                    final s = c['text']?.toString() ?? '';
                    if (s.isNotEmpty) buf.writeln(s);
                  }
                }
              }
            }
          }
        }
        text = buf.toString();
      }
    }

    final raw = text.trim();
    if (raw.isEmpty) {
      return const AiAdviceResult(
        advice: [],
        risks: ['AI 返回空内容，请稍后重试。'],
        disclaimer: '此建议仅供参考，不能替代医生诊断。',
        rawText: '',
      );
    }

    try {
      final obj = jsonDecode(raw);
      if (obj is Map<String, dynamic>) {
        final advice = (obj['advice'] is List)
            ? (obj['advice'] as List).map((e) => e.toString()).toList()
            : <String>[];
        final risks = (obj['risks'] is List)
            ? (obj['risks'] as List).map((e) => e.toString()).toList()
            : <String>[];
        final disclaimer =
        (obj['disclaimer'] ?? '此建议仅供参考，不能替代医生诊断。').toString();

        return AiAdviceResult(
          advice: advice,
          risks: risks,
          disclaimer: disclaimer,
          rawText: raw,
        );
      }
    } catch (_) {
      // JSON 解析失败兜底
    }

    // 兜底：把 raw 当作建议文本
    return AiAdviceResult(
      advice: const [],
      risks: const [],
      disclaimer: '此建议仅供参考，不能替代医生诊断。',
      rawText: raw,
    );
  }
}