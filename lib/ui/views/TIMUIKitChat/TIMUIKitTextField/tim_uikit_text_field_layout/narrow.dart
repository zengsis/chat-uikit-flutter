import 'dart:async';
import 'dart:math';

import 'package:extended_text_field/extended_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_setting_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/optimize_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/permission.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/special_text/DefaultSpecialTextSpanBuilder.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/special_text/emoji_text.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_send_sound_message.dart';
import 'package:tencent_keyboard_visibility/tencent_keyboard_visibility.dart';

GlobalKey<_TIMUIKitTextFieldLayoutNarrowState> narrowTextFieldKey = GlobalKey();
/// Expose the extra bottom inset occupied by emoji/more panel in narrow layout.
/// This panel does not trigger system keyboard `viewInsets`, but it visually covers bottom area.
/// Business-side containers can listen to this to adjust their own bottom offset like keyboard.
ValueNotifier<double> timUIKitExtraBottomInset = ValueNotifier<double>(0);

class TIMUIKitTextFieldLayoutNarrow extends StatefulWidget {
  /// sticker panel customization
  final CustomStickerPanel? customStickerPanel;

  final VoidCallback onEmojiSubmitted;
  final Function(int, String) onCustomEmojiFaceSubmitted;
  final Function(String, bool) handleSendEditStatus;
  final VoidCallback backSpaceText;
  final ValueChanged<String> addStickerToText;

  final ValueChanged<String> handleAtText;

  /// Whether to use the default emoji
  final bool isUseDefaultEmoji;

  final bool isUseTencentCloudChatPackageOldKeys;

  final TUIChatSeparateViewModel model;

  /// background color
  final Color? backgroundColor;

  /// control input field behavior
  final TIMUIKitInputTextFieldController? controller;

  /// config for more panel
  final MorePanelConfig? morePanelConfig;

  final String languageType;

  final TextEditingController textEditingController;

  /// conversation id
  final String conversationID;

  /// conversation type
  final ConvType conversationType;

  final FocusNode focusNode;

  /// show more panel
  final bool showMorePanel;

  /// hint text for textField widget
  final String? hintText;

  final int? currentCursor;

  final ValueChanged<int?> setCurrentCursor;

  final VoidCallback onCursorChange;

  /// show send audio icon
  final bool showSendAudio;

  final VoidCallback handleSoftKeyBoardDelete;

  /// on text changed
  final void Function(String)? onChanged;

  final V2TimMessage? repliedMessage;

  final void Function(String)? onDeleteText;

  /// show send emoji icon
  final bool showSendEmoji;

  final VoidCallback onSubmitted;

  final VoidCallback goDownBottom;

  final List<CustomEmojiFaceData> customEmojiStickerList;

  final List<CustomStickerPackage> stickerPackageList;

  const TIMUIKitTextFieldLayoutNarrow(
      {Key? key,
      this.customStickerPanel,
      required this.onEmojiSubmitted,
      required this.onCustomEmojiFaceSubmitted,
      required this.backSpaceText,
      required this.addStickerToText,
      required this.isUseDefaultEmoji,
      this.isUseTencentCloudChatPackageOldKeys = false,
      required this.languageType,
      required this.textEditingController,
      this.morePanelConfig,
      required this.conversationID,
      required this.conversationType,
      required this.focusNode,
      this.currentCursor,
      required this.setCurrentCursor,
      required this.onCursorChange,
      required this.model,
      this.backgroundColor,
      this.onChanged,
      this.onDeleteText,
      required this.handleSendEditStatus,
      required this.handleAtText,
      required this.handleSoftKeyBoardDelete,
      this.repliedMessage,
      required this.onSubmitted,
      required this.goDownBottom,
      required this.showSendAudio,
      required this.showSendEmoji,
      required this.showMorePanel,
      this.hintText,
      required this.customEmojiStickerList,
      this.controller,
      required this.stickerPackageList})
      : super(key: key);

  @override
  State<TIMUIKitTextFieldLayoutNarrow> createState() => _TIMUIKitTextFieldLayoutNarrowState();
}

class _TIMUIKitTextFieldLayoutNarrowState extends TIMUIKitState<TIMUIKitTextFieldLayoutNarrow> {
  final TUISettingModel settingModel = serviceLocator<TUISettingModel>();

  bool showMore = false;
  bool showMoreButton = true;
  bool showSendSoundText = false;
  bool showEmojiPanel = false;
  bool showKeyboard = false;
  Function? setKeyboardHeight;
  double? bottomPadding;
  double _lastPanelHeight = 0;
  DateTime? _keepPanelHeightUntil;
  double _lastKeyboardHeight = 0;

  double _resolvePanelHeight() {
    final fallback = 248.0 + (bottomPadding ?? 0.0);
    // 优先使用本地实时记录的最近一次键盘高度（无 debounce 延迟）
    if (_lastKeyboardHeight > 0) return _lastKeyboardHeight;
    // 次选全局缓存
    if (settingModel.keyboardHeight > 0) return settingModel.keyboardHeight;
    // 兜底默认面板高度
    return fallback;
  }

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      widget.controller?.addListener(
        () {
          final actionType = widget.controller?.actionType;
          if (actionType == ActionType.hideAllPanel) {
            hideAllPanel();
          }
        },
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncExtraBottomInset();
    });
  }

  void _syncExtraBottomInset() {
    // 外层容器（如半屏弹窗）需要知道“表情/更多面板”占用的高度，避免消息区被遮挡。
    // 键盘高度由外层 viewInsets/bottomOffset 处理，这里只输出面板高度。
    //
    // 体验优化：表情/更多面板高度尽量对齐键盘高度，减少键盘 <-> 表情切换时的跳动。
    double panelHeight = 0.0;
    if (showMore || showEmojiPanel) {
      panelHeight = _resolvePanelHeight();
    }

    final next = panelHeight;
    if (timUIKitExtraBottomInset.value != next) {
      timUIKitExtraBottomInset.value = next;
    }
  }

  void setSendButton() {
    final value = widget.textEditingController.text;
    if (isWebDevice() || isAndroidDevice()) {
      if (value.isEmpty && showMoreButton != true) {
        setState(() {
          showMoreButton = true;
        });
      } else if (value.isNotEmpty && showMoreButton == true) {
        setState(() {
          showMoreButton = false;
        });
      }
    }
  }

  hideAllPanel() {
    widget.focusNode.unfocus();
    widget.currentCursor == null;
    if (showKeyboard != false || showMore != false || showEmojiPanel != false) {
      setState(() {
        showKeyboard = false;
        showMore = false;
        showEmojiPanel = false;
      });
      _syncExtraBottomInset();
    }
  }

  Widget _getBottomContainer(TUITheme theme) {
    if (showEmojiPanel) {
      return widget.customStickerPanel != null
          ? widget.customStickerPanel!(
              sendTextMessage: () {
                widget.onEmojiSubmitted();
                setSendButton();
              },
              sendFaceMessage: widget.onCustomEmojiFaceSubmitted,
              deleteText: () {
                widget.backSpaceText();
                setSendButton();
              },
              addText: (int unicode) {
                final newText = String.fromCharCode(unicode);
                widget.addStickerToText(newText);
                setSendButton();
                // handleSetDraftText();
              },
              addCustomEmojiText: ((String singleEmojiName) {
                String? emojiName = singleEmojiName.split('.png')[0];
                String compatibleEmojiName = emojiName;
                if (widget.isUseTencentCloudChatPackageOldKeys) {
                  compatibleEmojiName = EmojiUtil.getCompatibleEmojiName(emojiName);
                }

                String newText = '[$compatibleEmojiName]';
                widget.addStickerToText(newText);
                setSendButton();
              }),
              defaultCustomEmojiStickerList: widget.isUseDefaultEmoji ? TUIKitStickerConstData.emojiList : [],
              height: _resolvePanelHeight())
          : StickerPanel(
              isWideScreen: false,
              sendTextMsg: () {
                widget.onEmojiSubmitted();
                setSendButton();
              },
              sendFaceMsg: widget.onCustomEmojiFaceSubmitted,
              deleteText: () {
                widget.backSpaceText();
                setSendButton();
              },
              addText: (int unicode) {
                final newText = String.fromCharCode(unicode);
                widget.addStickerToText(newText);
                setSendButton();
                // handleSetDraftText();
              },
              addCustomEmojiText: ((String singleEmojiName) {
                String? emojiName = singleEmojiName.split('.png')[0];
                String compatibleEmojiName = emojiName;
                if (widget.isUseTencentCloudChatPackageOldKeys) {
                  compatibleEmojiName = EmojiUtil.getCompatibleEmojiName(emojiName);
                }

                String newText = '[$compatibleEmojiName]';
                widget.addStickerToText(newText);
                setSendButton();
              }),
              customStickerPackageList: widget.stickerPackageList,
              lightPrimaryColor: theme.lightPrimaryColor);
    }

    if (showMore) {
      return MorePanel(
          morePanelConfig: widget.morePanelConfig,
          conversationID: widget.conversationID,
          conversationType: widget.conversationType);
    }

    return const SizedBox(height: 0);
  }

  double _getBottomHeight() {
    if (showKeyboard) {
      final currentKeyboardHeight = MediaQuery.of(context).viewInsets.bottom;
      // 以当前 MediaQuery 的 viewInsets 为准：
      // 当上层业务容器已整体跟随键盘上移并且通过 MediaQuery 抹平了 viewInsets 时，
      // 这里不应再使用历史缓存的 keyboardHeight，否则会出现“再次上移一个键盘高度”的空隙。
      if (currentKeyboardHeight == 0) {
        // 表情面板 -> 键盘：键盘 viewInsets 会稍后才上来。
        // 为了避免底部容器高度先掉到 0（导致工具栏/输入区闪一下），
        // 在短暂窗口内保持上一次面板高度，直到键盘出现。
        final now = DateTime.now();
        if (_keepPanelHeightUntil != null &&
            now.isBefore(_keepPanelHeightUntil!) &&
            _lastPanelHeight > 0) {
          return _lastPanelHeight;
        }
        return 0;
      }
      _lastKeyboardHeight = currentKeyboardHeight;
      double originHeight = settingModel.keyboardHeight;
      if (currentKeyboardHeight != 0) {
        if (currentKeyboardHeight >= originHeight) {
          originHeight = currentKeyboardHeight;
        }
        if (setKeyboardHeight != null) {
          setKeyboardHeight!(currentKeyboardHeight);
        }
      }
      final height = originHeight != 0 ? originHeight : currentKeyboardHeight;
      return height;
    } else if (showMore || showEmojiPanel) {
      final h = _resolvePanelHeight();
      _lastPanelHeight = h;
      return h;
    } else if (widget.textEditingController.text.length >= 46 && showKeyboard == false) {
      return 25 + (bottomPadding ?? 0.0);
    } else {
      return bottomPadding ?? 0;
    }
  }

  _openMore() {
    if (!showMore) {
      widget.focusNode.unfocus();
      widget.setCurrentCursor(null);
    }
    setState(() {
      showKeyboard = false;
      showEmojiPanel = false;
      showSendSoundText = false;
      showMore = !showMore;
    });
    _syncExtraBottomInset();
  }

  _openEmojiPanel() {
    widget.onCursorChange();
    showKeyboard = showEmojiPanel;
    if (showEmojiPanel) {
      widget.focusNode.requestFocus();
      // 从面板切换到键盘：开启一个短暂窗口，避免底部高度先变 0 再变为键盘高度
      _keepPanelHeightUntil = DateTime.now().add(const Duration(milliseconds: 260));
    } else {
      widget.focusNode.unfocus();
      _keepPanelHeightUntil = null;
    }

    setState(() {
      showMore = false;
      showSendSoundText = false;
      showEmojiPanel = !showEmojiPanel;
    });
    _syncExtraBottomInset();
  }

  _debounce(
    Function(String text) fun, [
    Duration delay = const Duration(milliseconds: 30),
  ]) {
    Timer? timer;
    return (String text) {
      if (timer != null) {
        timer?.cancel();
      }

      timer = Timer(delay, () {
        fun(text);
      });
    };
  }

  String getAbstractMessage(V2TimMessage message) {
    final String? customAbstractMessage =
        widget.model.abstractMessageBuilder != null ? widget.model.abstractMessageBuilder!(message) : null;
    return customAbstractMessage ?? MessageUtils.getAbstractMessageAsync(message, widget.model.groupMemberList ?? []);
  }

  _buildRepliedMessage(V2TimMessage? repliedMessage) {
    final haveRepliedMessage = repliedMessage != null;
    if (haveRepliedMessage) {
      final String text = "${MessageUtils.getDisplayName(repliedMessage)}:${getAbstractMessage(repliedMessage)}";
      return Container(
        color: widget.backgroundColor ?? hexToColor("f5f5f6"),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                text,
                softWrap: true,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: hexToColor("8f959e"), fontSize: 14),
              ),
            ),
            const SizedBox(
              width: 16,
            ),
            InkWell(
              onTap: () {
                widget.model.repliedMessage = null;
              },
              child: Icon(Icons.clear, color: hexToColor("8f959e"), size: 18),
            )
          ],
        ),
      );
    }
    return Container();
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final theme = value.theme;

    setKeyboardHeight ??= OptimizeUtils.debounce((height) {
      settingModel.keyboardHeight = height;
    }, const Duration(seconds: 1));

    final debounceFunc = _debounce((value) {
      if (isWebDevice() || isAndroidDevice()) {
        if (value.isEmpty && showMoreButton != true) {
          setState(() {
            showMoreButton = true;
          });
        } else if (value.isNotEmpty && showMoreButton == true) {
          setState(() {
            showMoreButton = false;
          });
        }
      }
      if (widget.onChanged != null) {
        widget.onChanged!(value);
      }
      widget.handleAtText(value);
      widget.handleSendEditStatus(value, true);
      final isEmpty = value.isEmpty;
      if (isEmpty) {
        widget.handleSoftKeyBoardDelete();
      }
    }, const Duration(milliseconds: 80));

    final MediaQueryData data = MediaQuery.of(context);
    EdgeInsets padding = data.padding;
    if (bottomPadding == null || padding.bottom > bottomPadding!) {
      bottomPadding = padding.bottom;
    }

    return GestureDetector(
      onTap: () {},
      child: Column(
        children: [
          _buildRepliedMessage(widget.repliedMessage),
          Container(
            color: widget.backgroundColor ?? hexToColor("f5f5f6"),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  constraints: const BoxConstraints(minHeight: 50),
                  child: Row(
                    children: [
                      if (PlatformUtils().isMobile && widget.showSendAudio)
                        InkWell(
                          onTap: () async {
                            showKeyboard = showSendSoundText;
                            if (showSendSoundText) {
                              widget.focusNode.requestFocus();
                            }
                            if (await Permissions.checkPermission(
                              context,
                              Permission.microphone.value,
                              theme,
                            )) {
                              setState(() {
                                showEmojiPanel = false;
                                showMore = false;
                                showSendSoundText = !showSendSoundText;
                              });
                            }
                          },
                          child: SvgPicture.asset(
                            showSendSoundText ? 'images/keyboard.svg' : 'images/voice.svg',
                            package: 'tencent_cloud_chat_uikit',
                            color: const Color.fromRGBO(68, 68, 68, 1),
                            height: 28,
                            width: 28,
                          ),
                        ),
                      const SizedBox(
                        width: 10,
                      ),
                      Expanded(
                        child: showSendSoundText
                            ? SendSoundMessage(
                                onDownBottom: widget.goDownBottom,
                                conversationID: widget.conversationID,
                                conversationType: widget.conversationType)
                            : Stack(children: [
                                Center(
                                  child: KeyboardVisibility(
                                      child: ExtendedTextField(
                                          maxLines: 4,
                                          minLines: 1,
                                          focusNode: widget.focusNode,
                                          onChanged: debounceFunc,
                                          onTap: () {
                                            // 与“表情按钮切回键盘”保持同一过渡策略：
                                            // 在键盘 viewInsets 尚未上来前，短暂保留面板高度，避免先下后上。
                                            if (showEmojiPanel) {
                                              _keepPanelHeightUntil = DateTime.now().add(
                                                const Duration(milliseconds: 260),
                                              );
                                            }
                                            showKeyboard = true;
                                            widget.goDownBottom();
                                            setState(() {
                                              showEmojiPanel = false;
                                              showMore = false;
                                            });
                                          },
                                          keyboardType: TextInputType.multiline,
                                          textInputAction: PlatformUtils().isAndroid
                                              ? TextInputAction.newline
                                              : TextInputAction.send,
                                          onEditingComplete: () {
                                            widget.onSubmitted();
                                            if (showKeyboard) {
                                              widget.focusNode.requestFocus();
                                            }
                                            setState(() {
                                              if (widget.textEditingController.text.isEmpty) {
                                                showMoreButton = true;
                                              }
                                            });
                                          },
                                          textAlignVertical: TextAlignVertical.top,
                                          decoration: InputDecoration(
                                              border: InputBorder.none,
                                              hintStyle: const TextStyle(
                                                // fontSize: 10,
                                                color: Color(0xffAEA4A3),
                                              ),
                                              fillColor: Colors.white,
                                              filled: true,
                                              isDense: true,
                                              hintText: widget.hintText ?? ''),
                                          controller: widget.textEditingController,
                                          specialTextSpanBuilder: PlatformUtils().isWeb
                                              ? null
                                              : DefaultSpecialTextSpanBuilder(
                                                  isUseQQPackage:
                                                      widget.model.chatConfig.stickerPanelConfig?.useQQStickerPackage ??
                                                          true,
                                                  isUseTencentCloudChatPackage: widget.model.chatConfig
                                                          .stickerPanelConfig?.useTencentCloudChatStickerPackage ??
                                                      true,
                                                  isUseTencentCloudChatPackageOldKeys: widget
                                                          .model
                                                          .chatConfig
                                                          .stickerPanelConfig
                                                          ?.useTencentCloudChatStickerPackageOldKeys ??
                                                      false,
                                                  customEmojiStickerList: widget.customEmojiStickerList,
                                                  showAtBackground: true,
                                                  checkHttpLink: false,
                                                )),
                                      onChanged: (bool visibility) {
                                        if (showKeyboard != visibility) {
                                          setState(() {
                                            showKeyboard = visibility;
                                            // 当系统键盘弹出时，表情/更多面板应视为关闭，否则外层会把半屏高度“顶满”，
                                            // 造成放大/缩小切换看起来无效。
                                            if (visibility) {
                                              showEmojiPanel = false;
                                              showMore = false;
                                              _keepPanelHeightUntil = null;
                                            }
                                          });
                                          _syncExtraBottomInset();
                                        }
                                      }),
                                ),
                                RawKeyboardListener(
                                  autofocus: true,
                                  focusNode: FocusNode(),
                                  onKey: (key) {
                                    if (key is RawKeyDownEvent && key.logicalKey == LogicalKeyboardKey.backspace) {
                                      if (widget.onDeleteText != null) {
                                        widget.onDeleteText!(widget.textEditingController.text);
                                      }
                                    }
                                  },
                                  child: Container(),
                                ),
                              ]),
                      ),
                      const SizedBox(
                        width: 10,
                      ),
                      if (widget.showSendEmoji)
                        InkWell(
                          onTap: () {
                            _openEmojiPanel();
                            widget.goDownBottom();
                          },
                          child: PlatformUtils().isWeb
                              ? Icon(showEmojiPanel ? Icons.keyboard_alt_outlined : Icons.mood_outlined,
                                  color: hexToColor("5c6168"), size: 32)
                              : SvgPicture.asset(
                                  showEmojiPanel ? 'images/keyboard.svg' : 'images/face.svg',
                                  package: 'tencent_cloud_chat_uikit',
                                  color: const Color.fromRGBO(68, 68, 68, 1),
                                  height: 28,
                                  width: 28,
                                ),
                        ),
                      const SizedBox(
                        width: 10,
                      ),
                      if (widget.showMorePanel && showMoreButton)
                        InkWell(
                          onTap: () {
                            // model.sendCustomMessage(data: "a", convID: model.currentSelectedConv, convType: model.currentSelectedConvType == 1 ? ConvType.c2c : ConvType.group);
                            _openMore();
                            widget.goDownBottom();
                          },
                          child: PlatformUtils().isWeb
                              ? Icon(Icons.add_circle_outline_outlined, color: hexToColor("5c6168"), size: 32)
                              : SvgPicture.asset(
                                  'images/add.svg',
                                  package: 'tencent_cloud_chat_uikit',
                                  color: const Color.fromRGBO(68, 68, 68, 1),
                                  height: 28,
                                  width: 28,
                                ),
                        ),
                      if ((isAndroidDevice() || isWebDevice()) && !showMoreButton)
                        SizedBox(
                          height: 32.0,
                          child: ElevatedButton(
                            onPressed: () {
                              widget.onSubmitted();
                              if (showKeyboard) {
                                widget.focusNode.requestFocus();
                              }
                              if (widget.textEditingController.text.isEmpty) {
                                setState(() {
                                  showMoreButton = true;
                                });
                              }
                            },
                            child: Text(TIM_t("发送")),
                          ),
                        ),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: Duration(milliseconds: (showKeyboard && PlatformUtils().isAndroid) ? 200 : 340),
                  curve: Curves.fastOutSlowIn,
                  height: max(_getBottomHeight(), 0.0),
                  child: ListView(
                    physics: const NeverScrollableScrollPhysics(),
                    children: [_getBottomContainer(theme)],
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
