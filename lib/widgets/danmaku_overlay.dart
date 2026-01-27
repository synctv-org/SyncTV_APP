import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import '../models/danmaku_model.dart' as local;
import 'dart:async';

/// 高性能弹幕叠加显示组件 - 使用canvas_danmaku
class DanmakuOverlay extends StatefulWidget {
  final VideoPlayerController? videoController;
  final List<local.DanmakuItem> danmakuList;  
  final bool isEnabled;
  final double opacity;

  const DanmakuOverlay({
    super.key,
    required this.videoController,
    required this.danmakuList,
    this.isEnabled = true,
    this.opacity = 0.8,
  });

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay> {
  DanmakuController? _danmakuController;
  Timer? _syncTimer;
  Duration _lastVideoPosition = Duration.zero;
  Set<int> _processedDanmakuIndices = {};
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startVideoSync();
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 如果弹幕列表变化，重置处理状态
    if (widget.danmakuList != oldWidget.danmakuList) {
      _processedDanmakuIndices.clear();
      _lastVideoPosition = Duration.zero;
      _danmakuController?.clear();
    }
    
    // 如果启用状态变化，更新弹幕显示
    if (widget.isEnabled != oldWidget.isEnabled) {
      if (widget.isEnabled) {
        _startVideoSync();
      } else {
        _pauseVideoSync();
        _danmakuController?.clear();
      }
    }
  }

  /// 开始视频同步
  void _startVideoSync() {
    if (!widget.isEnabled) return;
    
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      _syncWithVideo();
    });
  }
  
  /// 暂停视频同步
  void _pauseVideoSync() {
    _syncTimer?.cancel();
  }

  /// 与视频同步
  void _syncWithVideo() {
    if (!widget.isEnabled || 
        widget.videoController == null || 
        !widget.videoController!.value.isInitialized ||
        _danmakuController == null) {
      return;
    }

    final currentPosition = widget.videoController!.value.position;
    
    // 检查视频是否在播放
    if (!widget.videoController!.value.isPlaying) {
      return;
    }
    
    // 检测视频跳转（快进/快退）
    if ((currentPosition - _lastVideoPosition).abs() > const Duration(seconds: 2)) {
      print('检测到视频跳转，重置弹幕状态');
      _processedDanmakuIndices.clear();
      _danmakuController!.clear();
    }
    
    _lastVideoPosition = currentPosition;

    // 找到需要显示的弹幕
    int addedCount = 0;
    for (int i = 0; i < widget.danmakuList.length; i++) {
      final danmaku = widget.danmakuList[i];
      
      // 如果这条弹幕已经处理过，跳过
      if (_processedDanmakuIndices.contains(i)) {
        continue;
      }
      
      // 检查是否到了显示时间
      if (danmaku.shouldShowAt(currentPosition)) {
        print('DanmakuOverlay: 显示弹幕 [${danmaku.text}] at ${currentPosition.inSeconds}s (start: ${danmaku.startTime.inSeconds}s)');
        _addDanmakuToScreen(danmaku);
        _processedDanmakuIndices.add(i);
        addedCount++;
      }
    }
    
    if (addedCount > 0) {
      print('DanmakuOverlay: 本次同步添加了 $addedCount 条弹幕');
    }
  }

  /// 添加弹幕到屏幕
  void _addDanmakuToScreen(local.DanmakuItem danmaku) {
    if (_danmakuController == null) return;

    try {
      // 根据弹幕类型创建不同的弹幕内容
      switch (danmaku.type) {
        case local.DanmakuType.floating:
          // 滚动弹幕
          _danmakuController!.addDanmaku(
            DanmakuContentItem(
              danmaku.text,
              color: danmaku.color,
            ),
          );
          break;
          
        case local.DanmakuType.top:
          // 顶部固定弹幕
          _danmakuController!.addDanmaku(
            DanmakuContentItem(
              danmaku.text,
              color: danmaku.color,
              type: DanmakuItemType.top,
            ),
          );
          break;
          
        case local.DanmakuType.bottom:
          // 底部固定弹幕
          _danmakuController!.addDanmaku(
            DanmakuContentItem(
              danmaku.text,
              color: danmaku.color,
              type: DanmakuItemType.bottom,
            ),
          );
          break;
      }
      
      print('添加弹幕: ${danmaku.text} 在 ${_lastVideoPosition.inSeconds}s');
    } catch (e) {
      print('添加弹幕失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isEnabled) {
      return const SizedBox.shrink();
    }

    return DanmakuScreen(
      createdController: (controller) {
        print('弹幕控制器创建成功');
        _danmakuController = controller;
      },
      option: DanmakuOption(
        fontSize: 25.0,
        opacity: widget.opacity,
        duration: 8, // 8秒滚动时间
        showStroke: true, // 显示描边
        area: 1.0, // 使用全屏幕区域
        massiveMode: false, // 不使用海量模式，避免弹幕重叠
        hideTop: false,
        hideScroll: false,
        hideBottom: false,
        safeArea: false, // 不预留安全区域，让弹幕贴合视频
      ),
    );
  }
} 