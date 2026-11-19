import 'package:tencent_cloud_chat_uikit/ui/utils/media_message_source.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_message_metadata.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_video_elem.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_callback.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/permission.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_chat_videoplayer.dart';
import 'package:universal_html/html.dart' as html;

class VideoScreen extends StatefulWidget {
  const VideoScreen(
      {required this.message,
      required this.heroTag,
      required this.videoElement,
      Key? key})
      : super(key: key);

  final V2TimMessage message;
  final dynamic heroTag;
  final V2TimVideoElem videoElement;

  @override
  State<StatefulWidget> createState() => _VideoScreenState();
}

class _VideoScreenState extends TIMUIKitState<VideoScreen> {
  GlobalKey<ExtendedImageSlidePageState> slidePagekey =
      GlobalKey<ExtendedImageSlidePageState>();
  final TUIChatGlobalModel model = serviceLocator<TUIChatGlobalModel>();

  @override
  initState() {
    super.initState();
    // 允许横屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  //保存网络视频到本地
  Future<void> _saveNetworkVideo(
    context,
    String videoUrl, {
    bool isAsset = true,
  }) async {
    if (PlatformUtils().isWeb) {
      RegExp exp = RegExp(r"((\.){1}[^?]{2,4})");
      String? suffix = exp.allMatches(videoUrl).last.group(0);
      var xhr = html.HttpRequest();
      xhr.open('get', videoUrl);
      xhr.responseType = 'arraybuffer';
      xhr.onLoad.listen((event) {
        final a = html.AnchorElement(
            href: html.Url.createObjectUrl(html.Blob([xhr.response])));
        a.download = '${md5.convert(utf8.encode(videoUrl)).toString()}$suffix';
        a.click();
        a.remove();
      });
      xhr.send();
      return;
    }
    if (PlatformUtils().isMobile) {
      if (PlatformUtils().isIOS) {
        if (!await Permissions.checkPermission(
          context,
          Permission.photosAddOnly.value,
        )) {
          _showSaveResult(false);
          return;
        }
      } else {
        final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        if ((androidInfo.version.sdkInt) >= 33) {
          final videos = await Permissions.checkPermission(
            context,
            Permission.videos.value,
          );

          if (!videos) {
            _showSaveResult(false);
            return;
          }
        } else {
          final storage = await Permissions.checkPermission(
            context,
            Permission.storage.value,
          );
          if (!storage) {
            _showSaveResult(false);
            return;
          }
        }
      }
    }
    String savePath = videoUrl;
    if (!isAsset) {
      if (widget.message.msgID == null || widget.message.msgID!.isEmpty) {
        return;
      }
      if (model.getMessageProgress(widget.message.msgID) == 100) {
        String savePath;
        if (widget.message.videoElem!.localVideoUrl != null &&
            widget.message.videoElem!.localVideoUrl != '') {
          savePath = widget.message.videoElem!.localVideoUrl!;
        } else {
          savePath = model.getFileMessageLocation(widget.message.msgID);
        }
        File f = File(savePath);
        if (f.existsSync()) {
          var result = await ImageGallerySaverPlus.saveFile(savePath);
          if (PlatformUtils().isIOS) {
            if (result['isSuccess']) {
              _showSaveResult(true);
            } else {
              _showSaveResult(false);
            }
          } else {
            if (result is Map && result['isSuccess'] == true) {
              _showSaveResult(true);
            } else {
              _showSaveResult(false);
            }
          }
        }
      } else {
        onTIMCallback(TIMCallback(
            type: TIMCallbackType.INFO,
            infoRecommendText: TIM_t("the message is downloading"),
            infoCode: -1));
      }
      return;
    }
    var result = await ImageGallerySaverPlus.saveFile(savePath);
    if (PlatformUtils().isIOS) {
      if (result['isSuccess']) {
        _showSaveResult(true);
      } else {
        _showSaveResult(false);
      }
    } else {
      if (result is Map && result['isSuccess'] == true) {
        _showSaveResult(true);
      } else {
        _showSaveResult(false);
      }
    }
    return;
  }

  void _showSaveResult(bool success) {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
    final text = success ? TIM_t("视频保存成功") : TIM_t("视频保存失败");
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    onTIMCallback(TIMCallback(
        type: TIMCallbackType.INFO,
        infoRecommendText: text,
        infoCode: success ? 6660402 : 6660403));
  }

  bool _savingVideo = false;
  Future<void> _saveVideo() async {
    if (_savingVideo) return;
    setState(() => _savingVideo = true);
    try {
      if (PlatformUtils().isWeb) {
        final url =
            widget.videoElement.videoUrl ?? widget.videoElement.videoPath;
        if (url != null) await _saveNetworkVideo(context, url);
        return;
      }
      final path =
          await downloadOriginalVideo(widget.message, '${TIM_t("视频")}.mp4');
      if (mounted) await _saveNetworkVideo(context, path);
    } catch (_) {
      if (mounted) {
        _showSaveResult(false);
      }
    } finally {
      if (mounted) setState(() => _savingVideo = false);
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final title = MediaMessageMetadata.fileName(
        widget.message.cloudCustomData, null,
        fallback: TIM_t('视频'));
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
            systemNavigationBarColor: Colors.black,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false),
        centerTitle: true,
        leadingWidth: 72,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: IconButton(
            style: IconButton.styleFrom(backgroundColor: Colors.transparent),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            icon: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                    color: Color(0xFF333333), shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, size: 20)),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        actions: const [SizedBox(width: 72)],
        titleSpacing: 8,
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
      ),
      body: SafeArea(
        top: false,
        child: ExtendedImageSlidePage(
          key: slidePagekey,
          slidePageBackgroundHandler: (offset, size) => Colors.black.withValues(
              alpha: (1 - offset.distance / max(size.height / 2, 1))
                  .clamp(0.0, 1.0)),
          slideType: SlideType.onlyImage,
          slideEndHandler: (
            offset, {
            ExtendedImageSlidePageState? state,
            ScaleEndDetails? details,
          }) {
            if ((details?.velocity.pixelsPerSecond.dy ?? 0) > 300 ||
                offset.dy > 100) {
              return true;
            }
            return null;
          },
          child: TIMUIKitVideoPlayer(
            message: widget.message,
            controller: true,
            onSave: _saveVideo,
            saving: _savingVideo,
            isSending:
                widget.message.status == MessageStatus.V2TIM_MSG_STATUS_SENDING,
          ),
        ),
      ),
    );
  }
}
