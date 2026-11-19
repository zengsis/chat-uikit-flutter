import 'dart:async';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/logger.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_message_metadata.dart';

/// 视频与控制区分开布局，控件隐藏时保留空间，避免画面尺寸跳动。
class IMVideoControls extends StatefulWidget {
  const IMVideoControls(
      {super.key,
      required this.controller,
      required this.child,
      required this.onVisibilityChanged,
      this.onSave,
      this.isSaving = false});
  final BetterPlayerController controller;
  final Widget child;
  final ValueChanged<bool> onVisibilityChanged;
  final Future<void> Function()? onSave;
  final bool isSaving;
  @override
  State<IMVideoControls> createState() => _IMVideoControlsState();
}

class _IMVideoControlsState extends State<IMVideoControls> {
  Timer? _hideTimer;
  bool _visible = true, _dragging = false;
  double _seekMilliseconds = 0, _lastVolume = 1;

  @override
  void initState() {
    super.initState();
    widget.controller.addEventsListener(_onEvent);
  }

  @override
  void didUpdateWidget(covariant IMVideoControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeEventsListener(_onEvent);
    widget.controller.addEventsListener(_onEvent);
    _hideTimer?.cancel();
    _visible = true;
    _dragging = false;
  }

  void _onEvent(BetterPlayerEvent event) {
    if (const [
      BetterPlayerEventType.play,
      BetterPlayerEventType.pause,
      BetterPlayerEventType.finished
    ].contains(event.betterPlayerEventType)) {
      _show();
    }
  }

  void _show() {
    if (!mounted) return;
    if (!_visible) {
      setState(() => _visible = true);
      widget.onVisibilityChanged(true);
    }
    _hideTimer?.cancel();
    if (widget.controller.isPlaying() != true || _dragging) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _dragging) return;
      setState(() => _visible = false);
      widget.onVisibilityChanged(false);
    });
  }

  Future<void> _act(String action, Future<void> Function() operation) async {
    final controller = widget.controller;
    try {
      await operation();
    } catch (error) {
      outputLogger.i('scope=im.media event=video_control_failed '
          'action=$action error_type=${error.runtimeType}');
    } finally {
      if (mounted && controller == widget.controller) _show();
    }
  }

  void _playPause() {
    final controller = widget.controller;
    unawaited(_act('play_pause', () async {
      if (controller.isPlaying() == true) {
        await controller.pause();
      } else {
        final value = controller.videoPlayerController?.value;
        if (value?.duration != null && value!.position >= value.duration!) {
          await controller.seekTo(Duration.zero);
        }
        await controller.play();
      }
    }));
  }

  void _mute() {
    final controller = widget.controller;
    final volume = controller.videoPlayerController?.value.volume ?? 1;
    if (volume > 0) _lastVolume = volume;
    unawaited(_act(
        'volume', () => controller.setVolume(volume > 0 ? 0 : _lastVolume)));
  }

  Future<void> _seek(double value) async {
    final controller = widget.controller;
    await _act(
        'seek', () => controller.seekTo(Duration(milliseconds: value.round())));
    if (!mounted || controller != widget.controller) return;
    setState(() => _dragging = false);
    _show();
  }

  Widget _button(IconData icon, VoidCallback? onPressed) => IconButton(
      onPressed: onPressed,
      style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          hoverColor: Colors.white10,
          highlightColor: Colors.white12),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      color: Colors.white,
      disabledColor: Colors.white38,
      icon: Icon(icon, size: 32));

  String _time(Duration value) =>
      MediaMessageMetadata.formatDuration(value.inMilliseconds / 1000);

  Widget _progressBar(double total, double position) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          trackShape: const RectangularSliderTrackShape(),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          activeTrackColor: Colors.white70,
          inactiveTrackColor: Colors.white24,
          thumbColor: Colors.white,
          overlayColor: Colors.white12),
      child: Slider(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        value: position,
        max: total > 0 ? total : 1,
        onChangeStart: total > 0
            ? (value) {
                _hideTimer?.cancel();
                setState(() {
                  _dragging = true;
                  _seekMilliseconds = value;
                });
              }
            : null,
        onChanged: total > 0
            ? (value) => setState(() => _seekMilliseconds = value)
            : null,
        onChangeEnd: total > 0 ? (value) => unawaited(_seek(value)) : null,
      ),
    );
  }

  Widget _roundAction(IconData icon, VoidCallback? onPressed,
          {bool busy = false}) =>
      IconButton.filled(
        style: IconButton.styleFrom(
            backgroundColor: const Color(0xFF333333),
            foregroundColor: Colors.white,
            fixedSize: const Size(44, 44),
            shape: const CircleBorder()),
        onPressed: onPressed,
        icon: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Icon(icon, size: 23),
      );

  Widget _bar(VideoPlayerValue value) {
    final duration = value.duration ?? Duration.zero;
    final total = duration.inMilliseconds.toDouble();
    final position = (_dragging
            ? _seekMilliseconds
            : value.position.inMilliseconds.toDouble())
        .clamp(0.0, total > 0 ? total : 1.0);
    return ColoredBox(
      color: Colors.black,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 20, 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            _button(
                value.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                value.initialized ? _playPause : null),
            const SizedBox(width: 2),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Text(
                      '${_time(Duration(milliseconds: position.round()))} / ${_time(duration)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 13, color: Colors.white70)),
                  SizedBox(height: 24, child: _progressBar(total, position)),
                ])),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 20, 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (widget.onSave != null) ...[
              _roundAction(
                  Icons.file_download_outlined,
                  widget.isSaving
                      ? null
                      : () => unawaited(_act('save', widget.onSave!)),
                  busy: widget.isSaving),
              const SizedBox(width: 12),
            ],
            _roundAction(
                value.volume == 0
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                value.initialized ? _mute : null),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.controller.videoPlayerController;
    if (video == null) return widget.child;
    return ListenableBuilder(
        listenable: video,
        child: widget.child,
        builder: (_, child) {
          final value = video.value;
          // 失败状态交回播放器的重试界面，避免透明触摸层挡住错误操作。
          if (value.hasError) return child!;
          return Column(children: [
            Expanded(
                child: Stack(fit: StackFit.expand, children: [
              child!,
              GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (!_visible) {
                      _show();
                      return;
                    }
                    _hideTimer?.cancel();
                    setState(() => _visible = false);
                    widget.onVisibilityChanged(false);
                  }),
              if (value.isBuffering || !value.initialized)
                const Center(
                    child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))),
            ])),
            IgnorePointer(
                ignoring: !_visible,
                child: AnimatedOpacity(
                    opacity: _visible ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: _bar(value))),
          ]);
        });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeEventsListener(_onEvent);
    super.dispose();
  }
}
