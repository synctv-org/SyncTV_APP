import 'dart:async';
import 'package:flutter/material.dart';
import 'package:synctv_app/models/watch_together_models.dart';
import 'package:synctv_app/services/watch_together_service.dart';
import 'package:synctv_app/pages/desktop/desktop_room_screen.dart';
import 'package:synctv_app/widgets/watch_together_admin_settings.dart';
import 'package:synctv_app/utils/message_utils.dart';
import 'package:synctv_app/utils/chat_utils.dart';

class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({super.key});

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  bool _isLoading = true;
  List<WRoom> _rooms = [];
  bool _isLoggedIn = false;
  WUser? _currentUser;
  StreamSubscription? _authErrorSubscription;

  final List<Color> _cardColors = [
    const Color(0xFFE8F0FE), // Light Blue
    const Color(0xFFFCE8E6), // Light Red
    const Color(0xFFE6F4EA), // Light Green
    const Color(0xFFFEF7E0), // Light Yellow
    const Color(0xFFF3E8FD), // Light Purple
    const Color(0xFFE0F2F1), // Light Teal
  ];

  @override
  void initState() {
    super.initState();
    _authErrorSubscription = WatchTogetherService.onAuthError.listen((_) {
      if (mounted) {
        WatchTogetherService.logout();
        setState(() {
          _isLoggedIn = false;
        });
        _showLoginDialog();
      }
    });
    _checkLoginAndLoadData();
  }

  @override
  void dispose() {
    _authErrorSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchUserInfo() async {
    try {
      final user = await WatchTogetherService.getMe();
      if (mounted) {
        setState(() {
          _currentUser = user;
        });
      }
    } catch (e) {
      // Ignore
    }
  }

  Future<void> _checkLoginAndLoadData() async {
    final token = await WatchTogetherService.getToken();
    if (token == null) {
      if (mounted) {
        _showLoginDialog();
      }
    } else {
      setState(() {
        _isLoggedIn = true;
      });
      _loadRooms(silent: false);
      await _fetchUserInfo();
    }
  }

  Future<void> _loadRooms({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
      });
    }
    try {
      final publicRoomsFuture = WatchTogetherService.getRooms();
      final myRoomsFuture = WatchTogetherService.getMyRooms().catchError((e) {
        debugPrint('Failed to fetch my rooms: $e');
        return <WRoom>[];
      });

      final results = await Future.wait([publicRoomsFuture, myRoomsFuture]);
      
      final publicRooms = results[0];
      final myRooms = results[1];
      
      final publicRoomIds = publicRooms.map((r) => r.roomId).toSet();
      final Map<String, WRoom> roomMap = {};
      
      for (var room in myRooms) {
        if (!publicRoomIds.contains(room.roomId)) {
          room = room.copyWith(hidden: true);
        }
        roomMap[room.roomId] = room;
      }
      
      for (var room in publicRooms) {
        if (!roomMap.containsKey(room.roomId)) {
          roomMap[room.roomId] = room;
        }
      }

      if (mounted) {
        setState(() {
          _rooms = roomMap.values.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        MessageUtils.showError(context, '加载房间列表失败: $e');
      }
    }
  }

  void _showLoginDialog() {
    ChatUtils.showStyledDialog<bool>(
      context: context,
      title: '登录/注册',
      icon: const Icon(Icons.login, color: Color(0xFF5D5FEF)),
      content: const _LoginDialog(),
      actions: [],
    ).then((result) {
      if (result == true) {
        setState(() {
          _isLoggedIn = true;
        });
        _loadRooms(silent: false);
        _fetchUserInfo();
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    });
  }

  void _showCreateRoomDialog() {
    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    ChatUtils.showStyledDialog(
      context: context,
      title: '创建房间',
      icon: const Icon(Icons.add_box_outlined, color: Color(0xFF5D5FEF)),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: TextStyle(color: textColor),
              decoration: const InputDecoration(
                labelText: '房间名称',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF5D5FEF))),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: passwordController,
              style: TextStyle(color: textColor),
              decoration: const InputDecoration(
                labelText: '密码 (可选)',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF5D5FEF))),
              ),
              obscureText: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (nameController.text.isEmpty) {
              MessageUtils.showWarning(context, '请输入房间名称');
              return;
            }
            try {
              await WatchTogetherService.createRoom(
                nameController.text,
                password: passwordController.text.isEmpty ? null : passwordController.text,
              );
              Navigator.pop(context);
              _loadRooms(silent: true);
              MessageUtils.showSuccess(context, '房间创建成功');
            } catch (e) {
              MessageUtils.showError(context, '创建失败: $e');
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF5D5FEF),
            foregroundColor: Colors.white,
          ),
          child: const Text('创建'),
        ),
      ],
    );
  }

  void _showJoinRoomDialog() {
    final idController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    ChatUtils.showStyledDialog(
      context: context,
      title: '加入房间',
      icon: const Icon(Icons.login_rounded, color: Color(0xFF5D5FEF)),
      content: SizedBox(
        width: 300,
        child: TextField(
          controller: idController,
          style: TextStyle(color: textColor),
          decoration: const InputDecoration(
            labelText: '房间ID',
            labelStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF5D5FEF))),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (idController.text.isEmpty) {
              MessageUtils.showWarning(context, '请输入房间ID');
              return;
            }
            try {
              final room = await WatchTogetherService.getRoomInfo(idController.text);
              Navigator.pop(context);
              _handleJoinRoom(room);
            } catch (e) {
              MessageUtils.showError(context, '查找房间失败: $e');
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF5D5FEF),
            foregroundColor: Colors.white,
          ),
          child: const Text('加入'),
        ),
      ],
    );
  }

  void _showChangePasswordDialog() {
    final passwordController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    ChatUtils.showStyledDialog(
      context: context,
      title: '修改密码',
      icon: const Icon(Icons.password, color: Color(0xFF5D5FEF)),
      content: SizedBox(
        width: 300,
        child: TextField(
          controller: passwordController,
          style: TextStyle(color: textColor),
          decoration: const InputDecoration(
            labelText: '新密码',
            labelStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF5D5FEF))),
          ),
          obscureText: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (passwordController.text.isEmpty) {
              MessageUtils.showWarning(context, '请输入新密码');
              return;
            }
            try {
              await WatchTogetherService.changePassword(passwordController.text);
              Navigator.pop(context);
              MessageUtils.showSuccess(context, '密码修改成功');
            } catch (e) {
              MessageUtils.showError(context, '修改失败: $e');
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF5D5FEF),
            foregroundColor: Colors.white,
          ),
          child: const Text('确定'),
        ),
      ],
    );
  }

  void _showAdminSettingsDialog() {
    ChatUtils.showStyledDialog(
      context: context,
      title: '管理员设置',
      icon: const Icon(Icons.admin_panel_settings, color: Color(0xFF5D5FEF)),
      content: const SizedBox(
        width: 600,
        height: 500,
        child: AdminSettingsDialog(),
      ),
      actions: [],
    ).then((_) {
      _loadRooms(silent: true);
    });
  }

  void _showServerSettingsDialog() {
    final controller = TextEditingController(text: WatchTogetherService.baseUrl);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    ChatUtils.showStyledDialog(
      context: context,
      title: '服务器设置',
      icon: const Icon(Icons.dns_rounded, color: Color(0xFF5D5FEF)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              style: TextStyle(color: textColor),
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: '例如: https://tv.test.com/api',
                labelStyle: TextStyle(color: Colors.grey),
                prefixIcon: Icon(Icons.link, color: Colors.grey),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF5D5FEF))),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '修改后可能需要重新登录',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (controller.text.isEmpty) {
              MessageUtils.showWarning(context, '请输入服务器地址');
              return;
            }
            await WatchTogetherService.setBaseUrl(controller.text);
            if (mounted) {
              Navigator.pop(context);
              MessageUtils.showSuccess(context, '服务器地址已更新');
              _loadRooms(silent: false);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF5D5FEF),
            foregroundColor: Colors.white,
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _handleLogout() {
    ChatUtils.showStyledDialog<bool>(
      context: context,
      title: '退出登录',
      icon: const Icon(Icons.logout, color: Colors.red),
      content: const Text('确定要退出当前账号吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('退出'),
        ),
      ],
    ).then((confirm) async {
      if (confirm == true) {
        await WatchTogetherService.logout();
        if (mounted) {
          setState(() {
            _isLoggedIn = false;
            _currentUser = null;
            _rooms = [];
          });
          MessageUtils.showSuccess(context, '已退出登录');
        }
      }
    });
  }

  Future<void> _handleJoinRoom(WRoom room) async {
    // Check password if needed
    if (room.needPassword) {
      final passwordController = TextEditingController();
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final textColor = isDark ? Colors.white : Colors.black87;

      final password = await ChatUtils.showStyledDialog<String>(
        context: context,
        title: '输入房间密码',
        icon: const Icon(Icons.lock),
        content: SizedBox(
          width: 300,
          child: TextField(
            controller: passwordController,
            obscureText: true,
            style: TextStyle(color: textColor),
            decoration: const InputDecoration(
              labelText: '密码',
              prefixIcon: Icon(Icons.key),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, passwordController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5D5FEF),
              foregroundColor: Colors.white,
            ),
            child: const Text('确定'),
          ),
        ],
      );

      if (password == null) return;
      if (password.isEmpty) {
        if (mounted) MessageUtils.showWarning(context, '请输入密码');
        return;
      }

      try {
        await WatchTogetherService.joinRoom(room.roomId, password);
        if (mounted) {
          _navigateToRoom(room);
        }
      } catch (e) {
        if (mounted) MessageUtils.showError(context, '加入房间失败: $e');
      }
    } else {
      try {
        await WatchTogetherService.joinRoom(room.roomId, '');
        if (mounted) {
          _navigateToRoom(room);
        }
      } catch (e) {
        if (mounted) MessageUtils.showError(context, '加入房间失败: $e');
      }
    }
  }

  void _navigateToRoom(WRoom room) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DesktopRoomScreen(room: room),
      ),
    );
  }

  Future<void> _handleDeleteRoom(WRoom room) async {
    final confirm = await ChatUtils.showStyledDialog<bool>(
      context: context,
      title: '删除房间',
      icon: const Icon(Icons.delete_outline, color: Colors.red),
      content: Text('确定要删除房间 "${room.roomName}" 吗？此操作不可撤销。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('删除'),
        ),
      ],
    );

    if (confirm == true) {
      try {
        await WatchTogetherService.deleteRoom(room.roomId);
        if (mounted) {
          MessageUtils.showSuccess(context, '房间已删除');
          _loadRooms(silent: true);
        }
      } catch (e) {
        if (mounted) MessageUtils.showError(context, '删除失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isAdmin = _currentUser != null && _currentUser!.role >= 4;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F7FC),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            color: theme.appBarTheme.backgroundColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
              ),
            ],
          ),
          child: Row(
            children: [
              GestureDetector(
                onLongPress: _showServerSettingsDialog,
                child: Row(
                  children: [
                    Image.asset('assets/icon/robot_3.png', width: 40, height: 40),
                    const SizedBox(width: 16),
                    Text(
                      'SyncTV',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (_isLoggedIn) ...[
                TextButton.icon(
                  onPressed: _showCreateRoomDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('创建房间'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),
                const SizedBox(width: 16),
                TextButton.icon(
                  onPressed: _showJoinRoomDialog,
                  icon: const Icon(Icons.login),
                  label: const Text('加入房间'),
                  style: TextButton.styleFrom(
                     padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),
                const SizedBox(width: 16),
                PopupMenuButton<String>(
                  offset: const Offset(0, 50),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.hoverColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFF5D5FEF),
                          child: Text(
                            _currentUser?.username.isNotEmpty == true 
                              ? _currentUser!.username[0].toUpperCase() 
                              : '?',
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _currentUser?.username ?? 'User',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'password',
                      child: Row(
                        children: [
                          Icon(Icons.lock_reset, size: 18),
                          SizedBox(width: 8),
                          Text('修改密码'),
                        ],
                      ),
                    ),
                    if (isAdmin)
                      const PopupMenuItem(
                        value: 'admin',
                        child: Row(
                          children: [
                            Icon(Icons.admin_panel_settings, size: 18),
                            SizedBox(width: 8),
                            Text('管理员设置'),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'server',
                      child: Row(
                        children: [
                          Icon(Icons.dns, size: 18),
                          SizedBox(width: 8),
                          Text('服务器设置'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'logout',
                      child: Row(
                        children: [
                          Icon(Icons.logout, color: Colors.red, size: 18),
                          SizedBox(width: 8),
                          Text('退出登录', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    switch (value) {
                      case 'password':
                        _showChangePasswordDialog();
                        break;
                      case 'admin':
                        _showAdminSettingsDialog();
                        break;
                      case 'server':
                        _showServerSettingsDialog();
                        break;
                      case 'logout':
                        _handleLogout();
                        break;
                    }
                  },
                ),
              ] else
                ElevatedButton.icon(
                  onPressed: _showLoginDialog,
                  icon: const Icon(Icons.login),
                  label: const Text('登录'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5D5FEF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_isLoggedIn
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        '请先登录以查看房间列表',
                        style: TextStyle(
                          fontSize: 18,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _showLoginDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5D5FEF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        ),
                        child: const Text('立即登录'),
                      ),
                    ],
                  ),
                )
              : _rooms.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('暂无房间', style: TextStyle(fontSize: 18, color: Colors.grey)),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: () => _loadRooms(silent: false),
                            child: const Text('刷新'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async => await _loadRooms(silent: true),
                      child: GridView.builder(
                        padding: const EdgeInsets.all(32),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 300,
                          childAspectRatio: 1.0, // Square cards
                          crossAxisSpacing: 24,
                          mainAxisSpacing: 24,
                        ),
                        itemCount: _rooms.length,
                        itemBuilder: (context, index) => _buildRoomCard(_rooms[index], index),
                      ),
                    ),
    );
  }

  Widget _buildRoomCard(WRoom room, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF2C2C2C) : _cardColors[index % _cardColors.length];
    
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _handleJoinRoom(room),
          onLongPress: () {
            if (_currentUser != null && _currentUser!.id == room.creatorId) {
              _handleDeleteRoom(room);
            }
          },
          child: Stack(
            children: [
              Positioned(
                right: -30,
                top: -30,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (room.hidden)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade600,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('隐藏', style: TextStyle(fontSize: 10, color: Colors.white)),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF5D5FEF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('公开', style: TextStyle(fontSize: 10, color: Colors.white)),
                          ),
                        if (room.needPassword)
                          const Icon(Icons.lock, size: 16, color: Colors.grey),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      room.roomName,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.person, size: 14, color: isDark ? Colors.white60 : Colors.black54),
                        const SizedBox(width: 4),
                        Text(
                          '${room.viewerCount} 人在线',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '房主: ${room.creator}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog();

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegistering = false;
  bool _isLoading = false;

  Future<void> _handleSubmit() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      MessageUtils.showWarning(context, '请输入用户名和密码');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isRegistering) {
        await WatchTogetherService.register(
          _usernameController.text,
          _passwordController.text,
        );
        if (mounted) {
          MessageUtils.showSuccess(context, '注册成功，请登录');
          setState(() {
            _isRegistering = false;
            _passwordController.clear();
          });
        }
      } else {
        await WatchTogetherService.login(
          _usernameController.text,
          _passwordController.text,
        );
        if (mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        MessageUtils.showError(context, '${_isRegistering ? "注册" : "登录"}失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: '用户名',
              prefixIcon: Icon(Icons.person),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '密码',
              prefixIcon: Icon(Icons.lock),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _handleSubmit(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5D5FEF),
                foregroundColor: Colors.white,
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(_isRegistering ? '注册' : '登录'),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              setState(() {
                _isRegistering = !_isRegistering;
              });
            },
            child: Text(_isRegistering ? '已有账号？去登录' : '没有账号？去注册'),
          ),
        ],
      ),
    );
  }
}
