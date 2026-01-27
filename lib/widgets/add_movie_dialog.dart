import 'package:flutter/material.dart';
import 'package:synctv_app/services/watch_together_service.dart';
import 'package:synctv_app/utils/message_utils.dart';
import 'package:synctv_app/utils/chat_utils.dart';
import 'package:synctv_app/widgets/ios_style_switch.dart';
import 'platform_binding_dialog.dart';

class AddMovieDialog extends StatefulWidget {
  final String roomId;
  final String? parentId;

  const AddMovieDialog({super.key, required this.roomId, this.parentId});

  static Future<void> show(BuildContext context, String roomId, {String? parentId}) {
    return ChatUtils.showStyledDialog(
      context: context,
      title: '添加影片',
      icon: const Icon(Icons.add_to_queue, color: Color(0xFF5D5FEF)),
      content: AddMovieDialog(roomId: roomId, parentId: parentId),
      actions: [],
    );
  }

  @override
  State<AddMovieDialog> createState() => _AddMovieDialogState();
}

class _AddMovieDialogState extends State<AddMovieDialog> {
  // Navigation: -1 = Menu, 0 = Link, 1 = Bilibili, 2 = Alist, 3 = Emby
  int _selectedIndex = -1;

  // Controllers
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  final _biliUrlController = TextEditingController();
  
  // State variables
  bool _isLive = false;
  bool _isProxy = false;
  bool _isLoading = false;
  
  // Bilibili
  Map<String, dynamic>? _biliInfo;
  
  // Alist / Emby
  String _alistPath = '/';
  List<dynamic> _alistFiles = [];
  bool _alistLoading = false;
  int _alistPage = 1;
  bool _alistHasMore = true;
  static const int _pageSize = 20;
  final Map<String, dynamic> _selectedAlistItems = {};
  
  String _embyPath = '/';
  List<dynamic> _embyFiles = [];
  bool _embyLoading = false;
  
  List<String> _boundVendors = [];
  bool _checkingVendors = true;

  @override
  void initState() {
    super.initState();
    _checkVendors();
  }

  Future<void> _checkVendors() async {
    final vendors = await WatchTogetherService.getBoundVendors();
    if (mounted) {
      setState(() {
        _boundVendors = vendors;
        _checkingVendors = false;
      });
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _biliUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final contentWidth = size.width > 600 ? 560.0 : size.width * 0.9 - 40;

    return SizedBox(
      width: contentWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min, // Wrap content height
        children: [
          if (_selectedIndex != -1)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => setState(() => _selectedIndex = -1),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.arrow_back_rounded, size: 22, color: theme.primaryColor),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    _getTitle(_selectedIndex),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  if ((_selectedIndex == 2 && _boundVendors.contains('alist')) || 
                      (_selectedIndex == 3 && _boundVendors.contains('emby'))) ...[
                    const Spacer(),
                    IconButton(
                      onPressed: () async {
                        await PlatformBindingDialog.show(
                          context, 
                          initialIndex: _selectedIndex == 2 ? 0 : 1
                        );
                        // Refresh vendors and reload content if needed
                        await _checkVendors();
                        if (mounted) {
                          if (_selectedIndex == 2) _loadAlist(_alistPath);
                          if (_selectedIndex == 3) _loadEmby(_embyPath);
                        }
                      },
                      icon: Icon(Icons.settings_rounded, color: theme.hintColor),
                      tooltip: '管理配置',
                    ),
                  ],
                ],
              ),
            ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _selectedIndex == -1
                  ? _buildMenu(theme, contentWidth)
                  : SizedBox(
                      height: 450, // Fixed height for content views to ensure scrolling space
                      child: _buildContent(theme),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _getTitle(int index) {
    switch (index) {
      case 0: return '直链 / 直播流';
      case 1: return 'Bilibili';
      case 2: return 'Alist 网盘';
      case 3: return 'Emby 媒体库';
      default: return '';
    }
  }

  Widget _buildMenu(ThemeData theme, double dialogWidth) {
    // Reduce padding to maximize card width
    // Dialog itself has 20px padding, so we don't need huge padding here
    const double gridPadding = 4.0; 
    const double spacing = 16.0;
    
    // Calculate aspect ratio dynamically
    // Available width = Total Width - Horizontal Padding - Cross Axis Spacing
    final double itemWidth = (dialogWidth - (gridPadding * 2) - spacing) / 2;
    
    // Fixed height to ensure all content (Icon + Title + Subtitle + Spacing) fits comfortably
    // Icon(70 container) + Spacing(20) + Title(45) + Spacing(8) + Subtitle(40) + Padding(40) = ~223
    const double itemHeight = 240.0;
    
    final double ratio = itemWidth / itemHeight;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(gridPadding),
      crossAxisCount: 2,
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      childAspectRatio: ratio,
      children: [
        _buildGridMenuItem(
          0,
          '直链 / 直播流',
          '支持 HTTP/HLS/RTMP',
          Icons.link_rounded,
          const Color(0xFF5D5FEF),
          theme,
        ),
        _buildGridMenuItem(
          1,
          'Bilibili',
          '支持 BV / 链接解析',
          Icons.tv_rounded,
          const Color(0xFFFB7299),
          theme,
        ),
        _buildGridMenuItem(
          2,
          'Alist 网盘',
          '挂载的云盘资源',
          Icons.cloud_circle_rounded,
          Colors.amber.shade700,
          theme,
        ),
        _buildGridMenuItem(
          3,
          'Emby 媒体库',
          '个人媒体服务器',
          Icons.video_library_rounded,
          Colors.green.shade600,
          theme,
        ),
      ],
    );
  }

  Widget _buildGridMenuItem(int index, String title, String subtitle, IconData icon, Color color, ThemeData theme) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedIndex = index;
          if (index == 1 || index == 2) { // Bilibili or Alist
            _isProxy = true;
          } else {
            _isProxy = false;
          }
        });
        if (index == 2 && _alistFiles.isEmpty) _loadAlist('/');
        if (index == 3 && _embyFiles.isEmpty) _loadEmby('/');
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: theme.dividerColor.withOpacity(0.05)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: theme.hintColor),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    switch (_selectedIndex) {
      case 0: return _buildDirectLinkContent(theme);
      case 1: return _buildBilibiliContent(theme);
      case 2: return _buildAlistContent(theme);
      case 3: return _buildEmbyContent(theme);
      default: return const SizedBox();
    }
  }

  Widget _buildDirectLinkContent(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _buildTextField(theme, _urlController, '视频链接', '请输入 http/https/rtmp 链接', Icons.link),
          const SizedBox(height: 16),
          _buildTextField(theme, _nameController, '视频名称 (可选)', '默认为文件名', Icons.title),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('是否为直播流', style: TextStyle(fontWeight: FontWeight.w500)),
                    IOSStyleSwitch(
                      value: _isLive,
                      onChanged: (val) => setState(() => _isLive = val),
                      isDark: theme.brightness == Brightness.dark,
                    ),
                  ],
                ),
                Divider(height: 16, color: theme.dividerColor.withOpacity(0.05)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('是否开启代理', style: TextStyle(fontWeight: FontWeight.w500)),
                    IOSStyleSwitch(
                      value: _isProxy,
                      onChanged: (val) => setState(() => _isProxy = val),
                      isDark: theme.brightness == Brightness.dark,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          _buildActionButton('立即添加', _addDirectLink),
        ],
      ),
    );
  }

  Widget _buildBilibiliContent(ThemeData theme) {
    List? videoInfos;
    if (_biliInfo != null && _biliInfo!['videoInfos'] is List) {
      videoInfos = _biliInfo!['videoInfos'] as List;
    }

    Map? firstVideo;
    if (videoInfos != null && videoInfos.isNotEmpty && videoInfos[0] is Map) {
      firstVideo = videoInfos[0] as Map;
    }

    String coverImage = '';
    if (firstVideo != null && firstVideo['coverImage'] is String) {
      coverImage = firstVideo['coverImage'];
    } else if (_biliInfo != null && _biliInfo!['pic'] is String) {
      coverImage = _biliInfo!['pic'];
    }

    String title = '未知标题';
    if (_biliInfo != null && _biliInfo!['title'] is String) {
      title = _biliInfo!['title'];
    } else if (firstVideo != null && firstVideo['name'] is String) {
      title = firstVideo['name'];
    }

    String desc = '';
    if (_biliInfo != null) {
      if (_biliInfo!['actors'] is String) {
        desc = _biliInfo!['actors'];
      } else if (_biliInfo!['desc'] is String) {
        desc = _biliInfo!['desc'];
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Expanded(
                child: _buildTextField(theme, _biliUrlController, '视频链接 / BV号', '粘贴链接自动解析', Icons.search),
              ),
              const SizedBox(width: 12),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFFFB7299), Color(0xFFFF9EB5)]),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: _isLoading ? null : _parseBilibili,
                  icon: _isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _biliInfo == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.tv_off_rounded, size: 64, color: theme.disabledColor.withOpacity(0.2)),
                      const SizedBox(height: 16),
                      Text('暂无解析内容', style: TextStyle(color: theme.hintColor)),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      if (coverImage.isNotEmpty)
                        Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
                          ),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Image.network(
                              coverImage, 
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, err, stack) => Container(color: Colors.grey.withOpacity(0.3), child: const Icon(Icons.broken_image)),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          desc,
                          style: TextStyle(fontSize: 13, color: theme.hintColor),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('是否开启代理', style: TextStyle(fontWeight: FontWeight.w500)),
                            IOSStyleSwitch(
                              value: _isProxy,
                              onChanged: (val) => setState(() => _isProxy = val),
                              isDark: theme.brightness == Brightness.dark,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildActionButton('添加到播放列表', _addBilibili, color: const Color(0xFFFB7299)),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildAlistContent(ThemeData theme) {
    if (_checkingVendors) return const Center(child: CircularProgressIndicator());
    if (!_boundVendors.contains('alist')) return _buildBindGuide('Alist', theme);

    return Column(
      children: [
        _buildPathBar(theme, _alistPath, _goUpAlist),
        Expanded(
          child: !_alistLoading && _alistFiles.isEmpty
              ? Center(child: Text('暂无文件', style: TextStyle(color: theme.hintColor)))
              : _alistLoading && _alistFiles.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : NotificationListener<ScrollNotification>(
                onNotification: (ScrollNotification scrollInfo) {
                  if (!_alistLoading && _alistHasMore && 
                      scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
                    _loadAlist(_alistPath, loadMore: true);
                  }
                  return false;
                },
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: _alistFiles.length + (_alistHasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _alistFiles.length) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        alignment: Alignment.center,
                        child: _alistLoading 
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                            : TextButton(
                                onPressed: () => _loadAlist(_alistPath, loadMore: true),
                                child: const Text('加载更多'),
                              ),
                      );
                    }
                    
                    final file = _alistFiles[index];
                    final isDir = file['isDir'] == true || file['is_dir'] == true;
                    final path = file['path'] ?? (_alistPath.endsWith('/') ? '$_alistPath${file['name']}' : '$_alistPath/${file['name']}');
                    final isSelected = _selectedAlistItems.containsKey(path);

                    return _buildFileItem(
                      theme, 
                      file['name'], 
                      isDir, 
                      () => isDir ? (file['path'] != null ? _loadAlist(file['path']) : _enterAlistDir(file['name'])) : _addAlistFile(file),
                      subtitle: isDir ? null : _formatSize(file['size']),
                      isSelected: isSelected,
                      onSelectionChanged: (val) {
                        setState(() {
                          if (val == true) {
                            final fileToStore = Map<String, dynamic>.from(file);
                            fileToStore['path'] = path;
                            _selectedAlistItems[path] = fileToStore;
                          } else {
                            _selectedAlistItems.remove(path);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
        ),
        if (_selectedAlistItems.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4))],
            ),
            child: _buildActionButton('添加选中的 ${_selectedAlistItems.length} 项', _addSelectedAlistItems),
          ),
      ],
    );
  }

  Widget _buildEmbyContent(ThemeData theme) {
    if (_checkingVendors) return const Center(child: CircularProgressIndicator());
    if (!_boundVendors.contains('emby')) return _buildBindGuide('Emby', theme);

    return Column(
      children: [
        _buildPathBar(theme, _embyPath, _goUpEmby),
        Expanded(
          child: _embyLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: _embyFiles.length,
                itemBuilder: (context, index) {
                  final file = _embyFiles[index];
                  final isDir = file['isDir'] == true || file['is_dir'] == true || file['Type'] == 'Folder' || file['CollectionType'] != null;
                  final name = file['name'] ?? file['Name'] ?? 'Unknown';
                  return _buildFileItem(
                    theme,
                    name,
                    isDir,
                    () => isDir ? _enterEmbyDir(name, file['path'] ?? file['Id'] ?? name) : _addEmbyFile(file),
                    subtitle: isDir ? null : 'Emby Media',
                    iconColor: Colors.green,
                  );
                },
              ),
        ),
      ],
    );
  }


  Widget _buildTextField(ThemeData theme, TextEditingController controller, String label, String hint, IconData icon) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: theme.primaryColor),
        filled: true,
        fillColor: theme.cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: theme.primaryColor),
        ),
      ),
    );
  }

  Widget _buildActionButton(String text, VoidCallback onPressed, {Color? color}) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: color != null 
              ? [color, color.withOpacity(0.8)]
              : const [Color(0xFF5D5FEF), Color(0xFF843CF6)],
          ),
          boxShadow: [
            BoxShadow(
              color: (color ?? const Color(0xFF5D5FEF)).withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isLoading ? null : onPressed,
            borderRadius: BorderRadius.circular(16),
            child: Center(
              child: _isLoading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPathBar(ThemeData theme, String path, VoidCallback onUp) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: path == '/' ? null : onUp,
            borderRadius: BorderRadius.circular(8),
            child: Icon(Icons.arrow_upward_rounded, color: path == '/' ? theme.disabledColor : theme.primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              path,
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('代理', style: TextStyle(fontSize: 12, color: theme.hintColor)),
              const SizedBox(width: 4),
              Transform.scale(
                scale: 0.8,
                child: IOSStyleSwitch(
                  value: _isProxy,
                  onChanged: (val) => setState(() => _isProxy = val),
                  isDark: theme.brightness == Brightness.dark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFileItem(ThemeData theme, String name, bool isDir, VoidCallback onTap, {String? subtitle, Color? iconColor, bool? isSelected, ValueChanged<bool?>? onSelectionChanged}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onSelectionChanged != null)
              Padding(
                padding: const EdgeInsets.only(right: 4.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: isSelected ?? false,
                    onChanged: onSelectionChanged,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isDir ? Colors.amber : (iconColor ?? Colors.blue)).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isDir ? Icons.folder_rounded : Icons.movie_rounded,
                color: isDir ? Colors.amber : (iconColor ?? Colors.blue),
              ),
            ),
          ],
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: subtitle != null ? Text(subtitle, style: TextStyle(fontSize: 12, color: theme.hintColor)) : null,
      ),
    );
  }

  Widget _buildBindGuide(String name, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.link_off_rounded, size: 64, color: theme.disabledColor.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text('未绑定 $name', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('请先绑定账号以访问资源', style: TextStyle(color: theme.hintColor)),
          const SizedBox(height: 24),
          Material(
            color: theme.primaryColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () async {
                await PlatformBindingDialog.show(
                  context, 
                  initialIndex: name == 'Alist' ? 0 : 1
                );
                _checkVendors();
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link, color: theme.primaryColor, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '立即绑定 $name',
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
        ],
      ),
    );
  }

  String _formatSize(dynamic size) {
    if (size == null) return '';
    if (size is! num) return size.toString();
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(size / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  // Logic Actions
  Future<void> _addDirectLink() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final name = _nameController.text.trim().isEmpty ? 'Unknown Movie' : _nameController.text.trim();
      bool rtmp = url.startsWith('rtmp://');
      await WatchTogetherService.addMovie(widget.roomId, {
        'url': url, 'name': name, 'live': _isLive || rtmp, 'proxy': false, 'rtmpSource': rtmp, 'type': 'mp4',
        'headers': {'User-Agent': 'Mozilla/5.0'}, 'parentId': widget.parentId
      });
      if (mounted) { Navigator.pop(context); MessageUtils.showSuccess(context, '添加成功'); }
    } catch (e) { if (mounted) MessageUtils.showError(context, '添加失败: $e'); } 
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  Future<void> _parseBilibili() async {
    final url = _biliUrlController.text.trim();
    if (url.isEmpty) return;
    setState(() { _isLoading = true; _biliInfo = null; });
    try {
      final info = await WatchTogetherService.parseBilibili(url);
      if (mounted) setState(() => _biliInfo = info);
    } catch (e) { if (mounted) MessageUtils.showError(context, '解析失败: $e'); }
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  Future<void> _addBilibili() async {
    if (_biliInfo == null) return;
    setState(() => _isLoading = true);
    
    // Extract info from API response structure
    final videoInfos = _biliInfo?['videoInfos'] as List?;
    final firstVideo = (videoInfos != null && videoInfos.isNotEmpty) ? videoInfos[0] : null;
    
    // Fallback or use data
    final title = _biliInfo?['title'] ?? firstVideo?['name'] ?? 'Bilibili Video';
    // Bilibili usually doesn't need direct URL if we have bvid/cid, backend handles it
    final url = ''; 
    final bvid = firstVideo?['bvid'] ?? _biliInfo?['bvid'];
    final cid = firstVideo?['cid'] ?? _biliInfo?['cid'];
    final header = _biliInfo?['header'] ?? {}; // API doc doesn't mention header in response, but we might need it if available
    final isLive = firstVideo?['live'] == true;

    try {
      if (!isLive && (bvid == null || cid == null)) {
        throw Exception('无法获取 BVID 或 CID');
      }

      await WatchTogetherService.addMovie(widget.roomId, {
        'url': url, 
        'name': title, 
        'type': 'bilibili', 
        'live': isLive, 
        'proxy': _isProxy,
        'headers': header,
        'vendorInfo': {
          'vendor': 'bilibili', 
          'bilibili': { // Nested structure based on API doc
            'bvid': bvid, 
            'cid': cid,
            'shared': false
          }
        }
      });
      if (mounted) { Navigator.pop(context); MessageUtils.showSuccess(context, '添加成功'); }
    } catch (e) { if (mounted) MessageUtils.showError(context, '添加失败: $e'); }
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  Future<void> _loadAlist(String path, {bool loadMore = false}) async {
    if (loadMore && _alistLoading) return;
    
    int targetPage = loadMore ? _alistPage + 1 : 1;

    setState(() { 
      _alistLoading = true; 
      if (!loadMore) {
        _alistPath = path;
        _alistFiles = []; // Clear only on full reload
      }
    });

    try {
      final data = await WatchTogetherService.listAlist(path, page: targetPage, max: _pageSize);
      final List newItems = (data['items'] as List?) ?? [];
      final int? total = data['total'] is int ? data['total'] : null;
      
      if (mounted) {
        setState(() {
          if (loadMore) {
            _alistFiles.addAll(newItems);
            _alistPage = targetPage;
          } else {
            _alistFiles = newItems;
            _alistPage = 1;
          }
          
          if (total != null) {
            _alistHasMore = _alistFiles.length < total;
          } else {
            // Fallback strategy
            if (newItems.isEmpty) {
              _alistHasMore = false;
            } else {
              _alistHasMore = newItems.length >= _pageSize;
            }
          }
        });
      }
    } catch (e) { 
      debugPrint('Alist load error: $e');
      if (mounted) MessageUtils.showError(context, '加载失败: $e'); 
    }
    finally { if (mounted) setState(() => _alistLoading = false); }
  }

  void _enterAlistDir(String pathOrName) {
    if (pathOrName.startsWith('/')) {
       _loadAlist(pathOrName);
    } else {
       _loadAlist(_alistPath.endsWith('/') ? '$_alistPath$pathOrName' : '$_alistPath/$pathOrName');
    }
  }
  
  void _goUpAlist() {
    if (_alistPath == '/') return;
    final parts = _alistPath.split('/'); parts.removeLast();
    _loadAlist(parts.length == 1 && parts[0] == '' ? '/' : parts.join('/'));
  }

  Future<void> _addAlistFile(dynamic file) async {
    setState(() => _isLoading = true);
    try {
      final path = file['path'] ?? (_alistPath.endsWith('/') ? '$_alistPath${file['name']}' : '$_alistPath/${file['name']}');
      await WatchTogetherService.addMovie(widget.roomId, {
        'name': file['name'], 'url': '', 'type': 'alist', 'live': false, 'proxy': _isProxy, 'parentId': widget.parentId,
        'vendorInfo': {'vendor': 'alist', 'alist': {'path': path}}
      });
      if (mounted) { Navigator.pop(context); MessageUtils.showSuccess(context, '添加成功'); }
    } catch (e) { if (mounted) MessageUtils.showError(context, '添加失败: $e'); }
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  Future<void> _addSelectedAlistItems() async {
    if (_selectedAlistItems.isEmpty) return;
    setState(() => _isLoading = true);
    
    try {
      final List<Map<String, dynamic>> items = [];
      for (final file in _selectedAlistItems.values) {
        final path = file['path']; // Should be set during selection
        final isDir = file['isDir'] == true || file['is_dir'] == true;
        
        items.add({
          'name': file['name'],
          'url': '',
          'type': '',
          'live': false,
          'rtmpSource': false,
          'headers': {},
          'proxy': _isProxy,
          'isFolder': isDir,
          'parentId': widget.parentId,
          'vendorInfo': {
            'vendor': 'alist',
            'alist': {
              'path': path
            }
          }
        });
      }

      await WatchTogetherService.addMovies(widget.roomId, items);
      
      if (mounted) {
        Navigator.pop(context);
        MessageUtils.showSuccess(context, '已添加 ${_selectedAlistItems.length} 项');
      }
    } catch (e) {
      if (mounted) MessageUtils.showError(context, '批量添加失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadEmby(String path) async {
    setState(() { _embyLoading = true; _embyPath = path; });
    try {
      final data = await WatchTogetherService.listEmby(path);
      if (mounted) {
        setState(() {
          if (data is List) {
            _embyFiles = data;
          } else if (data is Map) {
            // Fix: API docs say 'items', check both 'items' and 'Items'
            if (data['items'] != null) {
              _embyFiles = data['items'];
            } else if (data['Items'] != null) {
              _embyFiles = data['Items'];
            } else {
              _embyFiles = [];
            }
          } else {
            _embyFiles = [];
          }
        });
      }
    } catch (e) { if (mounted) MessageUtils.showError(context, '加载失败: $e'); }
    finally { if (mounted) setState(() => _embyLoading = false); }
  }

  void _enterEmbyDir(String name, String pathOrId) => _loadEmby((pathOrId.contains('/') || pathOrId.length > 20) ? pathOrId : (_embyPath.endsWith('/') ? '$_embyPath$name' : '$_embyPath/$name'));

  void _goUpEmby() {
    if (_embyPath == '/') return;
    final parts = _embyPath.split('/'); parts.removeLast();
    _loadEmby(parts.length == 1 && parts[0] == '' ? '/' : parts.join('/'));
  }

  Future<void> _addEmbyFile(dynamic file) async {
    setState(() => _isLoading = true);
    try {
      final path = file['Id'] ?? file['id'] ?? file['Path'] ?? file['path'];
      await WatchTogetherService.addMovie(widget.roomId, {
        'name': file['name'] ?? file['Name'] ?? 'Emby Video', 'url': '', 'type': '', 'live': false, 'proxy': _isProxy, 'parentId': widget.parentId,
        'vendorInfo': {'vendor': 'emby', 'emby': {'path': path}}
      });
      if (mounted) { Navigator.pop(context); MessageUtils.showSuccess(context, '添加成功'); }
    } catch (e) { if (mounted) MessageUtils.showError(context, '添加失败: $e'); }
    finally { if (mounted) setState(() => _isLoading = false); }
  }
}