import 'package:flutter/material.dart';
import 'package:synctv_app/services/watch_together_service.dart';
import 'package:synctv_app/utils/message_utils.dart';
import 'package:synctv_app/utils/chat_utils.dart';

class PlatformBindingDialog extends StatefulWidget {
  final int initialIndex;

  const PlatformBindingDialog({super.key, this.initialIndex = 0});

  static Future<void> show(BuildContext context, {int initialIndex = 0}) {
    return ChatUtils.showStyledDialog(
      context: context,
      title: '账号绑定',
      icon: const Icon(Icons.link_rounded, color: Color(0xFF5D5FEF)),
      content: PlatformBindingDialog(initialIndex: initialIndex),
      actions: [],
    );
  }

  @override
  State<PlatformBindingDialog> createState() => _PlatformBindingDialogState();
}

class _PlatformBindingDialogState extends State<PlatformBindingDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Alist State
  List<Map<String, dynamic>> _alistBinds = [];
  bool _alistLoading = true;
  
  // Emby State
  List<Map<String, dynamic>> _embyBinds = [];
  bool _embyLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialIndex);
    _loadAListBinds();
    _loadEmbyBinds();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAListBinds({bool showLoading = true}) async {
    if (!mounted) return;
    if (showLoading) setState(() => _alistLoading = true);
    try {
      final list = await WatchTogetherService.getAListBindsList();
      if (mounted) setState(() => _alistBinds = list);
    } catch (e) {
      if (mounted && showLoading) MessageUtils.showError(context, '获取 Alist 绑定失败: $e');
    } finally {
      if (mounted && showLoading) setState(() => _alistLoading = false);
    }
  }

  Future<void> _loadEmbyBinds({bool showLoading = true}) async {
    if (!mounted) return;
    if (showLoading) setState(() => _embyLoading = true);
    try {
      final list = await WatchTogetherService.getEmbyBindsList();
      if (mounted) setState(() => _embyBinds = list);
    } catch (e) {
      if (mounted && showLoading) MessageUtils.showError(context, '获取 Emby 绑定失败: $e');
    } finally {
      if (mounted && showLoading) setState(() => _embyLoading = false);
    }
  }

  Future<void> _unbindAList(String serverId) async {
    final confirm = await ChatUtils.showStyledDialog<bool>(
      context: context,
      title: '确认解绑',
      icon: const Icon(Icons.delete_outline, color: Colors.red),
      content: const Text('确定要解除此 Alist 账号绑定吗？'),
      actions: [
        ChatUtils.createCancelButton(context),
        const SizedBox(width: 8),
        ChatUtils.createConfirmButton(context, () => Navigator.pop(context, true), text: '解绑'),
      ],
    );
    
    if (confirm != true) return;

    // Optimistic UI update: Remove item immediately
    if (mounted) {
      setState(() {
        _alistBinds.removeWhere((item) => item['serverId'].toString() == serverId);
      });
    }

    try {
      await WatchTogetherService.logoutAList(serverId);
      if (!mounted) return;
      
      MessageUtils.showSuccess(context, '解绑成功');
      await _loadAListBinds(showLoading: false);
    } catch (e) {
      if (mounted) {
        MessageUtils.showError(context, '解绑失败: $e');
        await _loadAListBinds(showLoading: false);
      }
    }
  }

  Future<void> _unbindEmby(String serverId) async {
    final confirm = await ChatUtils.showStyledDialog<bool>(
      context: context,
      title: '确认解绑',
      icon: const Icon(Icons.delete_outline, color: Colors.red),
      content: const Text('确定要解除此 Emby 账号绑定吗？'),
      actions: [
        ChatUtils.createCancelButton(context),
        const SizedBox(width: 8),
        ChatUtils.createConfirmButton(context, () => Navigator.pop(context, true), text: '解绑'),
      ],
    );
    
    if (confirm != true) return;

    if (mounted) {
      setState(() {
        _embyBinds.removeWhere((item) => item['serverId'].toString() == serverId);
      });
    }

    try {
      await WatchTogetherService.logoutEmby(serverId);
      if (!mounted) return;
      
      MessageUtils.showSuccess(context, '解绑成功');
      await _loadEmbyBinds(showLoading: false);
    } catch (e) {
      if (mounted) {
        MessageUtils.showError(context, '解绑失败: $e');
        await _loadEmbyBinds(showLoading: false);
      }
    }
  }

  void _showAddAListDialog() {
    ChatUtils.showStyledDialog(
      context: context,
      title: '登录 AList',
      icon: const Icon(Icons.cloud_circle_rounded, color: Colors.amber),
      content: _AddAccountDialog(
        type: 'alist',
        onSuccess: () {
          _loadAListBinds(showLoading: false);
        },
      ),
      actions: [],
    );
  }

  void _showAddEmbyDialog() {
    ChatUtils.showStyledDialog(
      context: context,
      title: '登录 Emby',
      icon: const Icon(Icons.video_library_rounded, color: Colors.green),
      content: _AddAccountDialog(
        type: 'emby',
        onSuccess: () {
          _loadEmbyBinds(showLoading: false);
        },
      ),
      actions: [],
    );
  }

  void _showAListInfo(String serverId) async {
    try {
      final info = await WatchTogetherService.getAListAccountInfo(serverId);
      if (!mounted) return;
      ChatUtils.showStyledDialog(
        context: context,
        title: '账号详情',
        icon: const Icon(Icons.info_outline, color: Color(0xFF5D5FEF)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${info['id'] ?? ''}'),
            const SizedBox(height: 8),
            Text('用户名: ${info['username'] ?? ''}'),
            const SizedBox(height: 8),
            Text('权限: ${info['permission'] ?? ''}'),
            const SizedBox(height: 8),
            Text('根目录: ${info['basePath'] ?? ''}'),
          ],
        ),
        actions: [
          ChatUtils.createConfirmButton(context, () => Navigator.pop(context), text: '关闭'),
        ],
      );
    } catch (e) {
      if (mounted) MessageUtils.showError(context, '获取详情失败: $e');
    }
  }

  void _showEmbyInfo(String serverId) async {
    try {
      final info = await WatchTogetherService.getEmbyAccountInfo(serverId);
      if (!mounted) return;
      ChatUtils.showStyledDialog(
        context: context,
        title: '账号详情',
        icon: const Icon(Icons.info_outline, color: Color(0xFF5D5FEF)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${info['Id'] ?? info['id'] ?? ''}'),
            const SizedBox(height: 8),
            Text('用户名: ${info['Name'] ?? info['name'] ?? ''}'),
            const SizedBox(height: 8),
            Text('服务器: ${info['ServerId'] ?? serverId}'),
          ],
        ),
        actions: [
          ChatUtils.createConfirmButton(context, () => Navigator.pop(context), text: '关闭'),
        ],
      );
    } catch (e) {
      if (mounted) MessageUtils.showError(context, '获取详情失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return SizedBox(
      height: 400, // Limit height naturally
      width: double.maxFinite,
      child: Column(
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
              tabs: const [
                Tab(text: 'Alist 网盘'),
                Tab(text: 'Emby 媒体库'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildList(_alistBinds, _alistLoading, 'Alist', _unbindAList, _showAddAListDialog, _showAListInfo),
                _buildList(_embyBinds, _embyLoading, 'Emby', _unbindEmby, _showAddEmbyDialog, _showEmbyInfo),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    List<Map<String, dynamic>> items, 
    bool isLoading, 
    String type,
    Function(String) onUnbind,
    VoidCallback onAdd,
    Function(String)? onInfo,
  ) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Column(
      children: [
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        type == 'Alist' ? Icons.cloud_off_rounded : Icons.videocam_off_rounded,
                        size: 48,
                        color: theme.disabledColor.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text('暂无绑定的 $type 账号', style: TextStyle(color: theme.hintColor)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final serverId = item['serverId']?.toString() ?? '';
                    final host = item['host']?.toString() ?? '';
                    
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: type == 'Alist' ? Colors.amber.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          type == 'Alist' ? Icons.cloud_circle_rounded : Icons.video_library_rounded,
                          color: type == 'Alist' ? Colors.amber : Colors.green,
                        ),
                      ),
                      title: Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text('ID: $serverId', style: TextStyle(fontSize: 10, color: theme.hintColor)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (onInfo != null)
                            IconButton(
                              icon: const Icon(Icons.info_outline, size: 20),
                              onPressed: () => onInfo(serverId),
                              tooltip: '详情',
                              color: theme.primaryColor,
                            ),
                          IconButton(
                            icon: const Icon(Icons.link_off_rounded, size: 20),
                            onPressed: () => onUnbind(serverId),
                            tooltip: '解绑',
                            color: Colors.redAccent,
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Center(
            child: Material(
              color: theme.primaryColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: onAdd,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_circle_rounded, color: theme.primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '添加 $type 账号',
                        style: TextStyle(
                          color: theme.primaryColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddAccountDialog extends StatefulWidget {
  final String type; // 'alist' or 'emby'
  final VoidCallback onSuccess;

  const _AddAccountDialog({required this.type, required this.onSuccess});

  @override
  State<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<_AddAccountDialog> {
  final _hostController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _hostController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final host = _hostController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (host.isEmpty || username.isEmpty || password.isEmpty) {
      MessageUtils.showError(context, '请填写完整信息');
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (widget.type == 'alist') {
        await WatchTogetherService.loginAList(host, username, password);
      } else {
        await WatchTogetherService.loginEmby(host, username, password);
      }
      if (mounted) {
        Navigator.pop(context);
        MessageUtils.showSuccess(context, '绑定成功');
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) MessageUtils.showError(context, '绑定失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildStyledTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    bool obscureText = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: TextField(
          controller: controller,
          obscureText: obscureText,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAlist = widget.type == 'alist';
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            if (isAlist)
               Container(
                 margin: const EdgeInsets.only(bottom: 20),
                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                 decoration: BoxDecoration(
                   color: Colors.amber.withOpacity(0.1),
                   borderRadius: BorderRadius.circular(8),
                 ),
                 child: Row(
                   children: [
                     const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber),
                     const SizedBox(width: 8),
                     const Text('注意：仅支持3.25.0及以上版本', style: TextStyle(fontSize: 12, color: Colors.amber)),
                   ],
                 ),
               ),
            
            _buildStyledTextField(
              controller: _hostController,
              label: '${isAlist ? "AList" : "Emby"} 地址',
              hint: 'https://example.com',
              icon: Icons.link_rounded,
            ),
            const SizedBox(height: 16),
            
            _buildStyledTextField(
              controller: _usernameController,
              label: '用户名',
              icon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: 16),
            
            _buildStyledTextField(
              controller: _passwordController,
              label: '密码',
              icon: Icons.lock_outline_rounded,
              obscureText: true,
            ),
            
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ChatUtils.createCancelButton(context),
                const SizedBox(width: 8),
                ChatUtils.createConfirmButton(
                  context, 
                  _submit, 
                  text: '登录',
                ),
              ],
            ),
        ],
      ),
    );
  }
}
