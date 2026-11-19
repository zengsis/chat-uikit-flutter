import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/logger.dart';

/// 平台异常也保留 SDK 已创建的消息，失败后使用同一消息重试。
Future<V2TimValueCallback<V2TimMessage>> sendNativeMessage(
  V2TimMessage? original,
  Future<V2TimValueCallback<V2TimMessage>> Function() send,
) async {
  V2TimValueCallback<V2TimMessage> result;
  try {
    result = await send();
  } catch (_) {
    if (original == null) rethrow;
    result = V2TimValueCallback(code: -1, desc: 'send_failed', data: original);
  }
  result.data ??= original;
  if (result.data != null) {
    final metadata = result.data!.cloudCustomData;
    if (metadata == null || metadata.isEmpty) {
      result.data!.cloudCustomData = original?.cloudCustomData;
    }
    if (result.code == 0) {
      result.data!.status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
    } else {
      result.data!.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
      outputLogger.i('scope=im.media event=send_failed code=${result.code}');
    }
  }
  return result;
}
