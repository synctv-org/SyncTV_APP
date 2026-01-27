import 'package:flutter/material.dart';
import 'package:synctv_app/models/watch_together_models.dart';
import 'package:synctv_app/services/watch_together_service.dart';
import 'package:synctv_app/utils/message_utils.dart';
import 'package:synctv_app/utils/chat_utils.dart';
import 'package:synctv_app/widgets/ios_style_switch.dart';

import 'package:synctv_app/widgets/platform_binding_dialog.dart';

class RoomSettingsDialog extends StatefulWidget {
  final String roomId;
  final String roomName;
  final WRoomSettings currentSettings;

  const RoomSettingsDialog({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.currentSettings,
  });

  @override
  State<RoomSettingsDialog> createState() => _RoomSettingsDialogState();
}

class _RoomSettingsDialogState extends State<RoomSettingsDialog> {
  late TextEditingController _nameController;
  late TextEditingController _passwordController;
  bool _updatePassword = false;
  
  // Basic Settings
  late bool _hidden;
  late bool _joinNeedReview;
  late bool _disableJoinNewUser;
  late bool _disableGuest;
  
  // Room Permissions (Global/Default)
  late bool _canGetMovieList;
  late bool _canAddMovie;
  late bool _canEditMovie;
  late bool _canDeleteMovie;
  late bool _canSetCurrentMovie;
  late bool _canSetCurrentStatus;
  late bool _canSendChatMessage;
  
  // Guest Permissions
  late bool _guestCanGetMovieList;
  late bool _guestCanAddMovie;
  late bool _guestCanEditMovie;
  late bool _guestCanDeleteMovie;
  late bool _guestCanSetCurrentMovie;
  late bool _guestCanSetCurrentStatus;
  late bool _guestCanSendChatMessage;
  late bool _guestCanWebRTC;
  
  // User Default Permissions
  late bool _userCanGetMovieList;
  late bool _userCanAddMovie;
  late bool _userCanEditMovie;
  late bool _userCanDeleteMovie;
  late bool _userCanSetCurrentMovie;
  late bool _userCanSetCurrentStatus;
  late bool _userCanSendChatMessage;
  late bool _userCanWebRTC;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.roomName);
    _passwordController = TextEditingController(); 
    
    final s = widget.currentSettings;
    _hidden = s.hidden;
    _joinNeedReview = s.joinNeedReview;
    _disableJoinNewUser = s.disableJoinNewUser;
    _disableGuest = s.disableGuest;

    // Room Permissions
    _canGetMovieList = s.canGetMovieList;
    _canAddMovie = s.canAddMovie;
    _canEditMovie = s.canEditMovie;
    _canDeleteMovie = s.canDeleteMovie;
    _canSetCurrentMovie = s.canSetCurrentMovie;
    _canSetCurrentStatus = s.canSetCurrentStatus;
    _canSendChatMessage = s.canSendChatMessage;

    // Parse Guest Permissions
    _guestCanGetMovieList = _hasPermission(s.guestPermissions, RoomMemberPermissions.getMovieList);
    _guestCanAddMovie = _hasPermission(s.guestPermissions, RoomMemberPermissions.addMovie);
    _guestCanEditMovie = _hasPermission(s.guestPermissions, RoomMemberPermissions.editMovie);
    _guestCanDeleteMovie = _hasPermission(s.guestPermissions, RoomMemberPermissions.deleteMovie);
    _guestCanSetCurrentMovie = _hasPermission(s.guestPermissions, RoomMemberPermissions.setCurrentMovie);
    _guestCanSetCurrentStatus = _hasPermission(s.guestPermissions, RoomMemberPermissions.setCurrentStatus);
    _guestCanSendChatMessage = _hasPermission(s.guestPermissions, RoomMemberPermissions.sendChatMessage);
    _guestCanWebRTC = _hasPermission(s.guestPermissions, RoomMemberPermissions.webRTC);

    // Parse User Default Permissions
    _userCanGetMovieList = _hasPermission(s.userDefaultPermissions, RoomMemberPermissions.getMovieList);
    _userCanAddMovie = _hasPermission(s.userDefaultPermissions, RoomMemberPermissions.addMovie);
    _userCanEditMovie = _hasPermission(s.userDefaultPermissions, RoomMemberPermissions.editMovie);
    _userCanDeleteMovie = _hasPermission(s.userDefaultPermissions, RoomMemberPermissions.deleteMovie);
    _userCanSetCurrentMovie = _hasPermission(s.userDefaultPermissions, RoomMemberPermissions.setCurrentMovie);
    _userCanSetCurrentStatus = _hasPermission(s.userDefaultPermissions, RoomMemberPermissions.setCurrentStatus);
    _userCanSendChatMessage = _hasPermission(s.userDefaultPermissions, RoomMemberPermissions.sendChatMessage);
    _userCanWebRTC = _hasPermission(s.userDefaultPermissions, RoomMemberPermissions.webRTC);
  }

  bool _hasPermission(int permissions, int flag) {
    return (permissions & flag) != 0;
  }

  int _calculatePermissions({
    required bool getMovieList,
    required bool addMovie,
    required bool editMovie,
    required bool deleteMovie,
    required bool setCurrentMovie,
    required bool setCurrentStatus,
    required bool sendChatMessage,
    required bool webRTC,
  }) {
    int p = 0;
    if (getMovieList) p |= RoomMemberPermissions.getMovieList;
    if (addMovie) p |= RoomMemberPermissions.addMovie;
    if (editMovie) p |= RoomMemberPermissions.editMovie;
    if (deleteMovie) p |= RoomMemberPermissions.deleteMovie;
    if (setCurrentMovie) p |= RoomMemberPermissions.setCurrentMovie;
    if (setCurrentStatus) p |= RoomMemberPermissions.setCurrentStatus;
    if (sendChatMessage) p |= RoomMemberPermissions.sendChatMessage;
    if (webRTC) p |= RoomMemberPermissions.webRTC;
    return p;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    try {
      if (_updatePassword) {
        await WatchTogetherService.updateRoomPassword(widget.roomId, _passwordController.text);
      }

      final guestPerms = _calculatePermissions(
        getMovieList: _guestCanGetMovieList,
        addMovie: _guestCanAddMovie,
        editMovie: _guestCanEditMovie,
        deleteMovie: _guestCanDeleteMovie,
        setCurrentMovie: _guestCanSetCurrentMovie,
        setCurrentStatus: _guestCanSetCurrentStatus,
        sendChatMessage: _guestCanSendChatMessage,
        webRTC: _guestCanWebRTC,
      );

      final userPerms = _calculatePermissions(
        getMovieList: _userCanGetMovieList,
        addMovie: _userCanAddMovie,
        editMovie: _userCanEditMovie,
        deleteMovie: _userCanDeleteMovie,
        setCurrentMovie: _userCanSetCurrentMovie,
        setCurrentStatus: _userCanSetCurrentStatus,
        sendChatMessage: _userCanSendChatMessage,
        webRTC: _userCanWebRTC,
      );

      final newSettings = WRoomSettings(
        hidden: _hidden,
        joinNeedReview: _joinNeedReview,
        disableJoinNewUser: _disableJoinNewUser,
        disableGuest: _disableGuest,
        canGetMovieList: _canGetMovieList,
        canAddMovie: _canAddMovie,
        canEditMovie: _canEditMovie,
        canDeleteMovie: _canDeleteMovie,
        canSetCurrentMovie: _canSetCurrentMovie,
        canSetCurrentStatus: _canSetCurrentStatus,
        canSendChatMessage: _canSendChatMessage,
        guestPermissions: guestPerms,
        userDefaultPermissions: userPerms,
      );

      await WatchTogetherService.updateRoomAdminSettings(widget.roomId, newSettings.toJson());

      if (mounted) {
        Navigator.pop(context);
        MessageUtils.showSuccess(context, '设置已更新');
      }
    } catch (e) {
      if (mounted) {
        MessageUtils.showError(context, '更新失败: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildSwitchItem(String title, String? subtitle, bool value, ValueChanged<bool> onChanged) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.textTheme.bodyLarge?.color;
    final subtitleColor = theme.hintColor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: textColor, fontSize: 16)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: subtitleColor, fontSize: 12)),
                ],
              ],
            ),
          ),
          IOSStyleSwitch(
            value: value,
            onChanged: onChanged,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.textTheme.bodyLarge?.color;
    final subTextColor = theme.hintColor;
    final borderColor = theme.dividerColor;
    final disabledBorderColor = theme.disabledColor;

    return SizedBox(
      width: double.maxFinite,
      height: MediaQuery.of(context).size.height * 0.7, // Limit height
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('基本设置'),

                  // Password Section
                  Row(
                    children: [
                      Checkbox(
                        value: _updatePassword,
                        onChanged: (v) => setState(() => _updatePassword = v ?? false),
                        activeColor: theme.primaryColor,
                      ),
                      Text('修改密码', style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  if (_updatePassword)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 16),
                      child: TextField(
                        controller: _passwordController,
                        style: TextStyle(color: textColor),
                        obscureText: false,
                        decoration: InputDecoration(
                          labelText: '新密码',
                          labelStyle: TextStyle(color: subTextColor),
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.primaryColor)),
                          helperText: '输入新密码。如需取消密码，请留空并保存。',
                          helperStyle: TextStyle(color: subTextColor, fontSize: 10),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () => _passwordController.clear(),
                          ),
                        ),
                      ),
                    ),

                  _buildSwitchItem('隐藏房间', '不在大厅列表中显示', _hidden, (v) => setState(() => _hidden = v)),
                  _buildSwitchItem('加入需要审核', '申请加入需房主同意', _joinNeedReview, (v) => setState(() => _joinNeedReview = v)),
                  _buildSwitchItem('禁止新用户加入', '完全禁止新成员加入', _disableJoinNewUser, (v) => setState(() => _disableJoinNewUser = v)),
                  _buildSwitchItem('禁止访客', '未登录用户无法加入', _disableGuest, (v) => setState(() => _disableGuest = v)),

                  _buildSectionHeader('房间权限设置 (默认)'),
                  _buildSwitchItem('允许获取影片列表', null, _canGetMovieList, (v) => setState(() => _canGetMovieList = v)),
                  _buildSwitchItem('允许添加影片', null, _canAddMovie, (v) => setState(() => _canAddMovie = v)),
                  _buildSwitchItem('允许编辑影片', null, _canEditMovie, (v) => setState(() => _canEditMovie = v)),
                  _buildSwitchItem('允许删除影片', null, _canDeleteMovie, (v) => setState(() => _canDeleteMovie = v)),
                  _buildSwitchItem('允许切换影片', null, _canSetCurrentMovie, (v) => setState(() => _canSetCurrentMovie = v)),
                  _buildSwitchItem('允许上报进度 (播放/暂停)', null, _canSetCurrentStatus, (v) => setState(() => _canSetCurrentStatus = v)),
                  _buildSwitchItem('允许发送聊天 / 弹幕', null, _canSendChatMessage, (v) => setState(() => _canSendChatMessage = v)),

                  _buildSectionHeader('访客权限 (未登录用户)'),
                  _buildSwitchItem('获取影片列表', null, _guestCanGetMovieList, (v) => setState(() => _guestCanGetMovieList = v)),
                  _buildSwitchItem('添加影片', null, _guestCanAddMovie, (v) => setState(() => _guestCanAddMovie = v)),
                  _buildSwitchItem('编辑影片', null, _guestCanEditMovie, (v) => setState(() => _guestCanEditMovie = v)),
                  _buildSwitchItem('删除影片', null, _guestCanDeleteMovie, (v) => setState(() => _guestCanDeleteMovie = v)),
                  _buildSwitchItem('切换影片', null, _guestCanSetCurrentMovie, (v) => setState(() => _guestCanSetCurrentMovie = v)),
                  _buildSwitchItem('上报进度 (播放/暂停)', null, _guestCanSetCurrentStatus, (v) => setState(() => _guestCanSetCurrentStatus = v)),
                  _buildSwitchItem('发送聊天 / 弹幕', null, _guestCanSendChatMessage, (v) => setState(() => _guestCanSendChatMessage = v)),
                  _buildSwitchItem('语音/视频通话', null, _guestCanWebRTC, (v) => setState(() => _guestCanWebRTC = v)),

                  _buildSectionHeader('普通用户默认权限'),
                  _buildSwitchItem('获取影片列表', null, _userCanGetMovieList, (v) => setState(() => _userCanGetMovieList = v)),
                  _buildSwitchItem('添加影片', null, _userCanAddMovie, (v) => setState(() => _userCanAddMovie = v)),
                  _buildSwitchItem('编辑影片', null, _userCanEditMovie, (v) => setState(() => _userCanEditMovie = v)),
                  _buildSwitchItem('删除影片', null, _userCanDeleteMovie, (v) => setState(() => _userCanDeleteMovie = v)),
                  _buildSwitchItem('切换影片', null, _userCanSetCurrentMovie, (v) => setState(() => _userCanSetCurrentMovie = v)),
                  _buildSwitchItem('上报进度 (播放/暂停)', null, _userCanSetCurrentStatus, (v) => setState(() => _userCanSetCurrentStatus = v)),
                  _buildSwitchItem('发送聊天 / 弹幕', null, _userCanSendChatMessage, (v) => setState(() => _userCanSendChatMessage = v)),
                  _buildSwitchItem('语音/视频通话', null, _userCanWebRTC, (v) => setState(() => _userCanWebRTC = v)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ChatUtils.createCancelButton(context),
              const SizedBox(width: 8),
              if (_isLoading)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              else
                ChatUtils.createConfirmButton(context, _saveSettings, text: '保存设置'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Theme.of(context).primaryColor,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }
}
