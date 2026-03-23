import 'package:flutter/material.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/contact_list.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

GlobalKey<_AddGroupMemberPageState> addGroupMemberKey = GlobalKey();

class AddGroupMemberPage extends StatefulWidget {
  final TUIGroupProfileModel model;
  final VoidCallback? onClose;

  const AddGroupMemberPage({Key? key, required this.model, this.onClose}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _AddGroupMemberPageState();
}

class _AddGroupMemberPageState extends TIMUIKitState<AddGroupMemberPage> {
  List<V2TimFriendInfo> selectedContacts = [];

  void submitAdd() async {
    if (selectedContacts.isNotEmpty) {
      final userIDs = selectedContacts.map((e) => e.userID).toList();
      await widget.model.inviteUserToGroup(userIDs);
      widget.onClose ?? Navigator.pop(context);
    }
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final TUITheme theme = value.theme;

    final resolvedTitleStyle = (Theme.of(context).appBarTheme.titleTextStyle ??
            Theme.of(context).textTheme.titleLarge ??
            const TextStyle(fontSize: 16))
        .copyWith(color: Colors.black);

    return TUIKitScreenUtils.getDeviceWidget(
        context: context,
        desktopWidget: Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ContactList(
            bgColor: Colors.white,
            groupMemberList: widget.model.groupMemberList,
            contactList: widget.model.contactList,
            isCanSelectMemberItem: true,
            onSelectedMemberItemChange: (selectedMember) {
              selectedContacts = selectedMember;
            },
          ),
        ),
        defaultWidget: Scaffold(
            backgroundColor: theme.weakBackgroundColor, // 页面背景色
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(kToolbarHeight),
              child: AppBar(
                  elevation: 1,
                  backgroundColor: Colors.white,
                  iconTheme: const IconThemeData(
                    color: Colors.black, // iOS 风格深色返回箭头
                  ),
                  title: Align(
                    alignment: Alignment.center,
                    child: Text(
                      TIM_t("添加群成员"),
                      style: resolvedTitleStyle,
                    ),
                  ),
                  leading: IconButton(
                    icon: Image.asset(
                      'images/arrow_back_black.png',
                      width: 20,
                      height: 20,
                      package: 'tencent_cloud_chat_uikit',
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        submitAdd();
                      },
                      child: Text(
                        TIM_t("确定"),
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                        ),
                      ),
                    )
                  ],
                  shadowColor: theme.weakDividerColor),
            ),
            body: ContactList(
              bgColor: Colors.white,
              groupMemberList: widget.model.groupMemberList,
              contactList: widget.model.contactList,
              isCanSelectMemberItem: true,
              onSelectedMemberItemChange: (selectedMember) {
                selectedContacts = selectedMember;
              },
            )));
  }
}
