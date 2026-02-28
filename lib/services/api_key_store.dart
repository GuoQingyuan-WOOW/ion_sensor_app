import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// ✅ 强烈建议：不要把 OpenAI API Key 写死在代码里。
/// - 个人自用：允许你在 App 里手动输入 key，并用 secure storage 保存
/// - 发布给别人用：必须走你自己的后端代理（否则 key 会被反编译盗走）
class ApiKeyStore {
  static const _kOpenAiKey = 'openai_api_key_v1';

  final FlutterSecureStorage _sec = const FlutterSecureStorage();

  Future<String?> readOpenAiKey() => _sec.read(key: _kOpenAiKey);

  Future<void> writeOpenAiKey(String key) => _sec.write(key: _kOpenAiKey, value: key.trim());

  Future<void> clearOpenAiKey() => _sec.delete(key: _kOpenAiKey);
}