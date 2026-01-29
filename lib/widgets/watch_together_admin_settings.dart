import 'package:flutter/material.dart';
import 'package:synctv_app/services/watch_together_service.dart';
import 'package:synctv_app/models/watch_together_models.dart';
import 'package:synctv_app/utils/message_utils.dart';
import 'package:synctv_app/utils/chat_utils.dart';
import 'package:synctv_app/widgets/ios_style_switch.dart';    

class AdminSettingsDialog extends StatefulWidget {
  const AdminSettingsDialog({super.key});

  @override
  State<AdminSettingsDialog> createState() => _AdminSettingsDialogState();
}

class _AdminSettingsDialogState extends State<AdminSettingsDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      height: 500,
      width: double.maxFinite,
      child: ScaffoldMessenger(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
            padding: const EdgeInsets.all(4),
            child: TabBar(
              controller: _tabController,
              labelColor: isDark ? Colors.white : theme.primaryColor,
              unselectedLabelColor: theme.hintColor,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isDark ? theme.cardColor : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: EdgeInsets.zero,
              tabs: const [
                Tab(text: '房间管理'),
                Tab(text: '用户管理'),
                Tab(text: '用户设置'),
                Tab(text: '房间设置'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                RoomManagementTab(),
                UserManagementTab(),
                UserSettingsTab(),
                RoomSettingsTab(),
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


class RoomManagementTab extends StatefulWidget {
  const RoomManagementTab({super.key});

  @override
  State<RoomManagementTab> createState() => _RoomManagementTabState();
}

class _RoomManagementTabState extends State<RoomManagementTab> {
  List<WRoom> _rooms = [];
  bool _isLoading = true;
  int _page = 1;
  int _max = 20;
  String _searchQuery = '';
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final data = await WatchTogetherService.adminGetRooms(
        page: _page,
        max: _max,
        search: _searchQuery,
        status: _statusFilter,
      );
      
      if (!mounted) return;
      
      final List list = data['list'] ?? [];
      setState(() {
        _rooms = list.map((e) => WRoom.fromJson(e)).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        MessageUtils.showError(context, '加载房间失败: $e');
      }
    }
  }

  Future<void> _banRoom(WRoom room, bool ban) async {
    final action = ban ? '封禁' : '解封';
    final confirm = await ChatUtils.showStyledDialog<bool>(
      context: context,
      title: '$action房间',
      icon: Icon(ban ? Icons.block : Icons.check_circle, color: ban ? Colors.red : Colors.green),
      content: Text('确定要$action房间 "${room.roomName}" 吗？'),
      actions: [
        ChatUtils.createCancelButton(context),
        const SizedBox(width: 8),
        ChatUtils.createConfirmButton(context, () => Navigator.pop(context, true), text: action),
      ],
    );

    if (confirm == true) {
      try {
        await WatchTogetherService.adminBanRoom(room.roomId, ban);
        MessageUtils.showSuccess(context, '操作成功');
        _loadRooms(silent: true);
      } catch (e) {
        MessageUtils.showError(context, '操作失败: $e');
      }
    }
  }

  Future<void> _deleteRoom(WRoom room) async {
    final confirm = await ChatUtils.showStyledDialog<bool>(
      context: context,
      title: '删除房间',
      icon: const Icon(Icons.delete_forever, color: Colors.red),
      content: Text('确定要删除房间 "${room.roomName}" 吗？此操作不可撤销。'),
      actions: [
        ChatUtils.createCancelButton(context),
        const SizedBox(width: 8),
        ChatUtils.createConfirmButton(context, () => Navigator.pop(context, true), text: '删除'),
      ],
    );

    if (confirm == true) {
      try {
        await WatchTogetherService.adminDeleteRoom(room.roomId);
        MessageUtils.showSuccess(context, '房间已删除');
        _loadRooms(silent: true);
      } catch (e) {
        MessageUtils.showError(context, '删除失败: $e');
      }
    }
  }

  String _getStatusText(int status) {
    switch (status) {
      case 1: return '已封禁';
      case 2: return '审核中';
      case 3: return '活跃';
      default: return '未知';
    }
  }

  Color _getStatusColor(int status) {
    switch (status) {
      case 1: return Colors.red;
      case 2: return Colors.orange;
      case 3: return Colors.green;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _buildStyledTextField(
                  onSubmitted: (val) {
                    setState(() {
                      _searchQuery = val;
                      _page = 1;
                    });
                    _loadRooms();
                  },
                  hint: '搜索房间',
                  icon: Icons.search,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _statusFilter,
                    hint: const Text('状态', style: TextStyle(fontSize: 14)),
                    icon: const Icon(Icons.arrow_drop_down, size: 20),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('全部')),
                      DropdownMenuItem(value: 'active', child: Text('活跃')),
                      DropdownMenuItem(value: 'pending', child: Text('审核中')),
                      DropdownMenuItem(value: 'banned', child: Text('已封禁')),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _statusFilter = val;
                        _page = 1;
                      });
                      _loadRooms();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _rooms.isEmpty
                  ? Center(child: Text('暂无房间', style: TextStyle(color: theme.hintColor)))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _rooms.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final room = _rooms[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          title: Text(room.roomName, style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(room.status).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: _getStatusColor(room.status)),
                                ),
                                child: Text(
                                  _getStatusText(room.status),
                                  style: TextStyle(fontSize: 10, color: _getStatusColor(room.status)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text('ID: ${room.roomId}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: theme.hintColor))),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (room.status != 1)
                                IconButton(
                                  icon: const Icon(Icons.block, size: 20),
                                  color: Colors.orange,
                                  tooltip: '封禁',
                                  onPressed: () => _banRoom(room, true),
                                )
                              else
                                IconButton(
                                  icon: const Icon(Icons.check_circle, size: 20),
                                  color: Colors.green,
                                  tooltip: '解封',
                                  onPressed: () => _banRoom(room, false),
                                ),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 20),
                                color: Colors.redAccent,
                                tooltip: '删除',
                                onPressed: () => _deleteRoom(room),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
  
  Widget _buildStyledTextField({
    required Function(String) onSubmitted,
    required String hint,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        onSubmitted: onSubmitted,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: theme.hintColor, size: 20),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          isDense: true,
        ),
      ),
    );
  }
}

class UserManagementTab extends StatefulWidget {
  const UserManagementTab({super.key});

  @override
  State<UserManagementTab> createState() => _UserManagementTabState();
}

class _UserManagementTabState extends State<UserManagementTab> {
  List<WUser> _users = [];
  bool _isLoading = true;
  int _page = 1;
  int _max = 20;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final data = await WatchTogetherService.adminGetUsers(
        page: _page,
        max: _max,
        search: _searchQuery,
      );
      
      if (!mounted) return;
      
      final List list = data['list'] ?? [];
      setState(() {
        _users = list.map((e) => WUser.fromJson(e)).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        MessageUtils.showError(context, '加载用户失败: $e');
      }
    }
  }

  Future<void> _addUser() async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    int role = 3; // Default User

    await ChatUtils.showStyledDialog(
      context: context,
      title: '新增用户',
      icon: const Icon(Icons.person_add, color: Color(0xFF5D5FEF)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: usernameController,
            decoration: const InputDecoration(labelText: '用户名'),
          ),
          TextField(
            controller: passwordController,
            decoration: const InputDecoration(labelText: '密码'),
            obscureText: true,
          ),
          DropdownButtonFormField<int>(
            value: role,
            decoration: const InputDecoration(labelText: '角色'),
            items: const [
              DropdownMenuItem(value: 3, child: Text('普通用户')),
              DropdownMenuItem(value: 4, child: Text('管理员')),
            ],
            onChanged: (val) => role = val!,
          ),
        ],
      ),
      actions: [
        ChatUtils.createCancelButton(context),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () async {
            if (usernameController.text.isEmpty || passwordController.text.isEmpty) {
              MessageUtils.showWarning(context, '请填写完整信息');
              return;
            }
            try {
              await WatchTogetherService.adminAddUser(
                usernameController.text,
                passwordController.text,
                role,
              );
              Navigator.pop(context);
              MessageUtils.showSuccess(context, '用户创建成功');
              _loadUsers(silent: true);
            } catch (e) {
              MessageUtils.showError(context, '创建失败: $e');
            }
          },
          child: const Text('创建'),
        ),
      ],
    );
  }

  Future<void> _deleteUser(WUser user) async {
    final confirm = await ChatUtils.showStyledDialog<bool>(
      context: context,
      title: '删除用户',
      icon: const Icon(Icons.warning, color: Colors.red),
      content: Text('确定要删除用户 "${user.username}" 吗？此操作不可撤销。'),
      actions: [
        ChatUtils.createCancelButton(context),
        const SizedBox(width: 8),
        ChatUtils.createConfirmButton(context, () => Navigator.pop(context, true), text: '删除'),
      ],
    );

    if (confirm == true) {
      try {
        await WatchTogetherService.adminDeleteUser(user.id);
        MessageUtils.showSuccess(context, '用户已删除');
        _loadUsers(silent: true);
      } catch (e) {
        MessageUtils.showError(context, '删除失败: $e');
      }
    }
  }

  Future<void> _toggleAdmin(WUser user) async {
    final isAdmin = user.role >= 4;
    final action = isAdmin ? '取消管理员' : '设为管理员';
    
    final confirm = await ChatUtils.showStyledDialog<bool>(
      context: context,
      title: '修改权限',
      icon: const Icon(Icons.admin_panel_settings, color: Color(0xFF5D5FEF)),
      content: Text('确定要将用户 "${user.username}" $action 吗？'),
      actions: [
        ChatUtils.createCancelButton(context),
        const SizedBox(width: 8),
        ChatUtils.createConfirmButton(context, () => Navigator.pop(context, true), text: '确定'),
      ],
    );

    if (confirm == true) {
      try {
        await WatchTogetherService.adminSetAdmin(user.id, !isAdmin);
        MessageUtils.showSuccess(context, '操作成功');
        _loadUsers(silent: true);
      } catch (e) {
        MessageUtils.showError(context, '操作失败: $e');
      }
    }
  }

  Future<void> _approveUser(WUser user) async {
    try {
      await WatchTogetherService.adminApproveUser(user.id);
      MessageUtils.showSuccess(context, '用户已通过审核');
      _loadUsers(silent: true);
    } catch (e) {
      MessageUtils.showError(context, '操作失败: $e');
    }
  }

  Future<void> _banUser(WUser user, bool ban) async {
    final action = ban ? '封禁' : '解封';
    final confirm = await ChatUtils.showStyledDialog<bool>(
      context: context,
      title: '$action用户',
      icon: Icon(ban ? Icons.block : Icons.check_circle, color: ban ? Colors.red : Colors.green),
      content: Text('确定要$action用户 "${user.username}" 吗？'),
      actions: [
        ChatUtils.createCancelButton(context),
        const SizedBox(width: 8),
        ChatUtils.createConfirmButton(context, () => Navigator.pop(context, true), text: '确定'),
      ],
    );

    if (confirm == true) {
      try {
        await WatchTogetherService.adminBanUser(user.id, ban);
        MessageUtils.showSuccess(context, '操作成功');
        _loadUsers(silent: true);
      } catch (e) {
        MessageUtils.showError(context, '操作失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _buildStyledTextField(
                  onSubmitted: (val) {
                    setState(() {
                      _searchQuery = val;
                      _page = 1;
                    });
                    _loadUsers();
                  },
                  hint: '搜索用户',
                  icon: Icons.search,
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: theme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _addUser,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.add_circle_rounded, color: theme.primaryColor, size: 20),
                        const SizedBox(width: 4),
                        Text('新增', style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _users.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    final isAdmin = user.role >= 4;
                    // Role: 1=Banned, 2=Pending, 3=User, 4=Admin
                    
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: isAdmin ? Colors.amber.withOpacity(0.2) : Colors.blue.withOpacity(0.1),
                        child: Text(
                          user.username.isNotEmpty ? user.username.substring(0, 1).toUpperCase() : '?',
                          style: TextStyle(
                            color: isAdmin ? Colors.amber.shade800 : Colors.blue.shade800,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      title: Text(user.username, style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text('ID: ${user.id} · Role: ${user.role}', style: TextStyle(fontSize: 10, color: theme.hintColor)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (user.role == 2) ...[ // Pending
                            IconButton(
                              icon: const Icon(Icons.check_circle, size: 20),
                              color: Colors.green,
                              tooltip: '通过注册',
                              onPressed: () => _approveUser(user),
                            ),
                            IconButton(
                              icon: const Icon(Icons.block, size: 20),
                              color: Colors.red,
                              tooltip: '禁止注册',
                              onPressed: () => _banUser(user, true),
                            ),
                          ] else if (user.role == 1) ...[ // Banned
                            IconButton(
                              icon: const Icon(Icons.check_circle, size: 20),
                              color: Colors.orange,
                              tooltip: '解封',
                              onPressed: () => _banUser(user, false),
                            ),
                          ] else ...[ // Active (3, 4, 5)
                            IconButton(
                              icon: const Icon(Icons.block, size: 20),
                              color: Colors.redAccent,
                              tooltip: '封禁',
                              onPressed: () => _banUser(user, true),
                            ),
                            IconButton(
                              icon: Icon(
                                isAdmin ? Icons.remove_moderator : Icons.add_moderator,
                                size: 20,
                              ),
                              color: isAdmin ? Colors.orange : Colors.blue,
                              tooltip: isAdmin ? '取消管理员' : '设为管理员',
                              onPressed: () => _toggleAdmin(user),
                            ),
                          ],
                          IconButton(
                            icon: const Icon(Icons.delete, size: 20),
                            color: Colors.redAccent,
                            tooltip: '删除用户',
                            onPressed: () => _deleteUser(user),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
  
  Widget _buildStyledTextField({
    required Function(String) onSubmitted,
    required String hint,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        onSubmitted: onSubmitted,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: theme.hintColor, size: 20),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          isDense: true,
        ),
      ),
    );
  }
}

// --- User Settings Tab ---

class UserSettingsTab extends StatefulWidget {
  const UserSettingsTab({super.key});

  @override
  State<UserSettingsTab> createState() => _UserSettingsTabState();
}

class _UserSettingsTabState extends State<UserSettingsTab> with AutomaticKeepAliveClientMixin {
  bool _isLoading = true;
  Map<String, dynamic> _settings = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final data = await WatchTogetherService.adminGetSettings('user');
      if (mounted) {
        setState(() {
          _settings = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        MessageUtils.showError(context, '加载设置失败: $e');
      }
    }
  }

  Future<void> _updateSetting(String key, dynamic value) async {
    try {
      // Optimistic update
      setState(() {
        _settings[key] = value;
      });
      await WatchTogetherService.adminUpdateSetting(key, value);
    } catch (e) {
      // Revert on failure
      if (mounted) MessageUtils.showError(context, '更新设置失败: $e');
      _loadSettings(); // Reload to sync
    }
  }

  Widget _buildSwitch(String key, String title) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          IOSStyleSwitch(
            value: _settings[key] ?? false,
            onChanged: (val) => _updateSetting(key, val),
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildNumberInput(String key, String title, String suffix) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        trailing: Container(
          width: 100,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.2) : Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextFormField(
            initialValue: (_settings[key] ?? 0).toString(),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              suffixText: suffix,
              isDense: true,
              border: InputBorder.none,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              hintText: '0',
            ),
            onFieldSubmitted: (val) {
              final numVal = int.tryParse(val);
              if (numVal != null) {
                _updateSetting(key, numVal);
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      children: [
        _buildSwitch('enable_guest', '允许访客用户'),
        _buildSwitch('disable_user_signup', '禁止用户注册'),
        _buildNumberInput('user_max_room_count', '用户最大创建房间数', '个'),
        _buildSwitch('signup_need_review', '注册需要审核'),
        _buildSwitch('enable_password_signup', '允许用户使用密码注册'),
        _buildSwitch('password_signup_need_review', '密码注册需要审核'),
      ],
    );
  }
}

// --- Room Settings Tab ---

class RoomSettingsTab extends StatefulWidget {
  const RoomSettingsTab({super.key});

  @override
  State<RoomSettingsTab> createState() => _RoomSettingsTabState();
}

class _RoomSettingsTabState extends State<RoomSettingsTab> with AutomaticKeepAliveClientMixin {
  bool _isLoading = true;
  Map<String, dynamic> _settings = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final data = await WatchTogetherService.adminGetSettings('room');
      if (mounted) {
        setState(() {
          _settings = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        MessageUtils.showError(context, '加载设置失败: $e');
      }
    }
  }

  Future<void> _updateSetting(String key, dynamic value) async {
    try {
      setState(() {
        _settings[key] = value;
      });
      await WatchTogetherService.adminUpdateSetting(key, value);
    } catch (e) {
      if (mounted) MessageUtils.showError(context, '更新设置失败: $e');
      _loadSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      children: [
        _buildNumberInput(
          'room_ttl',
          '非活跃房间回收时间',
          '小时',
          subtitle: '回收房间仅仅只是释放内存，而不是删除房间',
        ),
      ],
    );
  }

  Widget _buildNumberInput(String key, String title, String suffix, {String? subtitle}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: subtitle != null ? Text(subtitle, style: TextStyle(fontSize: 12, color: theme.hintColor)) : null,
        trailing: Container(
          width: 100,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.2) : Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextFormField(
            initialValue: (_settings[key] ?? 0).toString(),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              suffixText: suffix,
              isDense: true,
              border: InputBorder.none,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              hintText: '0',
            ),
            onFieldSubmitted: (val) {
              final numVal = int.tryParse(val);
              if (numVal != null) {
                _updateSetting(key, numVal);
              }
            },
          ),
        ),
      ),
    );
  }
}
