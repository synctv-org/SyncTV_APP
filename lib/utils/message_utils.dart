import 'package:flutter/material.dart';

/// 统一的系统消息工具类
class MessageUtils {
  /// 私有构造函数，防止实例化
  MessageUtils._();

  /// 默认的底部边距（考虑导航栏高度）
  static EdgeInsets _getDefaultMargin(BuildContext context) {
    return EdgeInsets.only(
      bottom: 70 + MediaQuery.of(context).padding.bottom,
      left: 20,
      right: 20,
    );
  }

  /// 默认的形状
  static RoundedRectangleBorder get _defaultShape {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
  }

  /// 显示成功消息
  static void showSuccess(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        margin: _getDefaultMargin(context),
        shape: _defaultShape,
        action: action,
      ),
    );
  }

  /// 显示错误消息
  static void showError(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        margin: _getDefaultMargin(context),
        shape: _defaultShape,
        action: action,
      ),
    );
  }

  /// 显示警告消息
  static void showWarning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.orange.shade600,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        margin: _getDefaultMargin(context),
        shape: _defaultShape,
        action: action,
      ),
    );
  }

  /// 显示信息消息
  static void showInfo(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blue.shade700,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        margin: _getDefaultMargin(context),
        shape: _defaultShape,
        action: action,
      ),
    );
  }

  /// 显示删除操作消息（带撤销功能）
  static void showDelete(
    BuildContext context,
    String message, {
    required VoidCallback onUndo,
    Duration duration = const Duration(seconds: 3),
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: isDark ? Colors.grey.shade900 : Colors.grey.shade800,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        margin: _getDefaultMargin(context),
        shape: _defaultShape,
        action: SnackBarAction(
          label: '撤销',
          textColor: Colors.white,
          onPressed: onUndo,
        ),
      ),
    );
  }

  /// 显示自定义颜色的消息
  static void showCustom(
    BuildContext context,
    String message, {
    required Color backgroundColor,
    Color textColor = Colors.white,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: textColor),
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        margin: _getDefaultMargin(context),
        shape: _defaultShape,
        action: action,
      ),
    );
  }

  /// 显示开关状态变更消息
  static void showToggle(
    BuildContext context,
    String message, {
    required bool isEnabled,
    Duration duration = const Duration(seconds: 2),
  }) {
    showCustom(
      context,
      message,
      backgroundColor: isEnabled ? Colors.green.shade600 : Colors.orange.shade600,
      duration: duration,
    );
  }

  /// 显示加载中消息（带圆形进度指示器）
  static void showLoading(
    BuildContext context,
    String message, {
    Duration? duration,
    Color? indicatorColor,
  }) {
    final theme = Theme.of(context);
    
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  indicatorColor ?? Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blue.shade700,
        behavior: SnackBarBehavior.floating,
        duration: duration ?? const Duration(seconds: 5), // 默认较长时间，通常需要手动关闭
        margin: _getDefaultMargin(context),
        shape: _defaultShape,
      ),
    );
  }
} 