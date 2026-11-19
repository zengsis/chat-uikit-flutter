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
import 'package:video_player/video_player.dart';

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
    builder: (_) => MediaAttachmentSheet(
      drafts: drafts,
      current: current,
      send: (draft) async {
        if (draft.failedMessage != null) {
          return model.reSendFailMessage(
              message: draft.failedMessage!,
              convID: conversation,
              convType: type);
        }
        switch (draft.kind) {
          case MediaAttachmentKind.video:
            return model.sendVideoMessage(
                videoPath: draft.path,
                fileName: draft.name,
                duration: draft.seconds?.floor(),
                videoDuration: draft.seconds,
                snapshotPath: draft.snapshot,
                convID: conversation,
                convType: type);
          case MediaAttachmentKind.file:
            return model.sendFileMessage(
                filePath: draft.path,
                fileName: draft.name,
                size: await File(draft.path).length(),
                convID: conversation,
                convType: type);
          case MediaAttachmentKind.image:
            return model.sendImageMessage(
                imagePath: draft.path, convID: conversation, convType: type);
        }
      },
    ),
  );
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
                    child: CircularProgressIndicator()),
              if (!busy)
                FilledButton(
                  onPressed: drafts.isEmpty ? null : submit,
                  child: Text(TIM_t('发送')),
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
        child: Stack(alignment: Alignment.bottomRight, children: [
          SizedBox(
              height: 180,
              width: double.infinity,
              child: draft.snapshot == null
                  ? const Icon(Icons.videocam_outlined)
                  : Image.file(File(draft.snapshot!),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.videocam_outlined))),
          const Center(child: Icon(Icons.play_circle_outline, size: 42)),
          if (draft.seconds != null)
            Text(MediaMessageMetadata.formatDuration(draft.seconds!)),
        ]),
      );
    }
    if (draft.kind == MediaAttachmentKind.image) {
      return SizedBox(
          height: 120,
          child: Image.file(File(draft.path), fit: BoxFit.contain));
    }
    return ListTile(
        leading: const Icon(Icons.insert_drive_file_outlined),
        title: Text(draft.name),
        subtitle: draft.bytes == null ? null : Text('${draft.bytes} B'));
  }
}

/// 使用播放器实测时长，避免相册整数 duration 丢失小数或返回 0。
Future<double> inspectAttachmentVideo(String path) async {
  final player = VideoPlayerController.file(File(path));
  try {
    await player.initialize().timeout(const Duration(seconds: 15));
    final seconds = player.value.duration.inMilliseconds / 1000;
    if (seconds <= 0 || !seconds.isFinite) {
      throw const FormatException('video_duration');
    }
    return seconds;
  } finally {
    await player.dispose();
  }
}
