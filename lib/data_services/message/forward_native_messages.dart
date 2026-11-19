import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'message_services.dart';

Future<void> forwardNativeMessages(
  TUIChatSeparateViewModel model,
  List<V2TimConversation> conversations,
  MessageService service,
) async {
  final revision = model.globalModel.sessionRevision;
  final conversationId = model.conversationID;
  bool current() =>
      model.globalModel.sessionRevision == revision &&
      model.conversationID == conversationId;
  final selected = List<V2TimMessage>.of(model.getSelectedMessageList());
  for (final conversation in conversations) {
    final target = conversation.groupID ?? conversation.userID ?? '';
    for (final original in selected) {
      if (!current()) return;
      final result = await service.createForwardMessage(msgID: original.msgID!);
      if (!current()) return;
      final message = result?.messageInfo;
      if (message == null) continue;
      message.cloudCustomData =
          original.cloudCustomData ?? message.cloudCustomData;
      final sender = model.tools.setUserInfoForMessage(message, result!.id);
      await model.globalModel.sendMessageFromController(
        convID: target,
        convType: conversation.type == 1 ? ConvType.c2c : ConvType.group,
        messageInfo: sender,
        cloudCustomData: sender.cloudCustomData,
      );
    }
  }
}
