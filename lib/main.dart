import 'dart:async';
import 'package:flutter/material.dart';
import 'package:synctv_app/models/watch_together_models.dart';
import 'package:synctv_app/services/watch_together_service.dart';
import 'package:synctv_app/watch_together_room_screen.dart';
import 'package:synctv_app/watch_together_admin_settings.dart';
import 'package:synctv_app/utils/message_utils.dart';
import 'package:synctv_app/utils/chat_utils.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WatchTogetherService.init();
  VideoPlayerMediaKit.ensureInitialized(
    android: true,
    iOS: true,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SyncTV',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5D5FEF),
          surface: Colors.white,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        cardTheme: const CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5D5FEF),
          brightness: Brightness.dark,
        ),
      ),
      home: const WatchTogetherHomeScreen(),
    );
  }
}

class WatchTogetherHomeScreen extends StatefulWidget {
  const WatchTogetherHomeScreen({super.key});

  @override
  State<WatchTogetherHomeScreen> createState() => _WatchTogetherHomeScreenState();
}

class _WatchTogetherHomeScreenState extends State<WatchTogetherHomeScreen> {
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
    VideoPlayerMediaKit.ensureInitialized(
      android: true,
      iOS: true,
    );
    _authErrorSubscription = WatchTogetherService.onAuthError.listen((_) {
      if (mounted) {
        // Clear token to ensure UI reflects logged out state if needed
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
        print('Failed to fetch my rooms: $e');
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
      content: const LoginDialog(),
      actions: [],
    ).then((result) {
      if (result == true) {
        setState(() {
          _isLoggedIn = true;
        });
        _loadRooms(silent: false);
        _fetchUserInfo(); // Fetch user info after login
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
      content: Column(
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
      content: TextField(
        controller: idController,
        style: TextStyle(color: textColor),
        decoration: const InputDecoration(
          labelText: '房间ID',
          labelStyle: TextStyle(color: Colors.grey),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF5D5FEF))),
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
              Navigator.pop(context); // Close join dialog
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
      content: TextField(
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
        width: double.maxFinite,
        height: 500,
        child: AdminSettingsDialog(),
      ),
      actions: [],
    ).then((_) {
      _loadRooms(silent: true);
    });
  }

  void _showOptionsBottomSheet() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isAdmin = _currentUser != null && _currentUser!.role >= 4;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Colors.grey.shade900 : Colors.white,
      elevation: 20,
      barrierColor: Colors.black.withOpacity(0.5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade600 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              if (!_isLoggedIn)
                _buildOptionItem(
                  icon: Icons.login,
                  title: '登录账号',
                  color: const Color(0xFF5D5FEF),
                  isDark: isDark,
                  onTap: () {
                    Navigator.pop(context);
                    _showLoginDialog();
                  },
                ),
              _buildOptionItem(
                icon: Icons.add_box_outlined,
                title: '创建房间',
                color: const Color(0xFF5D5FEF),
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  _showCreateRoomDialog();
                },
              ),
              _buildOptionItem(
                icon: Icons.login_rounded,
                title: '加入房间',
                color: Colors.green,
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  _showJoinRoomDialog();
                },
              ),
              _buildOptionItem(
                icon: Icons.lock_reset,
                title: '修改密码',
                color: Colors.blue,
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  _showChangePasswordDialog();
                },
              ),
              if (isAdmin)
                _buildOptionItem(
                  icon: Icons.admin_panel_settings,
                  title: '管理员设置',
                  color: Colors.orange,
                  isDark: isDark,
                  onTap: () {
                    Navigator.pop(context);
                    _showAdminSettingsDialog();
                  },
                ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOptionItem({
    required IconData icon,
    required String title,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF7F7FC),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadRooms(silent: true);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildAppBar(),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: _isLoading
                  ? const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : !_isLoggedIn
                      ? SliverFillRemaining(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 40,
                                  backgroundColor: const Color(0xFFE0E0FF),
                                  backgroundImage: const AssetImage('assets/icon/robot_3.png'),
                                  child: Container(),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '请先登录以使用功能',
                                  style: TextStyle(
                                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton.icon(
                                  onPressed: _showLoginDialog,
                                  icon: const Icon(Icons.login),
                                  label: const Text('立即登录'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF5D5FEF),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _rooms.isEmpty
                    ? SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 40,
                                backgroundColor: const Color(0xFFE0E0FF),
                                backgroundImage: const AssetImage('assets/icon/robot_3.png'),
                                child: Container(),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '暂无房间，快去创建一个吧！',
                                style: TextStyle(
                                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () => _loadRooms(silent: false),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF5D5FEF),
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('刷新列表'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.8,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _buildRoomCard(_rooms[index], index),
                          childCount: _rooms.length,
                        ),
                      ),
          ),
        ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showOptionsBottomSheet,
        child: const Icon(Icons.add),
        backgroundColor: const Color(0xFF5D5FEF),
      ),
    );
  }

  Widget _buildAppBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SliverAppBar(
      expandedHeight: 120,
      pinned: true,
      elevation: 0,
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF7F7FC),
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
        title: GestureDetector(
          onLongPress: _showServerSettingsDialog,
          child: Text(
            '一起看',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 32, // Magnified as requested
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
        ),
        background: Container(
          color: isDark ? const Color(0xFF121212) : const Color(0xFFF7F7FC),
          child: Stack(
            children: [
              Positioned(
                right: -40,
                top: -40,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF5D5FEF).withOpacity(0.03),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showServerSettingsDialog() {
    final controller = TextEditingController(text: WatchTogetherService.baseUrl);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    ChatUtils.showStyledDialog(
      context: context,
      title: '服务器设置',
      icon: const Icon(Icons.dns_rounded, color: Color(0xFF5D5FEF)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            style: TextStyle(color: textColor),
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: '例如: https://sso.lhht.cc/api',
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

  Future<void> _handleJoinRoom(WRoom room) async {
    if (room.needPassword) {
      final passwordController = TextEditingController();
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final textColor = isDark ? Colors.white : Colors.black87;

      final password = await ChatUtils.showStyledDialog<String>(
        context: context,
        title: '输入房间密码',
        icon: const Icon(Icons.lock),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          style: TextStyle(color: textColor),
          decoration: const InputDecoration(
            labelText: '密码',
            prefixIcon: Icon(Icons.key),
            border: OutlineInputBorder(),
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
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => WatchTogetherRoomScreen(room: room),
            ),
          );
        }
      } catch (e) {
        if (mounted) MessageUtils.showError(context, '加入房间失败: $e');
      }
    } else {
      try {
        await WatchTogetherService.joinRoom(room.roomId, '');
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => WatchTogetherRoomScreen(room: room),
            ),
          );
        }
      } catch (e) {
        if (mounted) MessageUtils.showError(context, '加入房间失败: $e');
      }
    }
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

  Widget _buildRoomCard(WRoom room, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;
    final cardColor = isDark ? const Color(0xFF2C2C2C) : _cardColors[index % _cardColors.length];
    final accentColor = isDark ? Colors.white24 : Colors.black.withOpacity(0.05);

    // Determine tag
    String tagText = '';
    Color tagColor = Colors.transparent;
    Color tagTextColor = Colors.white;

    if (room.hidden) {
      tagText = '隐藏';
      tagColor = Colors.grey.shade600;
    } else {
      tagText = '公开';
      tagColor = const Color(0xFF5D5FEF);
    }

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: isDark 
              ? Colors.black.withOpacity(0.3)
              : Colors.grey.withOpacity(0.1),
            blurRadius: isDark ? 8 : 12,
            spreadRadius: 0,
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
            // Decorative background circle
            Positioned(
              right: -20,
              top: -20,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor,
                ),
              ),
            ),
            // Tag
            if (tagText.isNotEmpty)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: tagColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tagText,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: tagTextColor,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.movie_filter_rounded,
                              color: Color(0xFF5D5FEF),
                              size: 24,
                            ),
                          ),
                          if (room.needPassword)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.lock, size: 14, color: Colors.black54),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        room.roomName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: textColor,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.group_rounded, size: 14, color: Colors.grey[700]),
                            const SizedBox(width: 4),
                            Text(
                              '${room.viewerCount}人',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[800]),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: Color(0xFF5D5FEF),
                        ),
                      ),
                    ],
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

class LoginDialog extends StatefulWidget {
  const LoginDialog({super.key});

  @override
  State<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.maxFinite,
      height: 320,
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF5D5FEF),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF5D5FEF),
            tabs: const [
              Tab(text: '登录'),
              Tab(text: '注册'),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildForm('登录'),
                _buildForm('注册'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(String buttonText) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Column(
      children: [
        TextField(
          controller: _usernameController,
          style: TextStyle(color: textColor),
          decoration: const InputDecoration(
            labelText: '用户名',
            labelStyle: TextStyle(color: Colors.grey),
            prefixIcon: Icon(Icons.person_outline, color: Colors.grey),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF5D5FEF))),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          style: TextStyle(color: textColor),
          decoration: const InputDecoration(
            labelText: '密码',
            labelStyle: TextStyle(color: Colors.grey),
            prefixIcon: Icon(Icons.lock_outline, color: Colors.grey),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF5D5FEF))),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5D5FEF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(buttonText, style: const TextStyle(fontSize: 16)),
                ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final username = _usernameController.text;
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      MessageUtils.showWarning(context, '请输入用户名和密码');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_tabController.index == 0) {
        // Login
        await WatchTogetherService.login(username, password);
        Navigator.pop(context, true);
      } else {
        // Register
        await WatchTogetherService.register(username, password);
        // Auto login after register
        await WatchTogetherService.login(username, password);
        Navigator.pop(context, true);
      }
    } catch (e) {
      MessageUtils.showError(context, '操作失败: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
}
