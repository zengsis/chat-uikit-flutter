import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';

/// 原生回调可能只带服务器 msgID，通过本地资源路径关联尚在上传的气泡。
class MediaUploadProgress {
  final _values = <String, int>{};

  Iterable<String> _keys(V2TimMessage message) sync* {
    if (message.id?.isNotEmpty == true) yield 'id:${message.id}';
    if (message.msgID?.isNotEmpty == true) yield 'msg:${message.msgID}';
    if (message.elemType == 5 &&
        message.videoElem?.videoPath?.isNotEmpty == true) {
      yield 'video:${message.videoElem!.videoPath}';
    }
    if (message.elemType == 6 && message.fileElem?.path?.isNotEmpty == true) {
      yield 'file:${message.fileElem!.path}';
    }
  }

  void record(V2TimMessage message, int progress) {
    for (final key in _keys(message)) {
      _values[key] = progress.clamp(0, 100);
    }
    while (_values.length > 512) {
      _values.remove(_values.keys.first);
    }
  }

  int progressFor(V2TimMessage message) {
    var progress = 0;
    for (final key in _keys(message)) {
      final value = _values[key] ?? 0;
      if (value > progress) progress = value;
    }
    return progress;
  }

  void clear() => _values.clear();
}
