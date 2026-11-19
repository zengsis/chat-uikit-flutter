import 'package:flutter/material.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/logger.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

Future<List<AssetEntity>?> pickIMAlbumAssets(BuildContext context) async {
  final permission = await AssetPicker.permissionCheck();
  if (!context.mounted) return null;
  final config = imAlbumPickerConfig(context);
  final provider = DefaultAssetPickerProvider(
      requestType: config.requestType,
      maxAssets: config.maxAssets,
      pageSize: config.pageSize);
  return AssetPicker.pickAssetsWithDelegate<AssetEntity, AssetPathEntity,
          DefaultAssetPickerProvider>(context,
      delegate: IMAlbumPickerBuilderDelegate(
        provider: provider,
        initialPermission: permission,
        pickerTheme: config.pickerTheme,
        textDelegate: config.textDelegate,
        locale: Localizations.localeOf(context),
      ));
}

/// 定制相册入口与选择标记，选图、预览及权限处理沿用选择器原有实现。
class IMAlbumPickerBuilderDelegate extends DefaultAssetPickerBuilderDelegate {
  IMAlbumPickerBuilderDelegate(
      {required super.provider,
      required super.initialPermission,
      super.pickerTheme,
      super.textDelegate,
      super.locale});

  @override
  Widget selectIndicator(BuildContext context, int index, AssetEntity asset) {
    final indicator = ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        final selected = provider.selectedAssets.contains(asset);
        if (!isPreviewEnabled && isSingleAssetMode && !selected) {
          return const SizedBox.shrink();
        }
        return Semantics(
          button: true,
          checked: selected,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => selectAsset(context, asset, index, selected),
            child: SizedBox.square(
              dimension: 44,
              child: Center(child: _selectionBadge(selected)),
            ),
          ),
        );
      },
    );
    if (!isPreviewEnabled) return indicator;
    return PositionedDirectional(top: 0, end: 0, child: indicator);
  }

  Widget _selectionBadge(bool selected) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected
              ? (themeColor ?? CommonColor.primaryColor)
              : const Color(0x33000000),
          border: Border.all(
            color: selected
                ? (themeColor ?? CommonColor.primaryColor)
                : Colors.white,
            width: 1.5,
          ),
          // 白色图片和深色视频上都保留清晰的轮廓。
          boxShadow: const [
            BoxShadow(color: Color(0x26000000), blurRadius: 3),
          ],
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
            : null,
      );

  @override
  Widget pathEntitySelector(BuildContext context) => UnconstrainedBox(
        child: ListenableBuilder(
          listenable:
              Listenable.merge([provider, isSwitchingPath, permissionNotifier]),
          builder: (_, child) {
            final path = provider.currentPath?.path;
            final title = isPermissionLimited && path?.isAll == true
                ? textDelegate.accessiblePathName
                : path == null
                    ? (isPermissionLimited
                        ? textDelegate.changeAccessibleLimitedAssets
                        : TIM_t('相册'))
                    : pathNameBuilder?.call(path) ?? path.name;
            return Semantics(
              button: true,
              expanded: isSwitchingPath.value,
              child: Material(
                color: const Color(0xFFF5F6F8),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      if (isPermissionLimited && provider.isAssetsEmpty) {
                        try {
                          await PhotoManager.presentLimited();
                        } catch (error) {
                          outputLogger
                              .i('scope=im.media event=album_permission_failed '
                                  'error_type=${error.runtimeType}');
                        }
                        return;
                      }
                      if (path != null) {
                        isSwitchingPath.value = !isSwitchingPath.value;
                      }
                    },
                    child: Container(
                      height: 36,
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * .5),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(
                            child: Text(title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF333333)))),
                        const SizedBox(width: 6),
                        AnimatedRotation(
                            turns: isSwitchingPath.value ? .5 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: const Icon(Icons.expand_more_rounded,
                                size: 20, color: Color(0xFF737985))),
                      ]),
                    )),
              ),
            );
          },
        ),
      );
}

/// 只覆盖相册的外观与发送文案，保留选择器原有预览、数量和权限提示。
AssetPickerConfig imAlbumPickerConfig(BuildContext context) {
  final base = AssetPicker.themeData(CommonColor.primaryColor, light: true);
  final locale = Localizations.localeOf(context);
  final AssetPickerTextDelegate text;
  if (locale.languageCode == 'zh') {
    text = locale.scriptCode == 'Hant' ||
            const ['TW', 'HK', 'MO'].contains(locale.countryCode)
        ? const _TraditionalSendText()
        : const _ChineseSendText();
  } else if (locale.languageCode == 'ja') {
    text = const _JapaneseSendText();
  } else {
    text = const _EnglishSendText();
  }
  return AssetPickerConfig(
    requestType: RequestType.common,
    textDelegate: text,
    pickerTheme: base.copyWith(
      scaffoldBackgroundColor: Colors.white,
      canvasColor: Colors.white,
      appBarTheme: base.appBarTheme.copyWith(backgroundColor: Colors.white),
      bottomAppBarTheme: base.bottomAppBarTheme.copyWith(color: Colors.white),
      checkboxTheme: CheckboxThemeData(
        shape: const CircleBorder(),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? CommonColor.primaryColor
                : const Color(0xFFF5F6F8)),
        side: WidgetStateBorderSide.resolveWith((states) => BorderSide(
              color: states.contains(WidgetState.selected)
                  ? CommonColor.primaryColor
                  : const Color(0xFFADB4C0),
              width: 1.5,
            )),
      ),
      textTheme: base.textTheme.copyWith(
          bodyLarge: base.textTheme.bodyLarge?.copyWith(color: Colors.white)),
      colorScheme: base.colorScheme.copyWith(
          primary: CommonColor.primaryColor,
          secondary: CommonColor.primaryColor,
          surface: Colors.white),
    ),
  );
}

mixin _SendLabel on AssetPickerTextDelegate {
  @override
  String get confirm => TIM_t('发送');
  @override
  AssetPickerTextDelegate get semanticsTextDelegate => this;
}

class _ChineseSendText extends AssetPickerTextDelegate with _SendLabel {
  const _ChineseSendText();
}

class _TraditionalSendText extends TraditionalChineseAssetPickerTextDelegate
    with _SendLabel {
  const _TraditionalSendText();
}

class _EnglishSendText extends EnglishAssetPickerTextDelegate with _SendLabel {
  const _EnglishSendText();
}

class _JapaneseSendText extends JapaneseAssetPickerTextDelegate
    with _SendLabel {
  const _JapaneseSendText();
}
