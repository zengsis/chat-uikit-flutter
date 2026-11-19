import 'package:tencent_cloud_chat_uikit/ui/utils/media_message_text.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_message_source.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_message_metadata.dart';
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:open_file/open_file.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_file_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_file_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_download_progress.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_download_progress.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_callback.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/TIMUIKitMessageReaction/tim_uikit_message_reaction_wrapper.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_chat_file_icon.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/textSize.dart';
import 'package:universal_html/html.dart' as html;
import 'package:url_launcher/url_launcher.dart';

class TIMUIKitFileElem extends StatefulWidget {
  final String? messageID;
  final V2TimFileElem? fileElem;
  final bool isSelf;
  final bool isShowJump;
  final VoidCallback? clearJump;
  final V2TimMessage message;
  final bool? isShowMessageReaction;
  final TUIChatSeparateViewModel chatModel;

  const TIMUIKitFileElem(
      {Key? key,
      required this.chatModel,
      required this.messageID,
      required this.fileElem,
      required this.isSelf,
      required this.isShowJump,
      this.clearJump,
      required this.message,
      this.isShowMessageReaction})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _TIMUIKitFileElemState();
}

class _TIMUIKitFileElemState extends TIMUIKitState<TIMUIKitFileElem> {
  String filePath = "";
  bool isWebDownloading = false;
  final TUIChatGlobalModel model = serviceLocator<TUIChatGlobalModel>();
  int downloadProgress = 0;
  V2TimAdvancedMsgListener? advancedMsgListener;
  final GlobalKey containerKey = GlobalKey();
  double? containerHeight;
  bool? _downloadFailed = false;
  String? _pendingDownloadId;

  void _showDownloadResult(bool success) {
    if (!mounted ||
        _pendingDownloadId == null ||
        _pendingDownloadId != widget.message.msgID) {
      return;
    }
    _pendingDownloadId = null;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(mediaMessageText(
        success ? 'downloadSucceeded' : 'downloadFailed',
        locale: Localizations.localeOf(context).toString(),
      )),
    ));
  }

  @override
  void dispose() {
    if (advancedMsgListener != null) {
      TencentImSDKPlugin.v2TIMManager.getMessageManager().removeAdvancedMsgListener(listener: advancedMsgListener);
      advancedMsgListener = null;
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (!PlatformUtils().isWeb) {
      Future.delayed(const Duration(microseconds: 10), () {
        if (mounted) hasFile();
      });
    }
  }

  Future<bool> addAdvancedMsgListenerForDownload() async {
    if (advancedMsgListener != null) {
      return false;
    }
    advancedMsgListener = V2TimAdvancedMsgListener(
      onMessageDownloadProgressCallback: (V2TimMessageDownloadProgress messageProgress) async {
        if (mounted && messageProgress.msgID == widget.message.msgID) {
          if (messageProgress.isError || messageProgress.errorCode != 0) {
            setState(() {
              _downloadFailed = true;
            });
            _showDownloadResult(false);
            return;
          }

          if (messageProgress.isFinish) {
            if (mounted) {
              setState(() {
                downloadProgress = 100;
              });
              _showDownloadResult(true);

              if (advancedMsgListener != null) {
                TencentImSDKPlugin.v2TIMManager
                    .getMessageManager()
                    .removeAdvancedMsgListener(listener: advancedMsgListener);
                advancedMsgListener = null;
              }
            }
          } else {
            final currentProgress = messageProgress.totalSize > 0 ? (messageProgress.currentSize / messageProgress.totalSize * 100).floor().clamp(0, 100) : 0;
            if (mounted && currentProgress > downloadProgress) {
              setState(() {
                downloadProgress = currentProgress;
              });
            }
          }
        }
      },
    );
    await TencentImSDKPlugin.v2TIMManager.getMessageManager().addAdvancedMsgListener(listener: advancedMsgListener!);
    return true;
  }

  Future<bool> hasFile() async {
    if (PlatformUtils().isWeb) return true;
    for (final path in [model.getFileMessageLocation(widget.messageID),
        widget.message.fileElem?.localUrl, widget.message.fileElem?.path]) {
      if (path == null || path.isEmpty || !await File(path).exists()) continue;
      if (!mounted) return false;
      filePath = path;
      if (downloadProgress != 100) setState(() => downloadProgress = 100);
      return true;
    }
    return false;
  }

  String showFileSize(int fileSize) {
    if (fileSize < 1024) {
      return fileSize.toString() + "B";
    } else if (fileSize < 1024 * 1024) {
      return (fileSize / 1024).toStringAsFixed(2) + "KB";
    } else if (fileSize < 1024 * 1024 * 1024) {
      return (fileSize / 1024 / 1024).toStringAsFixed(2) + "MB";
    } else {
      return (fileSize / 1024 / 1024 / 1024).toStringAsFixed(2) + "GB";
    }
  }

  addUrlToWaitingPath(TUITheme theme) async {
    if (widget.messageID != null) {
      model.addWaitingList(widget.messageID!);
    }
    if (model.getWaitingListLength() == 1) {
      await downloadFile(theme);
    }
  }

  checkIsWaiting() {
    bool res = false;
    try {
      if (widget.messageID!.isNotEmpty) {
        res = model.isWaiting(widget.messageID!);
      }
    } catch (err) {
      // err
    }
    return res;
  }

  downloadFile(TUITheme theme) async {
    // SDK 下载写入应用缓存目录，原文件打开无需相册权限。
    await model.downloadFile();
  }

  Future<bool> hasZeroSize(String filePath) async {
    try {
      final file = File(filePath);
      final fileSize = await file.length();
      return fileSize == 0;
    } catch (e) {
      return false;
    }
  }

  tryOpenFile(context, theme) async {
    if (!PlatformUtils().isWeb && (await hasZeroSize(filePath) || widget.message.status == 3)) {
      onTIMCallback(TIMCallback(type: TIMCallbackType.INFO, infoRecommendText: "不支持 0KB 文件的传输", infoCode: 6660417));
      return;
    }
    try {
      filePath = await namedAttachmentCopy(filePath,
          MediaMessageMetadata.fileName(widget.message.cloudCustomData, widget.fileElem?.fileName));
      if (!mounted) return;
      if (PlatformUtils().isDesktop && !PlatformUtils().isWindows) {
        launchUrl(Uri.file(filePath));
      } else {
        OpenFile.open(filePath);
      }
      // ignore: empty_catches
    } catch (e) {
      OpenFile.open(filePath);
    }
  }

  void downloadWebFile(String fileUrl) async {
    if (mounted) {
      setState(() {
        isWebDownloading = true;
      });
    }
    String fileName = Uri.parse(fileUrl).pathSegments.last;
    try {
      http.Response response = await http.get(
        Uri.parse(fileUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      );

      final html.AnchorElement downloadAnchor = html.document.createElement('a') as html.AnchorElement;

      final html.Blob blob = html.Blob([response.bodyBytes]);

      downloadAnchor.href = html.Url.createObjectUrlFromBlob(blob);
      downloadAnchor.download = MediaMessageMetadata.fileName(widget.message.cloudCustomData, widget.fileElem?.fileName, fallback: fileName);

      downloadAnchor.click();
    } catch (e) {
      html.AnchorElement(
        href: widget.fileElem?.path ?? "",
      )
        ..setAttribute("download", MediaMessageMetadata.fileName(widget.message.cloudCustomData, widget.fileElem?.fileName, fallback: fileName))
        ..setAttribute("target", '_blank')
        ..style.display = "none"
        ..click();
    }
    if (mounted) {
      setState(() {
        isWebDownloading = false;
      });
    }
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final theme = value.theme;
    final received = downloadProgress;
    final fileName = MediaMessageMetadata.fileName(widget.message.cloudCustomData, widget.fileElem?.fileName);
    final fileSize = widget.fileElem!.fileSize;
    final borderRadius = widget.isSelf
        ? const BorderRadius.only(
            topLeft: Radius.circular(10),
            topRight: Radius.circular(2),
            bottomLeft: Radius.circular(10),
            bottomRight: Radius.circular(10))
        : const BorderRadius.only(
            topLeft: Radius.circular(2),
            topRight: Radius.circular(10),
            bottomLeft: Radius.circular(10),
            bottomRight: Radius.circular(10));
    String? fileFormat;
    if (widget.fileElem?.fileName != null && widget.fileElem!.fileName!.isNotEmpty) {
      final String fileName = MediaMessageMetadata.fileName(widget.message.cloudCustomData, widget.fileElem?.fileName);
      fileFormat = fileName.split(".")[max(fileName.split(".").length - 1, 0)];
    }
    final RenderBox? containerRenderBox = containerKey.currentContext?.findRenderObject() as RenderBox?;
    if (containerRenderBox != null) {
      containerHeight = containerRenderBox.size.height;
    }

    return Row(
      key: containerKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.isSelf && isWebDownloading)
          Container(
            margin: const EdgeInsets.only(top: 2),
            child: LoadingAnimationWidget.threeArchedCircle(
              color: theme.weakTextColor ?? Colors.grey,
              size: 20,
            ),
          ),
        TIMUIKitMessageReactionWrapper(
            chatModel: widget.chatModel,
            isShowJump: widget.isShowJump,
            clearJump: widget.clearJump,
            isFromSelf: widget.message.isSelf ?? true,
            isShowMessageReaction: widget.isShowMessageReaction ?? true,
            message: widget.message,
            child: GestureDetector(
              onTap: () async {
                if (widget.message.status == MessageStatus.V2TIM_MSG_STATUS_SENDING) return;
                try {
                  if (PlatformUtils().isWeb) {
                    if (!isWebDownloading) {
                      downloadWebFile(widget.fileElem?.path ?? "");
                    }
                    return;
                  }

                  if (mounted && _downloadFailed == true) setState(() => _downloadFailed = false);
                  await addAdvancedMsgListenerForDownload();
                  if (await hasFile()) {
                    if (mounted) {
                      tryOpenFile(context, theme);
                    } else {
                      onTIMCallback(
                        TIMCallback(
                          type: TIMCallbackType.INFO,
                          infoRecommendText: TIM_t("正在下载中"),
                          infoCode: 6660411,
                        ),
                      );
                    }
                    return;
                  }
                  if (checkIsWaiting()) {
                    onTIMCallback(
                      TIMCallback(
                          type: TIMCallbackType.INFO, infoRecommendText: TIM_t("已加入待下载队列，其他文件下载中"), infoCode: 6660413),
                    );
                    return;
                  } else {
                    _pendingDownloadId = widget.message.msgID;
                    await addUrlToWaitingPath(theme);
                  }
                } catch (e) {
                  _showDownloadResult(false);
                  onTIMCallback(
                      TIMCallback(type: TIMCallbackType.INFO, infoRecommendText: "文件处理异常", infoCode: 6660416));
                }
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 72),
                child: Container(
                  width: min(260.0, MediaQuery.sizeOf(context).width * .68),
                  decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.weakDividerColor ?? CommonColor.weakDividerColor,
                      ),
                      borderRadius: borderRadius),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                        child: Row(
                            mainAxisAlignment: widget.isSelf ? MainAxisAlignment.end : MainAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LayoutBuilder(
                                    builder: (buildContext, boxConstraints) {
                                      return CustomText(
                                        fileName,
                                        // 旧组件仅在初始化计算省略，布局变化时重新计算。
                                        key: ValueKey('$fileName:${boxConstraints.maxWidth}'),
                                        width: boxConstraints.maxWidth,
                                        maxLines: 1,
                                        style: TextStyle(
                                          color: theme.darkTextColor,
                                          fontSize: 16,
                                        ),
                                      );
                                    },
                                  ),
                                  if (fileSize != null)
                                    Text(
                                      showFileSize(fileSize),
                                      style: TextStyle(fontSize: 14, color: theme.weakTextColor),
                                    )
                                ],
                              )),
                              const SizedBox(width: 4),
                              TIMUIKitFileIcon(
                                fileFormat: fileFormat,
                              ),
                            ])),
                    if (_downloadFailed == true) Text(mediaMessageText('downloadFailed',
                        locale: Localizations.localeOf(context).toString()),
                        style: TextStyle(color: theme.weakTextColor)),
                    ListenableBuilder(listenable: model, builder: (_, __) {
                      final progressModel = model;
                      final sending = widget.message.status == MessageStatus.V2TIM_MSG_STATUS_SENDING;
                      final percent = sending ? progressModel.uploadProgressFor(widget.message) : received;
                      if (!sending && (percent == 0 || percent == 100)) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('$percent%', style: TextStyle(fontSize: 11, color: theme.weakTextColor)),
                          LinearProgressIndicator(minHeight: 3, value: percent / 100,
                            color: Colors.grey, backgroundColor: Colors.black12),
                        ]),
                      );
                    }),
                  ]),
                ),
              ),
            )),
        if (!widget.isSelf && isWebDownloading)
          Container(
            margin: const EdgeInsets.only(top: 2),
            child: LoadingAnimationWidget.threeArchedCircle(
              color: theme.weakTextColor ?? Colors.grey,
              size: 20,
            ),
          ),
      ],
    );
  }
}
