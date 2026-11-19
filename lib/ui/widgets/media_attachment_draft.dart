import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_message_metadata.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_message_text.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/logger.dart';

enum MediaAttachmentKind { image, video, file }

class MediaAttachmentDraft {
  MediaAttachmentDraft(this.path, this.name, this.kind,
      {this.seconds, this.snapshot, this.bytes});
  final String path, name;
  final MediaAttachmentKind kind;
  final double? seconds;
  final String? snapshot;
  int? bytes;
  V2TimMessage? failedMessage;
}

/// 弹窗独立于更多面板生命周期，发送时校验账号与会话。
Future<void> showMediaAttachmentDrafts(
  BuildContext context,
  TUIChatSeparateViewModel model,
  String conversation,
  ConvType type,
  List<MediaAttachmentDraft> drafts,
) async {
  if (drafts.isEmpty || !context.mounted) return;
  final sdk = TencentImSDKPlugin.v2TIMManager;
  final revision = model.globalModel.sessionRevision;
  final login = await sdk.getLoginUser();
  if (!context.mounted || login.code != 0 || login.data == null) return;
  Future<bool> current() async {
    final user = await sdk.getLoginUser();
    return model.globalModel.sessionRevision == revision &&
        model.conversationID == conversation &&
        user.code == 0 &&
        user.data == login.data;
  }

  if (!await current() || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.white,
    builder: (_) => MediaAttachmentSheet(
      drafts: drafts,
      current: current,
      send: (draft) =>
          sendMediaAttachmentDraft(model, conversation, type, draft),
    ),
  );
}

/// 相册直接发送与确认弹窗共用原生消息发送入口。
Future<V2TimValueCallback<V2TimMessage>?> sendMediaAttachmentDraft(
  TUIChatSeparateViewModel model,
  String conversation,
  ConvType type,
  MediaAttachmentDraft draft,
) async {
  if (draft.failedMessage != null) {
    return model.reSendFailMessage(
        message: draft.failedMessage!, convID: conversation, convType: type);
  }
  switch (draft.kind) {
    case MediaAttachmentKind.video:
      return model.sendVideoMessage(
          videoPath: draft.path,
          fileName: draft.name,
          duration: draft.seconds?.floor() ?? 0,
          videoDuration: draft.seconds,
          snapshotPath: draft.snapshot,
          convID: conversation,
          convType: type);
    case MediaAttachmentKind.file:
      return model.sendFileMessage(
          filePath: draft.path,
          fileName: draft.name,
          size: draft.bytes ?? await File(draft.path).length(),
          convID: conversation,
          convType: type);
    case MediaAttachmentKind.image:
      return model.sendImageMessage(
          imagePath: draft.path, convID: conversation, convType: type);
  }
}

/// 每条发送前重新核对账号和会话；单条失败保留聊天气泡并继续其余附件。
Future<int> sendMediaAttachmentBatch(TUIChatSeparateViewModel model,
    String conversation, ConvType type, List<MediaAttachmentDraft> drafts,
    {required Future<bool> Function() current}) async {
  var failures = 0;
  outputLogger
      .i('scope=im.media event=album_send_started count=${drafts.length}');
  for (final draft in drafts) {
    if (!await current()) {
      outputLogger.i('scope=im.media event=album_send_cancelled');
      return failures;
    }
    try {
      final result =
          await sendMediaAttachmentDraft(model, conversation, type, draft);
      if (result == null || result.code != 0) {
        draft.failedMessage = result?.data;
        failures++;
      }
    } catch (error) {
      failures++;
      outputLogger.i('scope=im.media event=attachment_send_failed '
          'kind=${draft.kind.name} error_type=${error.runtimeType}');
    }
  }
  outputLogger.i('scope=im.media event=album_send_finished failures=$failures');
  return failures;
}

class MediaAttachmentSheet extends StatefulWidget {
  const MediaAttachmentSheet(
      {super.key,
      required this.drafts,
      required this.current,
      required this.send});
  final List<MediaAttachmentDraft> drafts;
  final Future<bool> Function() current;
  final Future<V2TimValueCallback<V2TimMessage>?> Function(MediaAttachmentDraft)
      send;

  @override
  State<MediaAttachmentSheet> createState() => _AttachmentSheetState();
}

class _AttachmentSheetState extends State<MediaAttachmentSheet> {
  late final drafts = List<MediaAttachmentDraft>.of(widget.drafts);
  bool busy = false, failed = false;

  Future<void> submit() async {
    if (busy || !await widget.current() || !mounted) return;
    setState(() {
      busy = true;
      failed = false;
    });
    final batch = List<MediaAttachmentDraft>.of(drafts);
    setState(drafts.clear);
    for (var i = 0; i < batch.length; i++) {
      final draft = batch[i];
      try {
        if (!mounted || !await widget.current()) {
          if (mounted) Navigator.pop(context);
          return;
        }
        final result = await widget.send(draft);
        if (!mounted) return;
        if (result?.code != 0) {
          draft.failedMessage = result?.data;
          drafts.add(draft);
        }
      } catch (_) {
        // 已发出的消息仍由 SDK 维护状态，未成功的附件保留供重试。
        drafts.add(draft);
      }
    }
    if (!mounted) return;
    if (drafts.isEmpty) {
      Navigator.pop(context);
    } else {
      setState(() {
        busy = false;
        failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !busy,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .75),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Text(TIM_t('发送'),
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                    onPressed: busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ]),
              if (failed)
                Text(mediaMessageText('failed',
                    locale: Localizations.localeOf(context).toString())),
              Flexible(
                  child: ListView(
                shrinkWrap: true,
                children: [for (final draft in drafts) _draftView(draft)],
              )),
              if (busy)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                        color: CommonColor.primaryColor)),
              if (!busy) const SizedBox(height: 12),
              if (!busy)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: CommonColor.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: drafts.isEmpty ? null : submit,
                    child: Text(TIM_t('发送')),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _draftView(MediaAttachmentDraft draft) {
    if (draft.kind == MediaAttachmentKind.video) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height:
                (MediaQuery.sizeOf(context).height * .28).clamp(140.0, 220.0),
            width: double.infinity,
            child: ColoredBox(
              color: const Color(0xFF17191F),
              child: Stack(fit: StackFit.expand, children: [
                if (draft.snapshot != null)
                  Image.file(File(draft.snapshot!),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.videocam_outlined,
                          color: Colors.white38,
                          size: 40))
                else
                  const Icon(Icons.videocam_outlined,
                      color: Colors.white38, size: 40),
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Colors.black45),
                    child: const Icon(Icons.play_arrow_rounded,
                        size: 36, color: Colors.white),
                  ),
                ),
                if (draft.seconds != null)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(
                          MediaMessageMetadata.formatDuration(draft.seconds!),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );
    }
    if (draft.kind == MediaAttachmentKind.image) {
      return SizedBox(
          height: 120,
          child: Image.file(File(draft.path), fit: BoxFit.contain));
    }
    return _fileDraftView(draft);
  }

  Widget _fileDraftView(MediaAttachmentDraft draft) {
    final extension = draft.name.split('.').last.toLowerCase();
    final icon =
        const ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'].contains(extension)
            ? Icons.video_file_rounded
            : Icons.description_rounded;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: CommonColor.primaryColor.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: CommonColor.primaryColor, size: 28),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(draft.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 15, color: Color(0xFF222222))),
              if (draft.bytes != null) ...[
                const SizedBox(height: 4),
                Text(MediaMessageMetadata.formatFileSize(draft.bytes!),
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF888888))),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}
