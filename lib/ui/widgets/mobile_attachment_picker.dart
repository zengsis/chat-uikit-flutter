import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_message_metadata.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_message_source.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/logger.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_attachment_draft.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/im_album_picker_config.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_message_text.dart';
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
    Future<bool> current() async {
      final user = await sdk.getLoginUser();
      return context.mounted &&
          model.globalModel.sessionRevision == revision &&
          user.code == 0 &&
          user.data == login.data &&
          model.conversationID == conversation &&
          model.globalModel.currentSelectedConv == conversation;
    }

    final drafts = <MediaAttachmentDraft>[];
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
        drafts.add(await _video(item));
      }
      if (!await current() || !context.mounted) return;
      if (tooLarge) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
          TIM_t('文件大小超出了限制'),
        )));
      }
      if (source == 'gallery') {
        final failures = await sendMediaAttachmentBatch(
            model, conversation, type, drafts,
            current: current);
        if (failures > 0 && await current() && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(mediaMessageText('failed',
                  locale: Localizations.localeOf(context).toString()))));
        }
      } else {
        await showMediaAttachmentDrafts(
            context, model, conversation, type, drafts);
      }
    } catch (error) {
      outputLogger.i('scope=im.media event=attachment_prepare_failed '
          'error_type=${error.runtimeType}');
      if (context.mounted &&
          model.globalModel.sessionRevision == revision &&
          model.conversationID == conversation &&
          model.globalModel.currentSelectedConv == conversation) {
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
    final assets = await pickIMAlbumAssets(context);
    final drafts = <MediaAttachmentDraft>[];
    for (final asset in assets ?? <AssetEntity>[]) {
      if (asset.type != AssetType.image && asset.type != AssetType.video) {
        continue;
      }
      final file = await asset.originFile;
      if (file == null) continue;
      final video = asset.type == AssetType.video;
      drafts.add(MediaAttachmentDraft(
          file.path,
          asset.title ?? p.basename(file.path),
          video ? MediaAttachmentKind.video : MediaAttachmentKind.image,
          seconds: video
              ? MediaMessageMetadata.positiveSeconds(asset.duration)
              : null,
          snapshot: video ? await _albumSnapshot(asset) : null));
    }
    return drafts;
  }

  static Future<MediaAttachmentDraft> _video(
      MediaAttachmentDraft source) async {
    final seconds = await inspectAttachmentVideo(source.path,
        fallbackSeconds: source.seconds);
    final snapshot =
        await prepareVideoSnapshot(source.path, existing: source.snapshot);
    return MediaAttachmentDraft(
        source.path, source.name, MediaAttachmentKind.video,
        seconds: seconds, snapshot: snapshot, bytes: source.bytes);
  }

  static Future<String?> _albumSnapshot(AssetEntity asset) async {
    try {
      final data = await asset
          .thumbnailDataWithSize(const ThumbnailSize(640, 360))
          .timeout(const Duration(seconds: 10));
      if (data == null || data.isEmpty) return null;
      final directory = await getTemporaryDirectory();
      final path = p.join(
          directory.path, 'im-${DateTime.now().microsecondsSinceEpoch}.jpg');
      await File(path).writeAsBytes(data, flush: true);
      return path;
    } catch (error) {
      outputLogger.i('scope=im.media event=album_cover_fallback '
          'error_type=${error.runtimeType}');
      return null;
    }
  }
}
