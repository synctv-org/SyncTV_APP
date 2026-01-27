import 'dart:ui';

/// 弹幕数据模型
class DanmakuItem {
  final String text;           // 弹幕内容
  final Duration startTime;    // 开始时间
  final Duration endTime;      // 结束时间
  final Color color;           // 弹幕颜色
  final double fontSize;       // 字体大小
  final DanmakuType type;      // 弹幕类型
  final double? moveStartX;    // 移动起始X坐标
  final double? moveEndX;      // 移动结束X坐标
  final double? positionY;     // Y坐标位置

  const DanmakuItem({
    required this.text,
    required this.startTime,
    required this.endTime,
    required this.color,
    this.fontSize = 25.0,
    this.type = DanmakuType.floating,
    this.moveStartX,
    this.moveEndX,
    this.positionY,
  });

  /// 检查弹幕是否在指定时间点应该显示
  bool shouldShowAt(Duration currentTime) {
    return currentTime >= startTime && currentTime <= endTime;
  }

  /// 计算弹幕在指定时间的X坐标位置
  double calculateXPosition(Duration currentTime, double screenWidth) {
    if (type != DanmakuType.floating) return moveStartX ?? 0;
    
    if (currentTime < startTime || currentTime > endTime) {
      return -1000; // 不在显示时间范围内
    }

    final progress = (currentTime.inMilliseconds - startTime.inMilliseconds) / 
                    (endTime.inMilliseconds - startTime.inMilliseconds);
    
    final startX = moveStartX ?? screenWidth;
    final endX = moveEndX ?? -200;
    
    return startX + (endX - startX) * progress;
  }

  @override
  String toString() {
    return 'DanmakuItem(text: $text, start: ${startTime.inSeconds}s, end: ${endTime.inSeconds}s)';
  }
}

/// 弹幕类型枚举
enum DanmakuType {
  floating,  // 飘过弹幕（从右到左）
  top,       // 顶部固定
  bottom,    // 底部固定
}

/// 弹幕样式配置
class DanmakuStyle {
  final Color defaultColor;
  final double defaultFontSize;
  final String fontFamily;
  final bool bold;
  final double outlineWidth;
  final Color outlineColor;
  final double shadowOffset;
  final Color shadowColor;

  const DanmakuStyle({
    this.defaultColor = const Color(0xFFFFFFFF),
    this.defaultFontSize = 25.0,
    this.fontFamily = '黑体',
    this.bold = true,
    this.outlineWidth = 0.8,
    this.outlineColor = const Color(0xFF000000),
    this.shadowOffset = 0.0,
    this.shadowColor = const Color(0xFF000000),
  });
} 