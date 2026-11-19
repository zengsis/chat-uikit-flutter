import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'dart:io';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_message_text.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_attachment_draft.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

/// 选择器到待发送区的适配，文件入口始终创建文件附件。
class MobileAttachmentPicker {
  static Future<void> open(
    BuildContext context,
    TUIChatSeparateViewModel model,
    String conversation,
    ConvType type, {
    required String source,
  }) async {
    final sdk = TencentImSDKPlugin.v2TIMManager;
    final revision = model.globalModel.sessionRevision;
    final login = await sdk.getLoginUser();
    if (!context.mounted || login.code != 0 || login.data == null) return;
    final drafts = <MediaAttachmentDraft>[];
    var invalidVideo = false;
    var tooLarge = false;
    try {
      final selected = await _pick(context, source);
      for (final item in selected) {
        final size = await File(item.path).length();
        item.bytes = size;
        final limit = item.kind == MediaAttachmentKind.image
            ? 28 * 1024 * 1024
            : 100 * 1024 * 1024;
        if (size == 0 || size >= limit) {
          tooLarge = true;
          continue;
        }
        if (item.kind != MediaAttachmentKind.video) {
          drafts.add(item);
          continue;
        }
        try {
          drafts.add(await _video(item));
        } catch (_) {
          invalidVideo = true;
        }
      }
      final current = await sdk.getLoginUser();
      if (!context.mounted ||
          model.globalModel.sessionRevision != revision ||
          current.data != login.data ||
          model.conversationID != conversation) {
        return;
      }
      if (invalidVideo || tooLarge) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
          invalidVideo
              ? mediaMessageText('unplayable',
                  locale: Localizations.localeOf(context).toString())
              : TIM_t('文件大小超出了限制'),
        )));
      }
      await showMediaAttachmentDrafts(
          context, model, conversation, type, drafts);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(TIM_t('文件处理异常'))));
      }
    }
  }

  static Future<List<MediaAttachmentDraft>> _pick(
      BuildContext context, String source) async {
    if (source == 'file') {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      return [
        for (final file in result?.files ?? <PlatformFile>[])
          if (file.path != null)
            MediaAttachmentDraft(
                file.path!, file.name, MediaAttachmentKind.file)
      ];
    }
    if (source == 'cameraVideo' || source == 'cameraImage') {
      final picker = ImagePicker();
      final video = source == 'cameraVideo';
      final file = video
          ? await picker.pickVideo(source: ImageSource.camera)
          : await picker.pickImage(source: ImageSource.camera);
      return [
        if (file != null)
          MediaAttachmentDraft(file.path, file.name,
              video ? MediaAttachmentKind.video : MediaAttachmentKind.image)
      ];
    }
    final assets = await AssetPicker.pickAssets(context);
    final drafts = <MediaAttachmentDraft>[];
    for (final asset in assets ?? <AssetEntity>[]) {
      final file = await asset.originFile;
      if (file == null) continue;
      if (asset.type != AssetType.image && asset.type != AssetType.video) {
        continue;
      }
      drafts.add(MediaAttachmentDraft(
          file.path,
          asset.title ?? p.basename(file.path),
          asset.type == AssetType.video
              ? MediaAttachmentKind.video
              : MediaAttachmentKind.image));
    }
    return drafts;
  }

  static Future<MediaAttachmentDraft> _video(
      MediaAttachmentDraft source) async {
    final seconds = await inspectAttachmentVideo(source.path);
    String? snapshot;
    // 封面失败仍允许发送视频，接收端会显示占位与播放按钮。
    try {
      final directory = await getTemporaryDirectory();
      final path = p.join(
          directory.path, 'im-${DateTime.now().microsecondsSinceEpoch}.jpg');
      final ok = await FcNativeVideoThumbnail().getVideoThumbnail(
          srcFile: source.path,
          destFile: path,
          format: 'jpeg',
          width: 1280,
          height: 1280,
          quality: 85);
      if (ok && await File(path).exists()) snapshot = path;
    } catch (_) {/* 媒体本身已通过播放器校验。 */}
    return MediaAttachmentDraft(
        source.path, source.name, MediaAttachmentKind.video,
        seconds: seconds, snapshot: snapshot, bytes: source.bytes);
  }
}
