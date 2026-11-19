import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_message_metadata.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_message_source.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/video_screen.dart';
import 'TIMUIKitMessageReaction/tim_uikit_message_reaction_wrapper.dart';

class TIMUIKitVideoElem extends StatefulWidget {
  const TIMUIKitVideoElem(
    this.message, {
    super.key,
    this.isShowJump = false,
    this.clearJump,
    this.isFrom,
    this.isShowMessageReaction,
    required this.chatModel,
  });
  final V2TimMessage message;
  final bool isShowJump;
  final VoidCallback? clearJump;
  final String? isFrom;
  final TUIChatSeparateViewModel chatModel;
  final bool? isShowMessageReaction;

  @override
  State<TIMUIKitVideoElem> createState() => _TIMUIKitVideoElemState();
}

class _TIMUIKitVideoElemState extends TIMUIKitState<TIMUIKitVideoElem> {
  double? probedDuration;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant TIMUIKitVideoElem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.msgID != widget.message.msgID ||
        oldWidget.message.id != widget.message.id) {
      probedDuration = null;
      load();
    }
  }

  Future<void> load() async {
    final request = ++generation;
    final message = widget.message;
    try {
      await resolveVideoMessageUrl(message);
      if (!mounted || request != generation) return;
      setState(() {});
      if (MediaMessageMetadata.duration(
              message.videoElem?.duration, message.cloudCustomData) ==
          null) {
        final seconds = await probeMessageDuration(message);
        if (mounted && request == generation) {
          setState(() => probedDuration = seconds);
        }
      }
    } catch (_) {
      // 在线地址查询失败仍展示视频占位，打开播放器后可重试。
    }
  }

  Widget snapshot() {
    final element = widget.message.videoElem;
    if (!kIsWeb) {
      for (final path in [element?.snapshotPath, element?.localSnapshotUrl]) {
        if (path != null && path.isNotEmpty && File(path).existsSync()) {
          return Image.file(File(path),
              fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder());
        }
      }
    }
    final url = MediaMessageMetadata.remoteUrl(element?.snapshotUrl);
    return url == null
        ? placeholder()
        : Image.network(url,
            fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder());
  }

  Widget placeholder() => const ColoredBox(
      color: Color(0xff32373e),
      child: Center(
          child:
              Icon(Icons.videocam_outlined, color: Colors.white38, size: 48)));

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final element = widget.message.videoElem;
    final width = element?.snapshotWidth ?? 0;
    final height = element?.snapshotHeight ?? 0;
    final ratio = width > 0 && height > 0 ? width / height : 16 / 9;
    final duration = MediaMessageMetadata.duration(
            element?.duration, widget.message.cloudCustomData) ??
        probedDuration;
    final sending =
        widget.message.status == MessageStatus.V2TIM_MSG_STATUS_SENDING;
    final hero = '${widget.message.msgID ?? widget.message.id}${widget.isFrom}';
    return GestureDetector(
      onTap: () {
        if (element == null) return;
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => VideoScreen(
                message: widget.message,
                heroTag: hero,
                videoElement: element)));
      },
      child: TIMUIKitMessageReactionWrapper(
        chatModel: widget.chatModel,
        message: widget.message,
        isShowJump: widget.isShowJump,
        clearJump: widget.clearJump,
        isFromSelf: widget.message.isSelf ?? true,
        isShowMessageReaction: widget.isShowMessageReaction ?? true,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 220,
            height: (220 / ratio).clamp(100, 300),
            child: Stack(fit: StackFit.expand, children: [
              snapshot(),
              const Center(
                  child: Icon(Icons.play_circle_fill,
                      color: Colors.white, size: 48)),
              if (duration != null)
                Positioned(
                    right: 8,
                    bottom: 8,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4)),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            child: Text(
                                MediaMessageMetadata.formatDuration(duration),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12))))),
              if (sending)
                Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: ListenableBuilder(
                        listenable: widget.chatModel.globalModel,
                        builder: (_, __) {
                          final model = widget.chatModel.globalModel;
                          final percent =
                              model.uploadProgressFor(widget.message);
                          return Column(children: [
                            Text('$percent%',
                                style: const TextStyle(color: Colors.white)),
                            LinearProgressIndicator(
                                value: percent / 100, minHeight: 3),
                          ]);
                        })),
            ]),
          ),
        ),
      ),
    );
  }
}
