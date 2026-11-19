import 'dart:convert';

/// 跨端附件扩展。更新 messages 时保留回复、转发和未知业务字段。
class MediaMessageMetadata {
  static Map<String, dynamic> decode(String? value) {
    try {
      final data = jsonDecode(value ?? '{}');
      if (data is Map<String, dynamic>) return data;
    } on FormatException {
      // 历史非 JSON 扩展不参与字段读取。
    }
    return {};
  }

  static double? positiveSeconds(Object? value) {
    final number = value is num ? value.toDouble() : null;
    return number != null && number.isFinite && number > 0 ? number : null;
  }

  static double? duration(num? sdkSeconds, String? cloudCustomData) {
    final messages = decode(cloudCustomData)['messages'];
    return positiveSeconds(sdkSeconds) ??
        positiveSeconds(messages is Map ? messages['videoDuration'] : null);
  }

  static String fileName(String? cloudCustomData, String? sdkName,
      {String fallback = ''}) {
    final messages = decode(cloudCustomData)['messages'];
    final name = messages is Map ? messages['fileName'] : null;
    if (name is String && name.trim().isNotEmpty) return name;
    return sdkName?.isNotEmpty == true ? sdkName! : fallback;
  }

  static String merge(String? existing, {String? fileName, num? seconds}) {
    final root = decode(existing);
    final current = root['messages'];
    final messages = current is Map
        ? Map<String, dynamic>.from(current)
        : <String, dynamic>{};
    if (fileName != null && fileName.trim().isNotEmpty) {
      messages['fileName'] = fileName;
    }
    final valid = positiveSeconds(seconds);
    if (valid != null) messages['videoDuration'] = valid;
    root['messages'] = messages;
    return jsonEncode(root);
  }

  static String formatDuration(num seconds) {
    final total = positiveSeconds(seconds)?.floor() ?? 0;
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  static String? remoteUrl(String? value) {
    final uri = Uri.tryParse(value ?? '');
    return uri != null &&
            const ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty
        ? value
        : null;
  }
}
