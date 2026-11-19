import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'media_message_metadata.dart';
import 'logger.dart';

/// URL 缺失时从原生 SDK 获取在线资源，封面可独立缺失。
Future<void> resolveVideoMessageUrl(V2TimMessage message,
    {bool refresh = false}) async {
  if ((!refresh &&
          MediaMessageMetadata.remoteUrl(message.videoElem?.videoUrl) !=
              null) ||
      message.msgID?.isNotEmpty != true) {
    return;
  }
  final response = await TencentImSDKPlugin.v2TIMManager
      .getMessageManager()
      .getMessageOnlineUrl(msgID: message.msgID!)
      .timeout(const Duration(seconds: 15));
  final online = response.data?.videoElem;
  final element = message.videoElem;
  if (response.code == 0 && online != null && element != null) {
    element.videoUrl = online.videoUrl;
    element.snapshotUrl = online.snapshotUrl ?? element.snapshotUrl;
    element.snapshotWidth ??= online.snapshotWidth;
    element.snapshotHeight ??= online.snapshotHeight;
  }
}

String? localMessageVideo(V2TimMessage message) {
  if (kIsWeb) return null;
  for (final path in [
    message.videoElem?.videoPath,
    message.videoElem?.localVideoUrl
  ]) {
    if (path != null && path.isNotEmpty && File(path).existsSync()) return path;
  }
  return null;
}

Future<double?> probeMessageDuration(V2TimMessage message) async {
  VideoPlayerController? player;
  try {
    final local = localMessageVideo(message);
    final remote = MediaMessageMetadata.remoteUrl(message.videoElem?.videoUrl);
    if (local == null && remote == null) return null;
    player = local != null
        ? VideoPlayerController.file(File(local))
        : VideoPlayerController.networkUrl(Uri.parse(remote!));
    await player.initialize().timeout(const Duration(seconds: 12));
    return MediaMessageMetadata.positiveSeconds(
        player.value.duration.inMilliseconds / 1000);
  } catch (_) {
    return null;
  } finally {
    await player?.dispose();
  }
}

/// 原文件按原始名称保存在应用文档目录，不依赖相册权限。
Future<String> downloadOriginalVideo(
    V2TimMessage message, String fallbackName) async {
  await resolveVideoMessageUrl(message);
  final raw = MediaMessageMetadata.fileName(message.cloudCustomData, null,
      fallback: fallbackName);
  final name = p
      .basename(raw.replaceAll('\\', '/'))
      .replaceAll(RegExp(r'[\x00-\x1f]'), '_');
  final root = await getApplicationDocumentsDirectory();
  final folder = await Directory(p.join(root.path, 'IMDownloads',
          DateTime.now().microsecondsSinceEpoch.toString()))
      .create(recursive: true);
  final target = File(p.join(folder.path,
      name.isEmpty || name == '.' || name == '..' ? fallbackName : name));
  final local = localMessageVideo(message);
  if (local != null) {
    await File(local).copy(target.path);
    return target.path;
  }
  final url = MediaMessageMetadata.remoteUrl(message.videoElem?.videoUrl);
  if (url == null) throw const FormatException('missing_video_source');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  final partial = File('${target.path}.download');
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != HttpStatus.ok) {
      throw const HttpException('media_download_failed');
    }
    await response
        .timeout(const Duration(seconds: 30))
        .pipe(partial.openWrite());
    await partial.rename(target.path);
    return target.path;
  } catch (_) {
    if (await partial.exists()) await partial.delete();
    rethrow;
  } finally {
    client.close(force: true);
  }
}

/// 打开附件前恢复原始名称及后缀，缓存文件名不影响系统文件类型识别。
Future<String> namedAttachmentCopy(String source, String name) async {
  final safeName = p
      .basename(name.replaceAll('\\', '/'))
      .replaceAll(RegExp(r'[\x00-\x1f]'), '_');
  if (safeName.isEmpty || safeName == '.' || safeName == '..') return source;
  if (p.basename(source) == safeName) return source;
  final root = await getApplicationDocumentsDirectory();
  final folder = await Directory(p.join(root.path, 'IMDownloads',
          DateTime.now().microsecondsSinceEpoch.toString()))
      .create(recursive: true);
  return (await File(source).copy(p.join(folder.path, safeName))).path;
}

/// 播放器仅补充精确时长，本机解码失败不等同于视频不能上传。
Future<double?> inspectAttachmentVideo(String path,
    {double? fallbackSeconds}) async {
  final player = VideoPlayerController.file(File(path));
  try {
    await player.initialize().timeout(const Duration(seconds: 15));
    final seconds = MediaMessageMetadata.positiveSeconds(
        player.value.duration.inMilliseconds / 1000);
    if (seconds != null) return seconds;
  } catch (error) {
    outputLogger.i('scope=im.media event=video_duration_fallback '
        'error_type=${error.runtimeType}');
  } finally {
    try {
      await player.dispose().timeout(const Duration(seconds: 3));
    } catch (error) {
      outputLogger.i('scope=im.media event=video_probe_dispose_failed '
          'error_type=${error.runtimeType}');
    }
  }
  return MediaMessageMetadata.positiveSeconds(fallbackSeconds);
}

/// SDK 要求本地封面存在；依次使用相册封面、视频抽帧、现有占位资源。
Future<String> prepareVideoSnapshot(String videoPath,
    {String? existing}) async {
  if (existing != null &&
      await File(existing).exists() &&
      await File(existing).length() > 0) {
    return existing;
  }
  final directory = await getTemporaryDirectory();
  final path =
      p.join(directory.path, 'im-${DateTime.now().microsecondsSinceEpoch}.jpg');
  outputLogger.i('scope=im.media event=video_cover_started');
  try {
    final ok = await FcNativeVideoThumbnail()
        .getVideoThumbnail(
            srcFile: videoPath,
            destFile: path,
            format: 'jpeg',
            width: 1280,
            height: 1280,
            quality: 85)
        .timeout(const Duration(seconds: 10));
    if (ok && await File(path).exists() && await File(path).length() > 0) {
      outputLogger.i('scope=im.media event=video_cover_succeeded');
      return path;
    }
  } catch (error) {
    outputLogger.i('scope=im.media event=video_cover_failed '
        'error_type=${error.runtimeType}');
  }
  final data = await rootBundle
      .load('packages/tencent_cloud_chat_uikit/images/video_icon.png');
  final placeholder = File(p.setExtension(path, '.png'));
  await placeholder.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true);
  outputLogger.i('scope=im.media event=video_cover_placeholder');
  return placeholder.path;
}
