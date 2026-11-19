import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_message_metadata.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_message_source.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_message_text.dart';

class TIMUIKitVideoPlayer extends StatefulWidget {
  const TIMUIKitVideoPlayer(
      {super.key,
      required this.message,
      required this.controller,
      required this.isSending});
  final V2TimMessage message;
  final bool controller, isSending;
  @override
  State<TIMUIKitVideoPlayer> createState() => TIMUIKitVideoPlayerState();
}

class TIMUIKitVideoPlayerState extends State<TIMUIKitVideoPlayer> {
  BetterPlayerController? player;
  bool failed = false, downloading = false;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize({bool refresh = false}) async {
    final retry = refresh || failed;
    final request = ++generation;
    player?.dispose();
    player = null;
    setState(() => failed = false);
    try {
      if (!widget.isSending || localMessageVideo(widget.message) == null) {
        await resolveVideoMessageUrl(widget.message, refresh: retry);
      }
    } catch (_) {/* 在线地址查询失败时仍可播放有效本地文件。 */}
    if (!mounted || request != generation) return;
    final local = localMessageVideo(widget.message);
    final remote =
        MediaMessageMetadata.remoteUrl(widget.message.videoElem?.videoUrl);
    // 发送中优先本地预览，已发送消息优先远端资源。
    final path = widget.isSending ? local ?? remote : remote ?? local;
    if (path == null) {
      setState(() => failed = true);
      return;
    }
    final online = MediaMessageMetadata.remoteUrl(path) != null;
    final config = BetterPlayerConfiguration(
      autoPlay: false,
      fit: BoxFit.contain,
      allowedScreenSleep: false,
      autoDispose: false,
      errorBuilder: (_, __) => errorView(),
      controlsConfiguration: const BetterPlayerControlsConfiguration(
          enableFullscreen: false,
          enableOverflowMenu: false,
          enableSkips: false),
    );
    final controller = BetterPlayerController(config);
    player = controller;
    try {
      await controller
          .setupDataSource(BetterPlayerDataSource(
              online
                  ? BetterPlayerDataSourceType.network
                  : BetterPlayerDataSourceType.file,
              path))
          .timeout(const Duration(seconds: 20));
      if (mounted && request == generation) setState(() {});
    } catch (_) {
      if (mounted && request == generation) setState(() => failed = true);
    }
  }

  Future<void> download() async {
    if (downloading) return;
    setState(() => downloading = true);
    try {
      if (kIsWeb) {
        final url =
            MediaMessageMetadata.remoteUrl(widget.message.videoElem?.videoUrl);
        if (url == null || !await launchUrl(Uri.parse(url))) {
          throw const FormatException('missing_video_source');
        }
        return;
      }
      final path =
          await downloadOriginalVideo(widget.message, '${TIM_t("视频")}.mp4');
      if (!mounted) return;
      final result = await OpenFile.open(path);
      if (mounted && result.type != ResultType.done) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(TIM_t('视频保存成功'))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(TIM_t('视频保存失败'))));
      }
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  String label(String key) =>
      mediaMessageText(key, locale: Localizations.localeOf(context).toString());

  Widget errorView() => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label('playFailed'), style: const TextStyle(color: Colors.white)),
        TextButton(
            onPressed: () => initialize(refresh: true),
            child: Text(label('retry'))),
        TextButton(
            onPressed: downloading ? null : download,
            child: Text(label('original'))),
      ]));

  @override
  void dispose() {
    generation++;
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message.hasRiskContent == true) {
      return Center(child: Text(TIM_t('视频加载失败')));
    }
    if (failed) return errorView();
    final controller = player;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(children: [
      Center(
          child: AspectRatio(
              aspectRatio:
                  controller.videoPlayerController?.value.aspectRatio ?? 16 / 9,
              child: BetterPlayer(controller: controller))),
      Positioned(
          top: 50,
          left: 16,
          right: 16,
          child: Text(
              MediaMessageMetadata.fileName(
                  widget.message.cloudCustomData, null,
                  fallback: TIM_t('视频')),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white))),
      Positioned(
          bottom: 16,
          right: 70,
          child: TextButton(
              onPressed: downloading ? null : download,
              child: Text(label('original')))),
    ]);
  }
}
