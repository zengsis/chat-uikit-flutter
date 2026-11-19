import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';

/// 在图片预览层内展示下载结果，避免提示被透明预览路由遮挡。
class ImageDownloadButton extends StatefulWidget {
  const ImageDownloadButton({super.key, required this.onDownload});

  final Future<void> Function() onDownload;

  @override
  State<ImageDownloadButton> createState() => _ImageDownloadButtonState();
}

class _ImageDownloadButtonState extends State<ImageDownloadButton> {
  bool _loading = false;
  String? _result;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  Future<void> _download() async {
    if (_loading) return;
    _hideTimer?.cancel();
    setState(() {
      _loading = true;
      _result = null;
    });
    var success = false;
    try {
      await widget.onDownload();
      success = true;
    } catch (_) {
      // 保存服务通过异常返回失败，界面只显示可读文案。
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = success ? TIM_t('图片保存成功') : TIM_t('图片保存失败');
    });
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _result = null);
    });
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_result != null)
            Semantics(
              liveRegion: true,
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xE6333333),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_result!,
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
              ),
            ),
          SizedBox.square(
            dimension: 48,
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : IconButton(
                    icon: Image.asset('images/download.png',
                        package: 'tencent_cloud_chat_uikit'),
                    iconSize: 30,
                    onPressed: _download,
                  ),
          ),
        ],
      );
}
