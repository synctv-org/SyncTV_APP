import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/services.dart';
import 'package:synctv_app/models/watch_together_models.dart';
import 'package:synctv_app/models/simple_proto.dart';
import 'package:synctv_app/services/watch_together_service.dart';
import 'package:synctv_app/utils/message_utils.dart';
import 'package:synctv_app/utils/chat_utils.dart';
import 'package:synctv_app/widgets/room_settings_dialog.dart';
import 'package:synctv_app/widgets/add_movie_dialog.dart';
import 'package:synctv_app/widgets/custom_video_player.dart';
import 'package:synctv_app/widgets/chat_input_area.dart';
import 'package:synctv_app/managers/webrtc_manager.dart';
import 'package:synctv_app/models/danmaku_model.dart';

class DesktopRoomScreen extends StatefulWidget {
  final WRoom room;

  const DesktopRoomScreen({super.key, required this.room});

  @override
  State<DesktopRoomScreen> createState() => _DesktopRoomScreenState();
}

class _DesktopRoomScreenState extends State<DesktopRoomScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  VideoPlayerController? _videoPlayerController;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = []; // Local chat cache
  Timer? _syncTimer;
  WPlaybackStatus? _currentStatus;
  WebSocketChannel? _channel;
  List<WUser> _members = [];
  List<WMovie> _movies = [];
  bool _isLoadingMovies = true;
  
  // Pagination
  int _currentPage = 1;
  final int _pageSize = 20;
  bool _hasMoreMovies = true;
  bool _isLoadingMoreMovies = false;
  final ScrollController _movieScrollController = ScrollController();

  // Folder navigation
  List<WMovie> _folderStack = [];
  List<String> _folderNameStack = ['根目录'];

  WUser? _currentUser;

  // Sync state
  bool _isSyncing = false;
  Timer? _updateDebounce;
  bool _lastPlaying = false;
  double _lastRate = 1.0;
  double _lastPosition = 0.0;

  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  StreamSubscription? _authErrorSubscription;

  // WebRTC
  WebRTCManager? _webrtcManager;
  bool _isVoiceJoined = false;
  
  // Danmaku Stream
  final DanmakuController _danmakuController = DanmakuController();

  bool _isSelectionMode = false;
  final Set<String> _selectedMovieIds = {};

  @override
  void initState() {
    super.initState();
    _authErrorSubscription = WatchTogetherService.onAuthError.listen((_) {
      if (mounted) {
        _disposeVideoController();
        _channel?.sink.close();
        _reconnectTimer?.cancel();
        _webrtcManager?.leave();
        
        Navigator.of(context).pop();
      }
    });
    _tabController = TabController(length: 3, vsync: this);
    
    // Initialize WebRTC Manager
    _webrtcManager = WebRTCManager(
      onSignalingMessage: (type, data) {
        if (_channel != null) {
          MessageType msgType;
          switch (type) {
            case 'offer': msgType = MessageType.WEBRTC_OFFER; break;
            case 'answer': msgType = MessageType.WEBRTC_ANSWER; break;
            case 'candidate': msgType = MessageType.WEBRTC_ICE_CANDIDATE; break;
            case 'join': msgType = MessageType.WEBRTC_JOIN; break;
            case 'leave': msgType = MessageType.WEBRTC_LEAVE; break;
            default: return;
          }
          
          try {
            final payload = {'data': jsonEncode(data)};
            if (data['to'] != null) {
              payload['to'] = data['to'];
            }
            final bytes = SimpleProto.encodeWebRTC(msgType, payload);
            _channel!.sink.add(bytes);
          } catch (e) {
            debugPrint('WebRTC encode error: $e');
          }
        }
      },
      onStateChange: () {
        if (mounted) setState(() {});
      },
    );
    
    _joinRoom();
  }

  Future<void> _joinRoom() async {
    _connectWebSocket();

    _syncState();

    Future.wait([
      _fetchCurrentUser(),
      _fetchMembers(),
      _fetchMovies(),
    ]).catchError((e) {
      debugPrint('Background data fetch error: $e');
    });
  }

  Future<void> _fetchCurrentUser() async {
    try {
      final user = await WatchTogetherService.getMe();
      if (mounted) {
        setState(() {
          _currentUser = user;
        });
      }
    } catch (e) {
      debugPrint('Fetch user error: $e');
    }
  }

  Future<void> _fetchMembers() async {
    try {
      final members = await WatchTogetherService.getRoomMembers(widget.room.roomId);
      
      members.sort((a, b) {
        if (a.id == widget.room.creatorId) return -1;
        if (b.id == widget.room.creatorId) return 1;
        // Secondary sort: Admin > Member
        if (a.role >= 4 && b.role < 4) return -1;
        if (a.role < 4 && b.role >= 4) return 1;
        return 0;
      });

      if (mounted) {
        setState(() {
          _members = members;
        });
      }
    } catch (e) {
      debugPrint('Fetch members error: $e');
    }
  }

  Future<void> _fetchMovies() async {
    try {
      _currentPage = 1;
      _hasMoreMovies = true;
      
      final parentFolder = _folderStack.isNotEmpty ? _folderStack.last : null;
      final result = await WatchTogetherService.getMovies(
        widget.room.roomId, 
        parentId: parentFolder?.id,
        subPath: parentFolder?.subPath,
        page: 1,
        max: _pageSize
      );

      final movies = result['movies'] as List<WMovie>;
      final total = result['total'] as int;

      if (mounted) {
        setState(() {
          _movies = movies;
          _isLoadingMovies = false;
          _hasMoreMovies = _movies.length < total;
        });
        
        if (_movieScrollController.hasClients) {
          _movieScrollController.jumpTo(0);
        }
      }
    } catch (e) {
      debugPrint('Fetch movies error: $e');
      if (mounted) {
         setState(() => _isLoadingMovies = false);
      }
    }
  }

  void _onMovieScroll() {
    if (_movieScrollController.position.pixels >= _movieScrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMoreMovies && _hasMoreMovies) {
        _loadMoreMovies();
      }
    }
  }

  Future<void> _loadMoreMovies() async {
    if (_isLoadingMoreMovies) return;
    
    setState(() {
      _isLoadingMoreMovies = true;
    });

    try {
      final parentFolder = _folderStack.isNotEmpty ? _folderStack.last : null;
      final result = await WatchTogetherService.getMovies(
        widget.room.roomId, 
        parentId: parentFolder?.id,
        subPath: parentFolder?.subPath,
        page: _currentPage + 1,
        max: _pageSize
      );
      
      final movies = result['movies'] as List<WMovie>;
      final total = result['total'] as int;
      
      if (mounted) {
        setState(() {
          if (movies.isNotEmpty) {
             _movies.addAll(movies);
             _currentPage++;
             _hasMoreMovies = _movies.length < total;
          } else {
             _hasMoreMovies = false;
          }
          _isLoadingMoreMovies = false;
        });
      }
    } catch (e) {
      debugPrint('Load more movies error: $e');
      if (mounted) {
        setState(() {
          _isLoadingMoreMovies = false;
        });
      }
    }
  }

  Future<void> _connectWebSocket() async {
    _reconnectTimer?.cancel();
    
    try {
      final token = await WatchTogetherService.getToken();
      if (token == null) return;

      final httpUri = Uri.parse(WatchTogetherService.baseUrl);
      final wsScheme = httpUri.scheme == 'https' ? 'wss' : 'ws';
      final wsUrl = httpUri.replace(
        scheme: wsScheme,
        path: '${httpUri.path}/room/ws',
        queryParameters: {'roomId': widget.room.roomId},
      );
      
      _channel = IOWebSocketChannel.connect(
        wsUrl,
        protocols: [token],
      );

      _channel!.stream.listen(
        (data) {
          _reconnectAttempts = 0; 
          if (data is Uint8List || data is List<int>) {
             try {
               final message = SimpleProto.decode(data is Uint8List ? data : Uint8List.fromList(data));
               _handleWebSocketMessage(message);
             } catch (e) {
               debugPrint('Proto decode error: $e');
             }
          }
        },
        onError: (error) {
           debugPrint('WebSocket error: $error');
           _scheduleReconnect();
        },
        onDone: () {
           debugPrint('WebSocket closed');
           _scheduleReconnect();
        },
      );
    } catch (e) {
      debugPrint('WebSocket connection error: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
       if (mounted) MessageUtils.showError(context, '连接断开，请退出重试');
       return;
    }
    
    _reconnectAttempts++;
    final delay = Duration(seconds: _reconnectAttempts * 2); // Exponential backoff
    debugPrint('Scheduling reconnect attempt $_reconnectAttempts in ${delay.inSeconds}s');
    
    _reconnectTimer = Timer(delay, () {
      if (mounted) {
        _connectWebSocket();
      }
    });
  }

  void _handleWebSocketMessage(Map<String, dynamic> message) {
    final type = message['type'];
    
    if (type == MessageType.CHAT) {
      final sender = message['sender'];
      final content = message['chatContent'];
      final username = sender != null ? sender['username'] : 'Unknown';
      
      // Convert chat to danmaku
      if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized) {
        final currentPos = _videoPlayerController!.value.position;
        final danmaku = DanmakuItem(
          text: '$username: $content',
          startTime: currentPos,
          endTime: currentPos + const Duration(seconds: 8),
          color: Colors.white,
          type: DanmakuType.floating,
        );
        _danmakuController.add(danmaku);
      }
      
      if (mounted) {
        setState(() {
          _messages.add({
            'username': username,
            'content': content,
            'timestamp': message['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
          });
          // Limit chat history to 100 messages
          if (_messages.length > 100) {
            _messages.removeAt(0);
          }
        });
        _scrollToBottom();
      }
    } else if (type == MessageType.SYNC || type == MessageType.STATUS || type == MessageType.CHECK_STATUS) {
      final status = message['status'];
      if (status != null) {
        final isPlaying = status['is_playing'] == true;
        final currentTime = (status['current_time'] as num).toDouble();
        final playbackRate = (status['playback_rate'] as num?)?.toDouble() ?? 1.0;
        
        _performSync(isPlaying, currentTime, playbackRate);
        
        if (type == MessageType.SYNC) {
           debugPrint('Sync success');
        } else if (type == MessageType.CHECK_STATUS) {
           debugPrint('Status check received');
        }
      }
    } else if (type == MessageType.CURRENT) {
         _syncState();
      } else if (type == MessageType.MOVIES) {
         _fetchMovies();
      } else if (type == MessageType.VIEWER_COUNT) {
         _fetchMembers();
      } else if (type == MessageType.ERROR) {
         final errorMsg = message['error_message'];
         if (errorMsg != null && errorMsg.toString().isNotEmpty) {
            if (mounted) MessageUtils.showError(context, '错误: $errorMsg');
         } else {
         }
      } else if (type == MessageType.EXPIRED) {
         if (mounted) {
           MessageUtils.showError(context, '登录已过期，请重新登录');
           Navigator.of(context).pop();
         }
      } else if (type == MessageType.WEBRTC_OFFER || 
                 type == MessageType.WEBRTC_ANSWER || 
                 type == MessageType.WEBRTC_ICE_CANDIDATE ||
                 type == MessageType.WEBRTC_JOIN ||
                 type == MessageType.WEBRTC_LEAVE) {
         if (_webrtcManager != null) {
            final webrtcMap = message['webrtcData'];
            
            try {
              Map<String, dynamic> data = {};
              
              if (webrtcMap != null && webrtcMap['data'] != null) {
                 try {
                   final decoded = jsonDecode(webrtcMap['data']);
                   if (decoded is Map<String, dynamic>) {
                     data.addAll(decoded);
                   }
                 } catch (e) {
                   debugPrint('WebRTC JSON decode error: $e');
                 }
              }

              String? fromId;
              final rawFrom = webrtcMap != null ? webrtcMap['from'] : null;
              
              if (rawFrom != null && rawFrom.toString().isNotEmpty) {
                 fromId = rawFrom.toString();
              } else if (message['sender'] != null) {
                 fromId = message['sender']['userId'];
              }
              
              if (fromId != null) {
                 data['from'] = fromId;
              } else {
                 return;
              }
            
              String signalType = '';
              switch (type) {
                 case MessageType.WEBRTC_OFFER: signalType = 'offer'; break;
                 case MessageType.WEBRTC_ANSWER: signalType = 'answer'; break;
                 case MessageType.WEBRTC_ICE_CANDIDATE: signalType = 'candidate'; break;
                 case MessageType.WEBRTC_JOIN: signalType = 'join'; break;
                 case MessageType.WEBRTC_LEAVE: signalType = 'leave'; break;
              }
              
              if (signalType.isNotEmpty) {
                 if ((signalType == 'offer' || signalType == 'answer') && data['type'] == null) {
                   data['type'] = signalType;
                 }
                 _webrtcManager!.handleSignalingMessage(signalType, data);
              }
            } catch (e) {
              debugPrint('WebRTC signaling processing error: $e');
            }
         }
      }
    }

  Future<void> _performSync(bool isPlaying, double currentTime, double playbackRate) async {
    if (_videoPlayerController == null || !_videoPlayerController!.value.isInitialized) return;

    _isSyncing = true;
    
    try {
      if ((_videoPlayerController!.value.playbackSpeed - playbackRate).abs() > 0.1) {
        await _videoPlayerController!.setPlaybackSpeed(playbackRate);
        _lastRate = playbackRate;
      }

      if (!isPlaying && _videoPlayerController!.value.isPlaying) {
        await _videoPlayerController!.pause();
        _lastPlaying = false;
      }

      final currentPos = _videoPlayerController!.value.position.inMilliseconds / 1000.0;
      if ((currentPos - currentTime).abs() > 1.0) {
         await _videoPlayerController!.seekTo(Duration(milliseconds: (currentTime * 1000).toInt()));
         _lastPosition = currentTime; 
      }
      
      if (isPlaying && !_videoPlayerController!.value.isPlaying) {
        await _videoPlayerController!.play();
        _lastPlaying = true;
      }
    } catch (e) {
      debugPrint('Sync execution error: $e');
    } finally {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _isSyncing = false;
      });
    }
  }

  void _videoListener() {
    if (_isSyncing || _videoPlayerController == null || !_videoPlayerController!.value.isInitialized) return;

    final value = _videoPlayerController!.value;
    final isPlaying = value.isPlaying;
    final position = value.position.inMilliseconds / 1000.0;
    final rate = value.playbackSpeed;

    bool isPlayPauseChanged = false;
    bool isRateChanged = false;
    bool isSeekChanged = false;

    if (isPlaying != _lastPlaying) {
      _lastPlaying = isPlaying;
      isPlayPauseChanged = true;
    }

    if (rate != _lastRate) {
      _lastRate = rate;
      isRateChanged = true;
    }

    if ((position - _lastPosition).abs() > 1.0) {
      isSeekChanged = true;
      _lastPosition = position;
    } else {
       _lastPosition = position;
    }

    if (isPlayPauseChanged || isRateChanged || isSeekChanged) {
      if (isPlayPauseChanged || isRateChanged) {
        if (_updateDebounce?.isActive ?? false) _updateDebounce!.cancel();
        if (mounted && !_isSyncing) {
          final currentValue = _videoPlayerController!.value;
          _sendStatus(currentValue.isPlaying, currentValue.position.inMilliseconds / 1000.0, currentValue.playbackSpeed);
        }
        return;
      }

      if (_updateDebounce?.isActive ?? false) _updateDebounce!.cancel();
      _updateDebounce = Timer(const Duration(milliseconds: 500), () {
        if (mounted && !_isSyncing) {
          final currentValue = _videoPlayerController!.value;
          _sendStatus(currentValue.isPlaying, currentValue.position.inMilliseconds / 1000.0, currentValue.playbackSpeed);
        }
      });
    }
  }

  void _sendStatus(bool isPlaying, double position, double rate) {
    if (_channel != null) {
      try {
        final bytes = SimpleProto.encodeStatus(isPlaying, position, rate);
        _channel!.sink.add(bytes);
      } catch (e) {
        debugPrint('Send status error: $e');
      }
    }
  }

  Future<void> _syncState() async {
    try {
      final status = await WatchTogetherService.getCurrentMovie(widget.room.roomId);
      if (mounted) {
        if (_currentStatus?.movie?.id != status.movie?.id) {
           _danmakuController.clear();
        }

        setState(() {
          _currentStatus = status;
        });
        
        if (status.movie != null && status.movie!.url.isNotEmpty) {
          String newUrl = status.movie!.url;
          if (newUrl.startsWith('/')) {
            newUrl = '${WatchTogetherService.baseUrl.replaceAll('/api', '')}$newUrl';
          }

          if (_videoPlayerController == null || _videoPlayerController!.dataSource != newUrl) {
             await _initVideo(newUrl, headers: status.movie!.headers);
             if (mounted && _videoPlayerController != null && _videoPlayerController!.value.isInitialized) {
                _performSync(status.isPlaying, status.currentTime, status.playbackRate);
             }
          } else {
             _performSync(status.isPlaying, status.currentTime, status.playbackRate);
          }
          
          String? streamUrl = status.movie!.streamDanmu;
          if (streamUrl != null && streamUrl.startsWith('/')) {
              streamUrl = '${WatchTogetherService.baseUrl.replaceAll('/api', '')}$streamUrl';
          }
          
          String? danmuUrl = status.movie!.danmu;
          if (danmuUrl != null && danmuUrl.startsWith('/')) {
              danmuUrl = '${WatchTogetherService.baseUrl.replaceAll('/api', '')}$danmuUrl';
          }
          
          _danmakuController.updateConfig(
            danmakuUrl: danmuUrl,
            streamDanmakuUrl: streamUrl,
            controller: _videoPlayerController
          );
        } else {
          if (_videoPlayerController != null) {
            _disposeVideoController();
            setState(() {});
          }
        }
      }
    } catch (e) {
      debugPrint('Sync state error: $e');
    }
  }

  Future<void> _initVideo(String url, {Map<String, String>? headers}) async {
    if (url.isEmpty) return;

    final newController = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: headers ?? {},
    );

    try {
      await newController.initialize();
      
      if (!mounted) {
        newController.dispose();
        return;
      }

      _disposeVideoController();
      
      _videoPlayerController = newController;
      _videoPlayerController!.addListener(_videoListener); // Add listener
      
      if (mounted) setState(() {});
    } catch (e) {
      newController.dispose();
      debugPrint('Video init error: $e');
      if (mounted) MessageUtils.showError(context, '视频加载失败');
    }
  }

  void _disposeVideoController() {
    _videoPlayerController?.removeListener(_videoListener); // Remove listener
    _videoPlayerController?.dispose();
    _videoPlayerController = null;
    _updateDebounce?.cancel(); // Cancel debounce
  }

  @override
  void dispose() {
    _authErrorSubscription?.cancel();
    _tabController.dispose();
    _disposeVideoController();
    _syncTimer?.cancel();
    _channel?.sink.close();
    _messageController.dispose();
    _chatScrollController.dispose();
    _movieScrollController.dispose();
    _webrtcManager?.dispose();
    _danmakuController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      appBar: AppBar(
        title: Text(widget.room.roomName),
        backgroundColor: theme.appBarTheme.backgroundColor,
        actions: [
          IconButton(
            onPressed: () {
               Clipboard.setData(ClipboardData(text: widget.room.roomId));
               MessageUtils.showInfo(context, '房间ID已复制');
            },
            icon: const Icon(Icons.copy),
            tooltip: '复制房间ID',
          ),
          if (_currentStatus?.movie != null)
            IconButton(
              onPressed: _stopPlayback,
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
              tooltip: '停止播放',
            ),
          if ((_currentUser?.username == widget.room.creator) || 
              _members.any((m) => m.id == _currentUser?.id && m.role == 2))
            IconButton(
              onPressed: _showRoomSettings,
              icon: const Icon(Icons.settings),
              tooltip: '房间设置',
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(
        children: [
          // Main Content (Video)
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.black,
              child: Center(
                child: _videoPlayerController != null && _videoPlayerController!.value.isInitialized
                    ? CustomVideoPlayer(
                        controller: _videoPlayerController!,
                        title: _currentStatus?.movie?.name ?? '未知影片',
                        danmakuController: _danmakuController,
                        subtitles: _currentStatus?.movie?.subtitles,
                        onToggleFullScreen: _toggleFullScreen,
                        onSync: _handleSync,
                        // PC 端可能不需要全屏切换按钮，或者需要特殊的实现
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.ondemand_video_rounded, color: Colors.white54, size: 64),
                          const SizedBox(height: 16),
                          const Text('等待播放', style: TextStyle(color: Colors.white54, fontSize: 18)),
                        ],
                      ),
              ),
            ),
          ),
          
          // Sidebar (Chat/List/Members)
          Container(
            width: 350,
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              border: Border(left: BorderSide(color: theme.dividerColor)),
            ),
            child: Column(
              children: [
                _buildTabBar(theme),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildChatTab(),
                      _buildPlaylistTab(),
                      _buildMembersTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ... (Other methods: _handleSync, _toggleFullScreen, _sendDanmaku, etc.)
  // Note: I need to copy the rest of the methods, which are mostly identical to mobile version.
  // I will write the rest of the file in the next tool call if needed, or put them all here.
  
  void _handleSync() {
    if (_channel != null) {
      try {
        final bytes = SimpleProto.encodeSync();
        _channel!.sink.add(bytes);
        if (mounted) {
          MessageUtils.showInfo(context, '已发送同步请求', duration: const Duration(seconds: 1));
        }
      } catch (e) {
        debugPrint('Send SYNC error: $e');
      }
    }
  }

  void _toggleFullScreen() {
    // For PC, maybe toggle window fullscreen? Or just ignore.
    // Currently CustomVideoPlayer handles fullscreen by pushing a new route.
    if (_videoPlayerController == null || !_videoPlayerController!.value.isInitialized) return;
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CustomVideoPlayer(
          controller: _videoPlayerController!,
          title: _currentStatus?.movie?.name ?? '未知影片',
          danmakuController: _danmakuController,
          subtitles: _currentStatus?.movie?.subtitles,
          onToggleFullScreen: () => Navigator.of(context).pop(),
          onSync: _handleSync,
          onSendDanmaku: _sendDanmaku,
          isFullScreen: true,
        ),
      ),
    );
  }

  void _sendDanmaku(String text) {
    if (text.trim().isEmpty) return;
    if (_channel != null) {
      try {
        final bytes = SimpleProto.encodeChat(text);
        _channel!.sink.add(bytes);
      } catch (e) {
        debugPrint('Send danmaku error: $e');
        if (mounted) MessageUtils.showError(context, '弹幕发送失败: $e');
      }
    }
  }

  Widget _buildTabBar(ThemeData theme) {
    return Container(
      color: theme.appBarTheme.backgroundColor,
      child: TabBar(
        controller: _tabController,
        labelColor: theme.primaryColor,
        unselectedLabelColor: theme.hintColor,
        indicatorColor: theme.primaryColor,
        tabs: const [
          Tab(text: '聊天'),
          Tab(text: '列表'),
          Tab(text: '成员'),
        ],
      ),
    );
  }

  Widget _buildChatTab() {
    final theme = Theme.of(context);
    return Column(
      children: [
        _buildVoiceControl(theme),
        Expanded(
          child: ListView.builder(
            controller: _chatScrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              final name = msg['username'] ?? 'Unknown';
              final content = msg['content'] ?? '';
              
              int ts = msg['timestamp'] is int ? msg['timestamp'] : 0;
              if (ts < 100000000000) ts *= 1000;
              final dt = DateTime.fromMillisecondsSinceEpoch(ts);
              final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: theme.primaryColor)),
                        const SizedBox(width: 8),
                        Text(timeStr, style: TextStyle(fontSize: 10, color: theme.disabledColor)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(content),
                  ],
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ChatInputArea(
            textController: _messageController,
            isVoiceInputMode: false,
            isLoading: false,
            conversationType: 'watch_together',
            onSendMessage: () => _sendMessage(_messageController.text),
            onSwitchToVoiceMode: () {},
            onShowImagePicker: () {},
            onStartRecording: () {},
            onStopRecording: () {},
            onCancelRecording: () {},
          ),
        ),
      ],
    );
  }

  // Copied methods _buildVoiceControl, _buildPlaylistTab, _buildMembersTab, etc.
  // I'll simplify them slightly for brevity but keep functionality.

  Widget _buildVoiceControl(ThemeData theme) {
    if (_webrtcManager == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.hoverColor,
      child: Row(
        children: [
          Icon(
            _webrtcManager!.isConnected ? Icons.mic : Icons.mic_off,
            size: 16,
            color: _webrtcManager!.isConnected ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(
            _webrtcManager!.isConnected 
              ? '语音已连接 (${_webrtcManager!.participantCount}人)'
              : '语音聊天',
            style: const TextStyle(fontSize: 12),
          ),
          const Spacer(),
          if (_webrtcManager!.isConnected) ...[
            IconButton(
              icon: Icon(_webrtcManager!.isMuted ? Icons.mic_off : Icons.mic, size: 16),
              onPressed: () => _webrtcManager!.toggleMute(),
              constraints: const BoxConstraints(),
            ),
            IconButton(
              icon: const Icon(Icons.call_end, size: 16, color: Colors.red),
              onPressed: () => _webrtcManager!.leave(),
              constraints: const BoxConstraints(),
            ),
          ] else
            TextButton(
              onPressed: () => _webrtcManager!.join(),
              child: const Text('加入'),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaylistTab() {
    final theme = Theme.of(context);
    final primaryColor = const Color(0xFF5D5FEF);
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              if (_folderStack.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _exitFolder,
                  tooltip: '返回上一级',
                ),
              Expanded(
                child: Text(
                  _folderStack.isNotEmpty ? _folderNameStack.last : '播放列表',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _showAddMovieDialog,
                tooltip: '添加影片',
              ),
              IconButton(
                icon: Icon(_isSelectionMode ? Icons.close : Icons.checklist),
                onPressed: () {
                  setState(() {
                    _isSelectionMode = !_isSelectionMode;
                    _selectedMovieIds.clear();
                  });
                },
                tooltip: _isSelectionMode ? '取消选择' : '批量管理',
              ),
            ],
          ),
        ),
        if (_isSelectionMode)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                TextButton(onPressed: _selectAll, child: const Text('全选')),
                const Spacer(),
                ElevatedButton(
                  onPressed: _selectedMovieIds.isEmpty ? null : _deleteSelectedMovies,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  child: const Text('删除'),
                ),
              ],
            ),
          ),
        Expanded(
          child: _isLoadingMovies
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  controller: _movieScrollController,
                  itemCount: _movies.length + (_hasMoreMovies ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _movies.length) {
                       return const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()));
                    }
                    final movie = _movies[index];
                    final isCurrent = _currentStatus?.movie?.id == movie.id;
                    final isFolder = movie.isFolder;
                    final isSelected = _selectedMovieIds.contains(movie.id);

                    return ListTile(
                      selected: isSelected,
                      selectedTileColor: primaryColor.withOpacity(0.1),
                      leading: Icon(
                        isFolder ? Icons.folder : Icons.movie,
                        color: isFolder ? Colors.amber : (isCurrent ? primaryColor : null),
                      ),
                      title: Text(
                        movie.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent ? primaryColor : null,
                          fontWeight: isCurrent ? FontWeight.bold : null,
                        ),
                      ),
                      trailing: _isSelectionMode
                        ? Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked, color: isSelected ? primaryColor : Colors.grey)
                        : null,
                      onTap: () {
                        if (_isSelectionMode) {
                          _toggleSelection(movie);
                        } else if (isFolder) {
                          _enterFolder(movie);
                        } else {
                          _switchMovie(movie);
                        }
                      },
                      onLongPress: () {
                        if (!_isSelectionMode) {
                          _enterSelectionMode(movie);
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMembersTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text('在线成员 (${_members.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _members.length,
            itemBuilder: (context, index) {
              final member = _members[index];
              final isMe = _currentUser?.id == member.id;
              
              // Simplified permission check logic for UI
              return ListTile(
                leading: CircleAvatar(
                  child: Text(member.username[0].toUpperCase()),
                ),
                title: Text(member.username),
                subtitle: Text(member.role == 3 ? '房主' : (member.role == 2 ? '管理员' : '成员')),
                trailing: isMe ? const Chip(label: Text('我'), labelPadding: EdgeInsets.zero) : null,
                onTap: () {
                  // Show management dialog if have permission (simplified)
                  if (_currentUser != null && _currentUser!.role > member.role) {
                    _showMemberActionDialog(member);
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showMemberActionDialog(WUser member) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('管理: ${member.username}'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              _kickMember(member);
            },
            child: const Text('踢出成员', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ... (Missing methods: _enterFolder, _exitFolder, _switchMovie, _enterSelectionMode, etc. - implementation same as mobile)
  
  void _enterFolder(WMovie folder) {
    setState(() {
      _folderStack.add(folder);
      _folderNameStack.add(folder.name);
      _isLoadingMovies = true;
    });
    _fetchMovies();
  }

  void _exitFolder() {
    if (_folderStack.isEmpty) return;
    setState(() {
      _folderStack.removeLast();
      _folderNameStack.removeLast();
      _isLoadingMovies = true;
    });
    _fetchMovies();
  }

  Future<void> _switchMovie(WMovie movie) async {
    try {
      await WatchTogetherService.switchMovie(widget.room.roomId, movie.id, subPath: movie.subPath);
      if (mounted) MessageUtils.showSuccess(context, '已切换影片');
      await _syncState(); 
      if (mounted && _videoPlayerController != null && _videoPlayerController!.value.isInitialized) {
        await _videoPlayerController!.play();
        _sendStatus(
          true, 
          _videoPlayerController!.value.position.inMilliseconds / 1000.0, 
          _videoPlayerController!.value.playbackSpeed
        );
      }
    } catch (e) {
      if (mounted) MessageUtils.showError(context, '切换失败: $e');
    }
  }

  void _enterSelectionMode(WMovie movie) {
    setState(() {
      _isSelectionMode = true;
      _selectedMovieIds.clear();
      _selectedMovieIds.add(movie.id);
    });
  }

  void _toggleSelection(WMovie movie) {
    setState(() {
      if (_selectedMovieIds.contains(movie.id)) {
        _selectedMovieIds.remove(movie.id);
        if (_selectedMovieIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedMovieIds.add(movie.id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedMovieIds.length == _movies.length) {
        _selectedMovieIds.clear();
      } else {
        _selectedMovieIds.clear();
        _selectedMovieIds.addAll(_movies.map((m) => m.id));
      }
    });
  }

  Future<void> _deleteSelectedMovies() async {
    if (_selectedMovieIds.isEmpty) return;
    
    final confirmed = await ChatUtils.showStyledDialog<bool>(
      context: context, 
      title: '删除影片',
      icon: const Icon(Icons.delete_outline, color: Colors.red),
      content: Text('确定要删除选中的 ${_selectedMovieIds.length} 个影片吗？'),
      actions: [
        ChatUtils.createCancelButton(context),
        const SizedBox(width: 8),
        ChatUtils.createConfirmButton(
          context, 
          () => Navigator.pop(context, true), 
          text: '删除',
        ),
      ]
    );

    if (confirmed == true) {
      try {
        bool isAllLoadedSelected = _selectedMovieIds.length == _movies.length;
        if (isAllLoadedSelected && !_hasMoreMovies) {
           final parentFolder = _folderStack.isNotEmpty ? _folderStack.last : null;
           await WatchTogetherService.clearMovies(widget.room.roomId, parentId: parentFolder?.id);
        } else {
           await WatchTogetherService.deleteMovies(widget.room.roomId, _selectedMovieIds.toList());
        }

        setState(() {
          _isSelectionMode = false;
          _selectedMovieIds.clear();
        });
        _fetchMovies();
        if (mounted) MessageUtils.showInfo(context, '已删除');
      } catch (e) {
        if (mounted) MessageUtils.showError(context, '删除失败: $e');
      }
    }
  }

  Future<void> _stopPlayback() async {
    try {
      await WatchTogetherService.switchMovie(widget.room.roomId, '', subPath: '');
      if (mounted) {
        MessageUtils.showSuccess(context, '已停止播放');
        _disposeVideoController();
        setState(() {
          _currentStatus = null;
        });
      }
    } catch (e) {
      if (mounted) {
        MessageUtils.showError(context, '停止播放失败: $e');
      }
    }
  }

  Future<void> _showRoomSettings() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final settings = await WatchTogetherService.getRoomSettings(widget.room.roomId, isAdmin: true);
      
      if (mounted) {
        Navigator.pop(context); 
        
        final theme = Theme.of(context);
        ChatUtils.showStyledDialog(
          context: context,
          title: '房间设置',
          icon: Icon(Icons.settings, color: theme.primaryColor),
          content: SizedBox(
            width: 500, // Wider for PC
            child: RoomSettingsDialog(
              roomId: widget.room.roomId,
              roomName: widget.room.roomName,
              currentSettings: settings,
            ),
          ),
          actions: [],
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); 
        MessageUtils.showError(context, '获取设置失败: $e');
      }
    }
  }
  
  void _showAddMovieDialog() {
    AddMovieDialog.show(context, widget.room.roomId);
  }
  
  Future<void> _kickMember(WUser member) async {
    try {
      await WatchTogetherService.kickMember(widget.room.roomId, member.id);
      _fetchMembers(); 
      if (mounted) MessageUtils.showSuccess(context, '已踢出成员');
    } catch (e) {
      if (mounted) MessageUtils.showError(context, '踢出失败: $e');
    }
  }
  
  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;
    if (_channel != null) {
      try {
        final bytes = SimpleProto.encodeChat(text);
        _channel!.sink.add(bytes);
      } catch (e) {
        debugPrint('Send message error: $e');
        if (mounted) MessageUtils.showError(context, '发送失败: $e');
      }
    }
    _messageController.clear();
  }
}
