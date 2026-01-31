import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:synctv_app/models/watch_together_models.dart';
import 'package:synctv_app/services/watch_together_service.dart';
import 'package:synctv_app/pages/large_screen/large_screen_room.dart';
import 'package:synctv_app/utils/message_utils.dart';
import 'package:synctv_app/utils/chat_utils.dart';

class LargeScreenHome extends StatefulWidget {
  const LargeScreenHome({super.key});

  @override
  State<LargeScreenHome> createState() => _LargeScreenHomeState();
}

class _LargeScreenHomeState extends State<LargeScreenHome> {
  bool _isLoading = true;
  List<WRoom> _rooms = [];
  bool _isLoggedIn = false;
  WUser? _currentUser;
  StreamSubscription? _authErrorSubscription;
  final FocusNode _createRoomFocus = FocusNode();
  final FocusNode _refreshFocus = FocusNode();

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
    // Force landscape for TV
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
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
    _createRoomFocus.dispose();
    _refreshFocus.dispose();
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
        // Auto focus refresh button if no rooms or create room if rooms exist
        if (_rooms.isEmpty) {
          _refreshFocus.requestFocus();
        } else {
          _createRoomFocus.requestFocus();
        }
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
      icon: Icon(Icons.login, color: Theme.of(context).primaryColor),
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
      icon: Icon(Icons.add_box_outlined, color: Theme.of(context).primaryColor),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
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
        ChatUtils.createCancelButton(context),
        const SizedBox(width: 8),
        ChatUtils.createConfirmButton(
          context,
          () async {
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
          text: '创建',
        ),
      ],
    );
  }

  void _showServerSettingsDialog() {
    final controller = TextEditingController(text: WatchTogetherService.baseUrl);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    ChatUtils.showStyledDialog(
      context: context,
      title: '服务器设置',
      icon: Icon(Icons.dns_rounded, color: Theme.of(context).primaryColor),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
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
        ChatUtils.createCancelButton(context),
        const SizedBox(width: 8),
        ChatUtils.createConfirmButton(
          context,
          () async {
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
          text: '保存',
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
        ChatUtils.createCancelButton(context),
        const SizedBox(width: 8),
        ChatUtils.createConfirmButton(
          context,
          () => Navigator.pop(context, true),
          text: '退出',
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
    if (room.needPassword) {
      final passwordController = TextEditingController();
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final textColor = isDark ? Colors.white : Colors.black87;

      final password = await ChatUtils.showStyledDialog<String>(
        context: context,
        title: '输入房间密码',
        icon: Icon(Icons.lock, color: Theme.of(context).primaryColor),
        content: SizedBox(
          width: 300,
          child: TextField(
            controller: passwordController,
            autofocus: true,
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
          ChatUtils.createCancelButton(context),
          const SizedBox(width: 8),
          ChatUtils.createConfirmButton(
            context,
            () => Navigator.pop(context, passwordController.text),
            text: '确定',
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
        builder: (context) => LargeScreenRoom(room: room),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          // Top Header
          Container(
            height: 80,
            padding: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: theme.appBarTheme.backgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Logo & Name
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
                
                const Spacer(),
                
                // Server Settings
                IconButton(
                  icon: const Icon(Icons.dns_rounded),
                  onPressed: _showServerSettingsDialog,
                  tooltip: '服务器设置',
                ),
                const SizedBox(width: 8),
                
                // Refresh
                IconButton(
                  focusNode: _refreshFocus,
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => _loadRooms(silent: false),
                  tooltip: '刷新',
                ),
                const SizedBox(width: 24),
                
                // User Avatar (Login/Logout)
                if (_isLoggedIn && _currentUser != null)
                  InkWell(
                    onTap: _handleLogout,
                    borderRadius: BorderRadius.circular(50),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(0xFF5D5FEF),
                            child: Text(
                              _currentUser!.username.isNotEmpty ? _currentUser!.username[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _currentUser!.username,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _showLoginDialog,
                    icon: const Icon(Icons.login),
                    label: const Text('登录'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),

                const SizedBox(width: 24),
                
                // Create Room Button
                ElevatedButton.icon(
                  onPressed: _showCreateRoomDialog,
                  focusNode: _createRoomFocus,
                  icon: const Icon(Icons.add),
                  label: const Text('创建房间'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5D5FEF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : !_isLoggedIn
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.tv, size: 120, color: Colors.grey.withOpacity(0.5)),
                            const SizedBox(height: 24),
                            Text(
                              '请登录以开始观看',
                              style: TextStyle(
                                fontSize: 24,
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 32),
                            ElevatedButton.icon(
                              onPressed: _showLoginDialog,
                              icon: const Icon(Icons.login),
                              label: const Text('登录'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                textStyle: const TextStyle(fontSize: 18),
                              ),
                            ),
                          ],
                        ),
                      )
                    : _rooms.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.weekend_rounded, size: 120, color: Colors.grey.withOpacity(0.5)),
                                const SizedBox(height: 24),
                                const Text(
                                  '暂无房间，去创建一个吧',
                                  style: TextStyle(fontSize: 24, color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(32),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 400,
                              childAspectRatio: 1.6, // Wider cards for TV
                              crossAxisSpacing: 24,
                              mainAxisSpacing: 24,
                            ),
                            itemCount: _rooms.length,
                            itemBuilder: (context, index) => _buildRoomCard(_rooms[index], index),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomCard(WRoom room, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.black : _cardColors[index % _cardColors.length];
    
    return Focus(
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () => _handleJoinRoom(room),
            child: Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(24),
                border: hasFocus 
                    ? Border.all(color: const Color(0xFF5D5FEF), width: 4) 
                    : (isDark ? Border.all(color: Colors.white24, width: 1) : null),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(hasFocus ? 0.2 : 0.05),
                    blurRadius: hasFocus ? 16 : 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -20,
                    bottom: -20,
                    child: Icon(
                      Icons.tv,
                      size: 180,
                      color: Colors.white.withOpacity(0.05),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: room.hidden ? Colors.grey : const Color(0xFF5D5FEF),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                room.hidden ? '隐藏' : '公开',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (room.needPassword)
                              const Icon(Icons.lock, color: Colors.white54),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          room.roomName,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.person, size: 16, color: isDark ? Colors.white60 : Colors.black54),
                            const SizedBox(width: 8),
                            Text(
                              '${room.viewerCount} 人在线',
                              style: TextStyle(
                                fontSize: 16,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Icon(Icons.admin_panel_settings, size: 16, color: isDark ? Colors.white60 : Colors.black54),
                            const SizedBox(width: 8),
                            Text(
                              room.creator,
                              style: TextStyle(
                                fontSize: 16,
                                color: isDark ? Colors.white60 : Colors.black54,
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
          );
        }
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
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _usernameController,
            autofocus: true,
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
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ChatUtils.createConfirmButton(
                    context,
                    _handleSubmit,
                    text: _isRegistering ? '注册' : '登录',
                  ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              setState(() {
                _isRegistering = !_isRegistering;
              });
            },
            child: Text(_isRegistering ? '已有账号？去登录' : '没有账号？去注册', style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
