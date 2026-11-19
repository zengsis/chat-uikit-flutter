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
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/im_video_controls.dart';

class TIMUIKitVideoPlayer extends StatefulWidget {
  const TIMUIKitVideoPlayer(
      {super.key,
      required this.message,
      required this.controller,
      required this.isSending,
      this.onSave,
      this.saving = false});
  final V2TimMessage message;
  final bool controller, isSending;
  final Future<void> Function()? onSave;
  final bool saving;
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
      aspectRatio: videoAspectRatio(),
      fit: BoxFit.contain,
      allowedScreenSleep: false,
      autoDispose: false,
      errorBuilder: (_, __) => errorView(),
      controlsConfiguration:
          const BetterPlayerControlsConfiguration(showControls: false),
    );
    final controller = BetterPlayerController(config);
    player = controller;
    controller.addEventsListener((event) {
      if (event.betterPlayerEventType == BetterPlayerEventType.initialized &&
          mounted &&
          request == generation) {
        // 初始化完成后按媒体真实比例布局，避免竖屏视频被横屏容器缩小。
        controller.setOverriddenAspectRatio(videoAspectRatio());
        setState(() {});
      }
    });
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
    final message = widget.message;
    String? downloadedPath;
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
      final path = await downloadOriginalVideo(message, '${TIM_t("视频")}.mp4');
      if (!mounted || widget.message != message) return;
      downloadedPath = path;
      _showDownloadResult(true);
    } catch (_) {
      if (mounted && widget.message == message) _showDownloadResult(false);
    } finally {
      if (mounted) setState(() => downloading = false);
    }
    if (downloadedPath == null || !mounted || widget.message != message) return;
    try {
      await OpenFile.open(downloadedPath);
    } catch (_) {
      // 外部打开属于辅助操作，失败时仍保留已经提示的下载成功结果。
    }
  }

  void _showDownloadResult(bool success) {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(label(success ? 'downloadSucceeded' : 'downloadFailed'))));
  }

  String label(String key) =>
      mediaMessageText(key, locale: Localizations.localeOf(context).toString());

  double videoAspectRatio() {
    final size = player?.videoPlayerController?.value.size;
    if (size != null && size.width > 0 && size.height > 0) {
      return size.width / size.height;
    }
    final element = widget.message.videoElem;
    final width = element?.snapshotWidth ?? 0;
    final height = element?.snapshotHeight ?? 0;
    return width > 0 && height > 0 ? width / height : 16 / 9;
  }

  Widget errorView() => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label('playFailed'), style: const TextStyle(color: Colors.white)),
        TextButton(
            style:
                TextButton.styleFrom(foregroundColor: CommonColor.primaryColor),
            onPressed: () => initialize(refresh: true),
            child: Text(label('retry'))),
        TextButton(
            style:
                TextButton.styleFrom(foregroundColor: CommonColor.primaryColor),
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
      return Center(
          child: Text(TIM_t('视频加载失败'),
              style: const TextStyle(color: Colors.white70)));
    }
    if (failed) return errorView();
    final controller = player;
    if (controller == null) {
      return const Center(
          child: CircularProgressIndicator(color: CommonColor.primaryColor));
    }
    return IMVideoControls(
        controller: controller,
        onVisibilityChanged: controller.setControlsVisibility,
        onSave: widget.onSave ?? download,
        isSaving: widget.saving || downloading,
        child: Center(
            child: AspectRatio(
                aspectRatio: videoAspectRatio(),
                child: BetterPlayer(controller: controller))));
  }
}
