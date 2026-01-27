class WUser {
  final String id;
  final String username;
  final String? email;
  final int role;
  final int createdAt;
  final int status;
  final int onlineCount;

  WUser({
    required this.id,
    required this.username,
    this.email,
    required this.role,
    this.createdAt = 0,
    this.status = 0,
    this.onlineCount = 0,
  });

  factory WUser.fromJson(Map<String, dynamic> json) {
    int timestamp = 0;
    if (json['joinAt'] != null) {
      timestamp = json['joinAt'] is int ? json['joinAt'] : int.tryParse(json['joinAt'].toString()) ?? 0;
    } else if (json['createdAt'] != null) {
      timestamp = json['createdAt'] is int ? json['createdAt'] : int.tryParse(json['createdAt'].toString()) ?? 0;
    }

    if (timestamp > 100000000000) { 
      timestamp = (timestamp / 1000).floor();
    }

    return WUser(
      id: json['id'] ?? json['userId'] ?? '',
      username: json['username'] ?? '',
      email: json['email'],
      role: json['role'] is int ? json['role'] : 0,
      createdAt: timestamp,
      status: json['status'] is int ? json['status'] : 0,
      onlineCount: json['onlineCount'] is int ? json['onlineCount'] : 0,
    );
  }
}

class WRoom {
  final String roomId;
  final String roomName;
  final int viewerCount;
  final bool needPassword;
  final String creator;
  final String creatorId;
  final int createdAt;
  final int status;
  final bool hidden;
  final bool needVerify;
  final bool guestCanPause;
  final bool guestCanAdd;

  WRoom({
    required this.roomId,
    required this.roomName,
    this.viewerCount = 0,
    this.needPassword = false,
    this.creator = '',
    required this.creatorId,
    this.createdAt = 0,
    this.status = 0,
    this.hidden = false,
    this.needVerify = false,
    this.guestCanPause = true,
    this.guestCanAdd = true,
  });

  WRoom copyWith({
    String? roomId,
    String? roomName,
    int? viewerCount,
    bool? needPassword,
    String? creator,
    String? creatorId,
    int? createdAt,
    int? status,
    bool? hidden,
    bool? needVerify,
    bool? guestCanPause,
    bool? guestCanAdd,
  }) {
    return WRoom(
      roomId: roomId ?? this.roomId,
      roomName: roomName ?? this.roomName,
      viewerCount: viewerCount ?? this.viewerCount,
      needPassword: needPassword ?? this.needPassword,
      creator: creator ?? this.creator,
      creatorId: creatorId ?? this.creatorId,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      hidden: hidden ?? this.hidden,
      needVerify: needVerify ?? this.needVerify,
      guestCanPause: guestCanPause ?? this.guestCanPause,
      guestCanAdd: guestCanAdd ?? this.guestCanAdd,
    );
  }

  factory WRoom.fromJson(Map<String, dynamic> json) {
    bool canPause = true;
    bool canAdd = true;
    
    if (json['guest_permissions'] != null) {
      final int perms = json['guest_permissions'] is int ? json['guest_permissions'] : int.tryParse(json['guest_permissions'].toString()) ?? 0;
      canAdd = (perms & 2) != 0;
      canPause = (perms & 32) != 0;
    } else {
      canPause = json['guestCanPause'] ?? true;
      canAdd = json['guestCanAdd'] ?? true;
    }

    bool isHidden = false;
    if (json['settings'] != null && json['settings'] is Map) {
      isHidden = json['settings']['hidden'] ?? false;
    } else {
      isHidden = json['hidden'] ?? false;
    }

    return WRoom(
      roomId: json['roomId'] ?? '',
      roomName: json['roomName'] ?? '',
      viewerCount: json['viewerCount'] is int ? json['viewerCount'] : 0,
      needPassword: json['needPassword'] ?? false,
      creator: json['creator'] ?? '',
      creatorId: json['creatorId'] ?? '',
      createdAt: json['createdAt'] is int ? json['createdAt'] : 0,
      status: json['status'] is int ? json['status'] : 0,
      hidden: isHidden,
      needVerify: json['join_need_review'] ?? json['needVerify'] ?? false,
      guestCanPause: canPause,
      guestCanAdd: canAdd,
    );
  }
}

class WMovie {
  final String id;
  final String name;
  final String url;
  final bool live;
  final bool proxy;
  final bool rtmpSource;
  final String type;
  final String? subPath;
  final String creator;
  final Map<String, String> headers;
  final bool isFolder;
  final String? parentId;
  final Map<String, dynamic>? subtitles;
  final String? danmu;
  final String? streamDanmu;
  final Map<String, dynamic>? vendorInfo;

  WMovie({
    required this.id,
    required this.name,
    required this.url,
    this.live = false,
    this.proxy = false,
    this.rtmpSource = false,
    this.type = '',
    this.subPath,
    this.creator = '',
    this.headers = const {},
    this.isFolder = false,
    this.parentId,
    this.subtitles,
    this.danmu,
    this.streamDanmu,
    this.vendorInfo,
  });

  factory WMovie.fromJson(Map<String, dynamic> json) {
    final base = json['base'] is Map<String, dynamic> ? json['base'] : <String, dynamic>{};

    return WMovie(
      id: json['id'] ?? '',
      name: base['name'] ?? json['name'] ?? json['title'] ?? json['fileName'] ?? 'Unknown Movie',
      url: (base['url'] ?? json['url'] ?? '').toString().trim().replaceAll('`', ''),
      live: base['live'] ?? json['live'] ?? false,
      proxy: base['proxy'] ?? json['proxy'] ?? false,
      rtmpSource: base['rtmpSource'] ?? json['rtmpSource'] ?? false,
      type: base['type'] ?? json['type'] ?? '',
      subPath: json['subPath'] ?? base['subPath'],
      creator: json['creator'] ?? base['creator'] ?? '',
      headers: base['headers'] != null
          ? Map<String, String>.from(base['headers'])
          : (json['headers'] != null
              ? Map<String, String>.from(json['headers'])
              : const {}),
      isFolder: base['isFolder'] ?? json['isFolder'] ?? false,
      parentId: base['parentId'] ?? json['parentId'],
      subtitles: base['subtitles'] != null ? Map<String, dynamic>.from(base['subtitles']) : null,
      danmu: base['danmu'] ?? json['danmu'],
      streamDanmu: base['streamDanmu'] ?? json['streamDanmu'],
      vendorInfo: base['vendorInfo'] != null ? Map<String, dynamic>.from(base['vendorInfo']) : null,
    );
  }
}

class WPlaybackStatus {
  final WMovie? movie;
  final bool isPlaying;
  final double currentTime;
  final double playbackRate;

  WPlaybackStatus({
    this.movie,
    this.isPlaying = false,
    this.currentTime = 0,
    this.playbackRate = 1.0,
  });

  factory WPlaybackStatus.fromJson(Map<String, dynamic> json) {
    return WPlaybackStatus(
      movie: json['movie'] != null ? WMovie.fromJson(json['movie']) : null,
      isPlaying: json['status']?['is_playing'] ?? json['status']?['isPlaying'] ?? false,
      currentTime: (json['status']?['current_time'] ?? json['status']?['currentTime'] ?? 0).toDouble(),
      playbackRate: (json['status']?['playback_rate'] ?? json['status']?['playbackRate'] ?? 1.0).toDouble(),
    );
  }
}

class RoomMemberPermissions {
  static const int getMovieList = 1 << 0;
  static const int addMovie = 1 << 1;
  static const int deleteMovie = 1 << 2;
  static const int editMovie = 1 << 3;
  static const int setCurrentMovie = 1 << 4;
  static const int setCurrentStatus = 1 << 5;
  static const int sendChatMessage = 1 << 6;
  static const int webRTC = 1 << 7;

  static const Map<int, String> descriptions = {
    getMovieList: '获取影片列表',
    addMovie: '添加影片',
    deleteMovie: '删除影片',
    editMovie: '编辑影片',
    setCurrentMovie: '切换影片',
    setCurrentStatus: '播放/暂停/进度',
    sendChatMessage: '发送聊天/弹幕',
    webRTC: 'WebRTC通话',
  };
}

class WRoomSettings {
  bool hidden;
  bool joinNeedReview;
  bool disableJoinNewUser;
  bool disableGuest;
  
  bool canGetMovieList;
  bool canAddMovie;
  bool canEditMovie;
  bool canDeleteMovie;
  bool canSetCurrentMovie;
  bool canSetCurrentStatus;
  bool canSendChatMessage;

  int guestPermissions;
  int userDefaultPermissions;

  WRoomSettings({
    this.hidden = false,
    this.joinNeedReview = false,
    this.disableJoinNewUser = false,
    this.disableGuest = false,
    this.canGetMovieList = false,
    this.canAddMovie = false,
    this.canEditMovie = false,
    this.canDeleteMovie = false,
    this.canSetCurrentMovie = false,
    this.canSetCurrentStatus = false,
    this.canSendChatMessage = false,
    this.guestPermissions = 0,
    this.userDefaultPermissions = 0,
  });

  factory WRoomSettings.fromJson(Map<String, dynamic> json) {
    return WRoomSettings(
      hidden: json['hidden'] ?? false,
      joinNeedReview: json['join_need_review'] ?? false,
      disableJoinNewUser: json['disable_join_new_user'] ?? false,
      disableGuest: json['disable_guest'] ?? false,
      canGetMovieList: json['can_get_movie_list'] ?? false,
      canAddMovie: json['can_add_movie'] ?? false,
      canEditMovie: json['can_edit_movie'] ?? false,
      canDeleteMovie: json['can_delete_movie'] ?? false,
      canSetCurrentMovie: json['can_set_current_movie'] ?? false,
      canSetCurrentStatus: json['can_set_current_status'] ?? false,
      canSendChatMessage: json['can_send_chat_message'] ?? false,
      guestPermissions: json['guest_permissions'] is int ? json['guest_permissions'] : int.tryParse(json['guest_permissions']?.toString() ?? '0') ?? 0,
      userDefaultPermissions: json['user_default_permissions'] is int ? json['user_default_permissions'] : int.tryParse(json['user_default_permissions']?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hidden': hidden,
      'join_need_review': joinNeedReview,
      'disable_join_new_user': disableJoinNewUser,
      'disable_guest': disableGuest,
      'can_get_movie_list': canGetMovieList,
      'can_add_movie': canAddMovie,
      'can_edit_movie': canEditMovie,
      'can_delete_movie': canDeleteMovie,
      'can_set_current_movie': canSetCurrentMovie,
      'can_set_current_status': canSetCurrentStatus,
      'can_send_chat_message': canSendChatMessage,
      'guest_permissions': guestPermissions,
      'user_default_permissions': userDefaultPermissions,
    };
  }
}
