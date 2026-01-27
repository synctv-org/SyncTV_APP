import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';

import 'package:synctv_app/widgets/danmaku_overlay.dart';
import 'package:synctv_app/models/danmaku_model.dart';
import 'package:synctv_app/services/watch_together_service.dart';
import 'package:synctv_app/services/dlna.dart';
import 'package:synctv_app/services/xmlParser.dart';

/// Controller to manage Danmaku state and connections across fullscreen toggles
class DanmakuController extends ChangeNotifier {
  List<DanmakuItem> _items = [];
  List<DanmakuItem> get items => _items;

  http.Client? _sseClient;
  Timer? _reconnectTimer;
  VideoPlayerController? videoController;
  
  String? _danmakuUrl;
  String? _streamDanmakuUrl;
  
  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _sseClient?.close();
    super.dispose();
  }
  
  void updateConfig({String? danmakuUrl, String? streamDanmakuUrl, VideoPlayerController? controller}) {
    if (controller != null) {
      videoController = controller;
    }
    
    if (danmakuUrl != _danmakuUrl) {
      _danmakuUrl = danmakuUrl;
      _loadDanmaku();
    }
    
    if (streamDanmakuUrl != _streamDanmakuUrl) {
      _streamDanmakuUrl = streamDanmakuUrl;
      _connectDanmakuStream();
    }
  }

  void add(DanmakuItem item) {
    _items.add(item);
    if (_items.length > 500) {
      _items.removeRange(0, _items.length - 400);
    }
    notifyListeners();
  }
  
  void addItems(List<DanmakuItem> newItems) {
    _items.addAll(newItems);
    notifyListeners();
  }
  
  void clear() {
    _items.clear();
    notifyListeners();
  }

  void _loadDanmaku() async {
    _items.clear();
    notifyListeners();
    
    if (_danmakuUrl == null || _danmakuUrl!.isEmpty) return;
    try {
      String url = _danmakuUrl!;
      if (url.startsWith('/')) {
        final base = WatchTogetherService.baseUrl.replaceAll('/api', '');
        url = '$base$url';
      }
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        String content;
        try {
          content = utf8.decode(response.bodyBytes);
        } catch (e) {
          content = response.body;
        }
        _parseDanmaku(content);
      }
    } catch (e) {
      debugPrint('Failed to load danmaku: $e');
    }
  }
  
  void _parseDanmaku(String content) {
    String normalized = content
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u3000', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    
    final regex = RegExp(r'<d\s+p="([^"]*)"\s*>((?:.|\n)*?)<\/d>');
    final matches = regex.allMatches(normalized);
    
    final List<DanmakuItem> newItems = [];
    
    for (final match in matches) {
      final p = match.group(1) ?? '';
      String text = (match.group(2) ?? '').trim();
      final parts = p.split(',');
      if (parts.isNotEmpty) {
        final timeSec = double.tryParse(parts[0]) ?? 0.0;
        final mode = int.tryParse(parts.length > 1 ? parts[1] : '1') ?? 1;
        final colorInt = int.tryParse(parts.length > 3 ? parts[3] : '16777215') ?? 16777215;
        
        DanmakuType type = DanmakuType.floating;
        if (mode == 4) type = DanmakuType.bottom;
        if (mode == 5) type = DanmakuType.top;
        
        // Color is decimal RGB
        final color = Color(0xFF000000 | (colorInt & 0x00FFFFFF));
        final startTime = Duration(milliseconds: (timeSec * 1000).toInt());
        final duration = type == DanmakuType.floating ? const Duration(seconds: 8) : const Duration(seconds: 4);
        
        // Remove HTML entities if present
        text = text.replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>');
        
        newItems.add(DanmakuItem(
          text: text,
          startTime: startTime,
          endTime: startTime + duration,
          color: color,
          type: type,
        ));
      }
    }
    
    _items = newItems;
    notifyListeners();
  }
  
  void _connectDanmakuStream() async {
    _reconnectTimer?.cancel();
    _sseClient?.close();
    
    if (_streamDanmakuUrl == null || _streamDanmakuUrl!.isEmpty) return;
    
    _sseClient = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(_streamDanmakuUrl!));
      request.headers['Accept'] = 'text/event-stream';
      
      final response = await _sseClient!.send(request);
      
      if (response.statusCode == 200) {
        response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
             if (line.startsWith('data: ')) {
               final data = line.substring(6);
               _handleRealtimeDanmaku(data);
             }
          }, onError: (e) {
             debugPrint('SSE Error: $e');
             _scheduleReconnect();
          }, onDone: () {
             debugPrint('SSE Done');
             _scheduleReconnect();
          });
      } else {
        debugPrint('SSE Failed: ${response.statusCode}');
        _scheduleReconnect();
      }
    } catch (e) {
      debugPrint('SSE Connection failed: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      _connectDanmakuStream();
    });
  }

  void _handleRealtimeDanmaku(String jsonStr) {
    if (videoController == null) return;
    try {
      final data = jsonDecode(jsonStr);
      String text = '';
      Color color = Colors.white;
      DanmakuType type = DanmakuType.floating;
      
      if (data is String) {
        text = data;
      } else if (data is Map) {
        text = data['text'] ?? '';
        if (data['color'] != null) {
          try {
            String c = data['color'].toString();
            if (c.startsWith('#')) {
              c = c.substring(1);
              if (c.length == 6) {
                color = Color(int.parse('0xFF$c'));
              }
            }
          } catch (_) {}
        }
      }
      
      if (text.isNotEmpty) {
        final now = videoController!.value.position;
        final item = DanmakuItem(
          text: text,
          startTime: now, 
          endTime: now + const Duration(seconds: 8),
          color: color,
          type: type,
        );
        add(item);
      }
    } catch (e) {
      debugPrint('Danmaku parse error: $e');
    }
  }
}

class CustomVideoPlayer extends StatefulWidget {
  final VideoPlayerController controller;
  final String title;
  final DanmakuController? danmakuController;
  final Map<String, dynamic>? subtitles;
  final VoidCallback? onToggleFullScreen;
  final VoidCallback? onSync;
  final bool isFullScreen;
  final Function(String)? onSendDanmaku;

  const CustomVideoPlayer({
    super.key,
    required this.controller,
    required this.title,
    this.danmakuController,
    this.subtitles,
    this.onToggleFullScreen,
    this.onSync,
    this.isFullScreen = false,
    this.onSendDanmaku,
  });

  @override
  State<CustomVideoPlayer> createState() => _CustomVideoPlayerState();
}

class _CustomVideoPlayerState extends State<CustomVideoPlayer> with SingleTickerProviderStateMixin {
  bool _showControls = true;
  Timer? _hideTimer;
  bool _isDragging = false;
  bool _showDanmaku = true;
  
  // Gesture State
  double? _dragStartVolume;
  double? _dragStartDlnaVolume;
  double? _dragStartBrightness;
  Duration? _dragStartPosition;
  String _dragLabel = '';
  IconData _dragIcon = Icons.info;
  
  // Subtitles
  List<_SubtitleItem> _subtitleItems = [];
  String _currentSubtitle = '';
  Timer? _subtitleTimer;

  // DLNA
  final DLNAManager _dlnaManager = DLNAManager();
  Map<String, DLNADevice> _dlnaDevices = {};
  DLNADevice? _currentDlnaDevice;
  bool _isCasting = false;
  bool _isSearchingDlna = false;
  bool _dlnaIsPlaying = false;
  Duration _dlnaPosition = Duration.zero;
  Duration _dlnaDuration = Duration.zero;
  StreamSubscription? _dlnaDevicesSubscription;
  StreamSubscription? _dlnaPositionSubscription;

  @override
  void initState() {
    super.initState();
    if (widget.isFullScreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    widget.controller.addListener(_videoListener);
    widget.danmakuController?.addListener(_onDanmakuUpdate);
    _startHideTimer();
    _loadSubtitles();
  }

  void _onDanmakuUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(CustomVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_videoListener);
      widget.controller.addListener(_videoListener);
    }
    
    if (widget.danmakuController != oldWidget.danmakuController) {
      oldWidget.danmakuController?.removeListener(_onDanmakuUpdate);
      widget.danmakuController?.addListener(_onDanmakuUpdate);
    }

    if (widget.subtitles != oldWidget.subtitles) {
      _loadSubtitles();
    }
  }

  @override
  void dispose() {
    if (widget.isFullScreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    widget.controller.removeListener(_videoListener);
    widget.danmakuController?.removeListener(_onDanmakuUpdate);
    _hideTimer?.cancel();
    _subtitleTimer?.cancel();
    _stopDlna();
    super.dispose();
  }

  void _stopDlna() {
    _dlnaManager.stop();
    _dlnaDevicesSubscription?.cancel();
    _dlnaPositionSubscription?.cancel();
    _currentDlnaDevice?.positionPoller.stop();
    _currentDlnaDevice = null;
    _isCasting = false;
  }

  void _videoListener() {
    if (mounted) {
      setState(() {});
      if (_subtitleItems.isNotEmpty) {
        final position = _isCasting ? _dlnaPosition : widget.controller.value.position;
        final current = _subtitleItems.firstWhere(
          (item) => item.start <= position && item.end >= position,
          orElse: () => _SubtitleItem(Duration.zero, Duration.zero, ''),
        );
        if (_currentSubtitle != current.text) {
          _currentSubtitle = current.text;
        }
      }
    }
  }

  void _loadSubtitles([String? specificUrl]) async {
    _subtitleItems.clear();
    _currentSubtitle = '';
    
    // If specific URL provided (or null to clear), use it
    if (specificUrl != null) {
       await _fetchAndParseSubtitles(specificUrl);
       return;
    }

    // Otherwise load default
    if (widget.subtitles == null || widget.subtitles!.isEmpty) return;

    // Prefer 'zh' or 'chi' or 'Chinese', otherwise first
    String? url;
    String? defaultKey;
    
    // First pass: look for Chinese
    for (var key in widget.subtitles!.keys) {
      if (key.toLowerCase().contains('zh') || 
          key.toLowerCase().contains('chi') || 
          key.toLowerCase().contains('中')) {
        if (widget.subtitles![key] is Map) {
           url = widget.subtitles![key]['url'];
           defaultKey = key;
           break;
        }
      }
    }
    
    // Second pass: take first available if no Chinese found
    if (url == null) {
      for (var key in widget.subtitles!.keys) {
        if (widget.subtitles![key] is Map) {
           url = widget.subtitles![key]['url'];
           defaultKey = key;
           break;
        }
      }
    }
    
    if (url != null) {
      debugPrint('Loading default subtitle: $defaultKey');
      await _fetchAndParseSubtitles(url);
    }
  }

  Future<void> _fetchAndParseSubtitles(String url) async {
      try {
        Uri uri = Uri.parse(url);
        if (!uri.hasScheme) {
           final baseUri = Uri.parse(WatchTogetherService.baseUrl);
           final origin = '${baseUri.scheme}://${baseUri.host}${baseUri.hasPort ? ':${baseUri.port}' : ''}';
           uri = Uri.parse('$origin$url');
           debugPrint('Resolved relative subtitle URL to: $uri');
        }

        final response = await http.get(uri);
        if (response.statusCode == 200) {
          // Robust decoding (handles UTF-16 BOM)
          String content = _decodeSubtitleContent(response.bodyBytes);
          
          // Debug content header
          debugPrint('Subtitle Content Start: ${content.substring(0, min(200, content.length)).replaceAll('\n', '\\n')}');
          
          // Determine format
          if (content.contains('[Script Info]') || content.contains('[Events]')) {
             _parseAssSubtitles(content);
          } else {
             _parseSubtitles(content);
          }
          
          if (mounted) setState(() {});
        } else {
          debugPrint('Failed to load subtitles: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('Failed to load subtitles: $e');
      }
  }

  String _decodeSubtitleContent(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      debugPrint('Detected UTF-16 LE BOM');
      final List<int> codes = [];
      for (int i = 2; i < bytes.length - 1; i += 2) {
        codes.add(bytes[i] | (bytes[i + 1] << 8));
      }
      return String.fromCharCodes(codes);
    }

    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      debugPrint('Detected UTF-16 BE BOM');
      final List<int> codes = [];
      for (int i = 2; i < bytes.length - 1; i += 2) {
        codes.add((bytes[i] << 8) | bytes[i + 1]);
      }
      return String.fromCharCodes(codes);
    }

    int start = 0;
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      debugPrint('Detected UTF-8 BOM');
      start = 3;
    }

    try {
      return utf8.decode(bytes.sublist(start), allowMalformed: false);
    } catch (e) {
      debugPrint('UTF-8 decode failed, trying lenient decode: $e');
      // 5. Fallback to lenient UTF-8
      return utf8.decode(bytes, allowMalformed: true);
    }
  }


  void _parseAssSubtitles(String content) {
    if (content.contains('Script generated by danmu2ass')) {
      debugPrint('Detected danmu2ass script, parsing as Danmaku...');
      _parseAssToDanmaku(content);
      return;
    }

    debugPrint('Parsing ASS subtitles...');
    _subtitleItems.clear();
    final lines = LineSplitter.split(content).toList();
    
    int formatIndex = -1;
    List<String> formatFields = [];
    
    bool inEvents = false;
    
    for (String line in lines) {
      line = line.trim();
      if (line == '[Events]') {
        inEvents = true;
        continue;
      }
      
      if (!inEvents) continue;
      
      if (line.startsWith('Format:')) {
        final formatStr = line.substring(7).trim();
        formatFields = formatStr.split(',').map((e) => e.trim().toLowerCase()).toList();
        debugPrint('ASS Format: $formatFields');
        continue;
      }
      
      if (line.startsWith('Dialogue:')) {

        if (formatFields.isEmpty) {
           formatFields = ['layer', 'start', 'end', 'style', 'name', 'marginl', 'marginr', 'marginv', 'effect', 'text'];
        }
        
        final contentStr = line.substring(9).trim();
        
        List<String> parts = [];
        int currentStart = 0;
        for (int i = 0; i < formatFields.length - 1; i++) {
          int commaIndex = contentStr.indexOf(',', currentStart);
          if (commaIndex == -1) break;
          parts.add(contentStr.substring(currentStart, commaIndex));
          currentStart = commaIndex + 1;
        }
        // The rest is the text
        if (currentStart < contentStr.length) {
          parts.add(contentStr.substring(currentStart));
        } else {
           parts.add('');
        }
        
        if (parts.length == formatFields.length) {
          try {
            int startIndex = formatFields.indexOf('start');
            int endIndex = formatFields.indexOf('end');
            int textIndex = formatFields.indexOf('text');
            
            if (startIndex != -1 && endIndex != -1 && textIndex != -1) {
              final start = _parseAssDuration(parts[startIndex]);
              final end = _parseAssDuration(parts[endIndex]);
              String text = parts[textIndex];
              
              text = text.replaceAll(RegExp(r'\{.*?\}'), '');
              // Replace \N with newline
              text = text.replaceAll(r'\N', '\n');
              text = text.trim();
              
              if (text.isNotEmpty) {
                _subtitleItems.add(_SubtitleItem(start, end, text));
              }
            }
          } catch (e) {
          }
        }
      }
    }
    debugPrint('Parsed ${_subtitleItems.length} ASS subtitles');
  }

  void _parseAssToDanmaku(String content) {
    if (widget.danmakuController == null) return;
    
    final lines = LineSplitter.split(content).toList();
    List<DanmakuItem> danmakuItems = [];
    
    List<String> formatFields = [];
    bool inEvents = false;
    
    for (String line in lines) {
      line = line.trim();
      if (line == '[Events]') {
        inEvents = true;
        continue;
      }
      if (!inEvents) continue;
      
      if (line.startsWith('Format:')) {
        final formatStr = line.substring(7).trim();
        formatFields = formatStr.split(',').map((e) => e.trim().toLowerCase()).toList();
        continue;
      }
      
      if (line.startsWith('Dialogue:')) {
        if (formatFields.isEmpty) {
           formatFields = ['layer', 'start', 'end', 'style', 'name', 'marginl', 'marginr', 'marginv', 'effect', 'text'];
        }
        
        final contentStr = line.substring(9).trim();
        List<String> parts = [];
        int currentStart = 0;
        for (int i = 0; i < formatFields.length - 1; i++) {
          int commaIndex = contentStr.indexOf(',', currentStart);
          if (commaIndex == -1) break;
          parts.add(contentStr.substring(currentStart, commaIndex));
          currentStart = commaIndex + 1;
        }
        if (currentStart < contentStr.length) {
          parts.add(contentStr.substring(currentStart));
        } else {
           parts.add('');
        }
        
        if (parts.length == formatFields.length) {
          try {
            int startIndex = formatFields.indexOf('start');
            int endIndex = formatFields.indexOf('end');
            int textIndex = formatFields.indexOf('text');
            int styleIndex = formatFields.indexOf('style');
            
            if (startIndex != -1 && endIndex != -1 && textIndex != -1) {
              final start = _parseAssDuration(parts[startIndex]);
              final end = _parseAssDuration(parts[endIndex]);
              String rawText = parts[textIndex];
              String style = styleIndex != -1 ? parts[styleIndex] : '';
              
              // Extract color from tags if present {\c&HBBGGRR&}
              Color color = Colors.white;
              final colorMatch = RegExp(r'\\c&H([0-9a-fA-F]{6})&').firstMatch(rawText);
              if (colorMatch != null) {
                final hex = colorMatch.group(1)!; // BBGGRR
                final b = int.parse(hex.substring(0, 2), radix: 16);
                final g = int.parse(hex.substring(2, 4), radix: 16);
                final r = int.parse(hex.substring(4, 6), radix: 16);
                color = Color.fromARGB(255, r, g, b);
              }
              
              // Remove tags
              String text = rawText.replaceAll(RegExp(r'\{.*?\}'), '').replaceAll(r'\N', '\n').trim();
              
              if (text.isNotEmpty) {
                DanmakuType type = DanmakuType.floating;
                if (style.toLowerCase().contains('top')) type = DanmakuType.top;
                if (style.toLowerCase().contains('bottom')) type = DanmakuType.bottom;
                
                danmakuItems.add(DanmakuItem(
                  text: text,
                  startTime: start,
                  endTime: end, // DanmakuOverlay uses internal duration usually, but we can pass it
                  color: color,
                  type: type,
                ));
              }
            }
          } catch (e) {
            // ignore
          }
        }
      }
    }
    
    _subtitleItems.clear();
    
    // Add to danmaku controller
    widget.danmakuController!.clear();
    widget.danmakuController!.addItems(danmakuItems);
    debugPrint('Parsed and added ${danmakuItems.length} danmaku items from ASS');
    
    // Enable danmaku if not already
    if (!_showDanmaku) {
      setState(() {
        _showDanmaku = true;
      });
    }
  }


  Duration _parseAssDuration(String s) {
    // h:mm:ss.cc
    final parts = s.split(':');
    
    int hours = int.parse(parts[0]);
    int minutes = int.parse(parts[1]);
    final secParts = parts[2].split('.');
    int seconds = int.parse(secParts[0]);
    int centiseconds = int.parse(secParts[1]);
    
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: centiseconds * 10,
    );
  }

  void _parseSubtitles(String content) {
    _subtitleItems.clear();
    final lines = LineSplitter.split(content).toList();
    final regex = RegExp(r'((?:\d{2}:)?\d{2}:\d{2}[.,]\d{3}) --> ((?:\d{2}:)?\d{2}:\d{2}[.,]\d{3})');
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      final match = regex.firstMatch(line);
      if (match != null) {
        try {
          final start = _parseDuration(match.group(1)!);
          final end = _parseDuration(match.group(2)!);
          
          String text = '';
          int j = i + 1;
          while (j < lines.length && lines[j].trim().isNotEmpty) {
            text += '${lines[j].trim()}\n';
            j++;
          }
          
          if (text.isNotEmpty) {
            _subtitleItems.add(_SubtitleItem(start, end, text.trim()));
          }
          i = j;
        } catch (e) {
          debugPrint('Error parsing subtitle line: $line, error: $e');
        }
      }
    }
    debugPrint('Parsed ${_subtitleItems.length} subtitles');
  }

  Duration _parseDuration(String s) {
    final parts = s.split(':');
    int hours = 0;
    int minutes = 0;
    int seconds = 0;
    int milliseconds = 0;
    
    if (parts.length == 3) {
      hours = int.parse(parts[0]);
      minutes = int.parse(parts[1]);
      final secondsParts = parts[2].split(RegExp(r'[.,]'));
      seconds = int.parse(secondsParts[0]);
      milliseconds = int.parse(secondsParts[1]);
    } else if (parts.length == 2) {
      minutes = int.parse(parts[0]);
      final secondsParts = parts[1].split(RegExp(r'[.,]'));
      seconds = int.parse(secondsParts[0]);
      milliseconds = int.parse(secondsParts[1]);
    }
    
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && widget.controller.value.isPlaying && !_isDragging) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) _startHideTimer();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _isDragging = true;
    _dragStartPosition = widget.controller.value.position;
    _hideTimer?.cancel();
    setState(() {
      _showControls = true;
      _dragLabel = _formatDuration(_dragStartPosition!);
      _dragIcon = Icons.fast_forward;
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_dragStartPosition == null) return;
    
    final duration = widget.controller.value.duration.inMilliseconds.toDouble();
    final deltaMs = details.primaryDelta! * 200; 
    
    final currentMs = _dragStartPosition!.inMilliseconds.toDouble();
    final newPosMs = (currentMs + deltaMs).clamp(0.0, duration);
    _dragStartPosition = Duration(milliseconds: newPosMs.toInt());
    
    setState(() {
      _dragLabel = '${_formatDuration(_dragStartPosition!)} / ${_formatDuration(widget.controller.value.duration)}';
      _dragIcon = details.primaryDelta! > 0 ? Icons.fast_forward : Icons.fast_rewind;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    _isDragging = false;
    if (_dragStartPosition != null) {
      widget.controller.seekTo(_dragStartPosition!);
    }
    _startHideTimer();
    setState(() {
      _dragLabel = '';
    });
  }

  void _onVerticalDragStart(DragStartDetails details) async {
    final width = MediaQuery.of(context).size.width;
    final isLeft = details.globalPosition.dx < width / 2;
    
    if (isLeft) {
      _dragStartBrightness = await ScreenBrightness().current;
      setState(() {
        _dragIcon = Icons.brightness_6;
        _dragLabel = '亮度';
      });
    } else {
      if (_isCasting) {
        try {
          final volXml = await _currentDlnaDevice?.getVolume();
          if (volXml != null) {
            _dragStartDlnaVolume = VolumeParser(volXml).current.toDouble();
          }
        } catch (e) {
          debugPrint('Failed to get DLNA volume: $e');
          _dragStartDlnaVolume = 0;
        }
      } else {
        _dragStartVolume = await FlutterVolumeController.getVolume();
      }
      setState(() {
        _dragIcon = Icons.volume_up;
        _dragLabel = '音量';
      });
    }
    _showControls = true;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) async {
    final delta = details.primaryDelta! / -200; // Up is negative, so invert
    
    if (_dragStartBrightness != null) {
      final newVal = (_dragStartBrightness! + delta).clamp(0.0, 1.0);
      await ScreenBrightness().setScreenBrightness(newVal);
      _dragStartBrightness = newVal; // accumulate
      setState(() {
        _dragLabel = '亮度 ${(newVal * 100).toInt()}%';
      });
    } else if (_dragStartDlnaVolume != null) {
      final dlnaDelta = details.primaryDelta! / -2.0; 
      final newVal = (_dragStartDlnaVolume! + dlnaDelta).clamp(0.0, 100.0);
      
      final newInt = newVal.toInt();
      if (newInt != _dragStartDlnaVolume!.toInt()) {
         _currentDlnaDevice?.volume(newInt);
      }
      _dragStartDlnaVolume = newVal;

      setState(() {
        _dragLabel = '音量 $newInt%';
      });
    } else if (_dragStartVolume != null) {
      final newVal = (_dragStartVolume! + delta).clamp(0.0, 1.0);
      await FlutterVolumeController.setVolume(newVal);
      _dragStartVolume = newVal;
      setState(() {
        _dragLabel = '音量 ${(newVal * 100).toInt()}%';
      });
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _dragStartBrightness = null;
    _dragStartVolume = null;
    _dragStartDlnaVolume = null;
    setState(() {
      _dragLabel = '';
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  void _showDlnaMenu() {
    _dlnaDevices.clear();
    _isSearchingDlna = true;
    
    StateSetter? sheetSetState;

    _dlnaManager.start().then((manager) {
      _dlnaDevicesSubscription?.cancel();
      _dlnaDevicesSubscription = manager.devices.stream.listen((devices) {
        if (mounted) {
          setState(() {
            _dlnaDevices = devices;
          });
          sheetSetState?.call(() {});
        }
      });
    });

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          sheetSetState = setSheetState;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('投屏设备', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      if (_isSearchingDlna)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white24, height: 1),
                if (_isCasting && _currentDlnaDevice != null)
                  ListTile(
                    leading: const Icon(Icons.cast_connected, color: Color(0xFF5D5FEF)),
                    title: Text('正在投屏: ${_currentDlnaDevice!.info.friendlyName}', style: const TextStyle(color: Color(0xFF5D5FEF))),
                    trailing: TextButton(
                      onPressed: () {
                        // Stop casting
                        _currentDlnaDevice!.stop();
                        _currentDlnaDevice!.positionPoller.stop();
                        _dlnaPositionSubscription?.cancel();
                        setState(() {
                          _isCasting = false;
                          _currentDlnaDevice = null;
                        });
                        // Resume local player
                        widget.controller.seekTo(_dlnaPosition);
                        widget.controller.play();
                        Navigator.pop(context);
                      },
                      child: const Text('退出投屏', style: TextStyle(color: Colors.red)),
                    ),
                  ),
                if (_dlnaDevices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('正在搜索设备...', style: TextStyle(color: Colors.white54)),
                  ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: _dlnaDevices.values.map((device) {
                        final isSelected = _currentDlnaDevice == device;
                        return ListTile(
                          leading: Icon(Icons.tv, color: isSelected ? const Color(0xFF5D5FEF) : Colors.white),
                          title: Text(device.info.friendlyName, style: TextStyle(color: isSelected ? const Color(0xFF5D5FEF) : Colors.white)),
                          onTap: () async {
                            Navigator.pop(context);
                            _connectToDlnaDevice(device);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      _isSearchingDlna = false;
      _dlnaManager.stop();
    });
  }

  Future<void> _connectToDlnaDevice(DLNADevice device) async {
    widget.controller.pause();
    
    setState(() {
      _currentDlnaDevice = device;
      _isCasting = true;
      _dlnaIsPlaying = true;
    });

    try {
      final url = widget.controller.dataSource;
      debugPrint('Casting to ${device.info.friendlyName}: $url');
      
      PlayType type = VideoMime.any;
      if (url.endsWith('.mp4')) type = VideoMime.mp4;
      if (url.endsWith('.mkv')) type = VideoMime.xMatroska;
      
      await device.setUrl(url, title: widget.title, type: type);
      await device.play();
      
      device.positionPoller.start();
      _dlnaPositionSubscription?.cancel();
      _dlnaPositionSubscription = device.currPosition.stream.listen((position) {
        if (mounted) {
          setState(() {
            _dlnaPosition = Duration(seconds: position.RelTimeInt);
            _dlnaDuration = Duration(seconds: position.TrackDurationInt);
          });
        }
      });
      
      final currentPos = widget.controller.value.position;
      if (currentPos > Duration.zero) {
        await device.seek(_formatDurationDlna(currentPos));
      }
      
    } catch (e) {
      debugPrint('DLNA Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('投屏失败: $e')));
        setState(() {
          _isCasting = false;
          _currentDlnaDevice = null;
        });
      }
    }
  }

  String _formatDurationDlna(Duration d) {
    // HH:MM:SS
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  void _showSubtitleMenu() {
    if (widget.subtitles == null || widget.subtitles!.isEmpty) {
      return;
    }
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择字幕', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.close, color: Colors.white),
              title: const Text('关闭字幕', style: TextStyle(color: Colors.white)),
              onTap: () {
                setState(() {
                  _subtitleItems.clear();
                  _currentSubtitle = '';
                });
                Navigator.pop(context);
              },
            ),
            const Divider(color: Colors.white24, height: 1),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: widget.subtitles!.entries.map((e) {
                    final label = e.key;
                    final url = e.value is Map ? e.value['url'] : null;
                    return ListTile(
                      title: Text(label, style: const TextStyle(color: Colors.white)),
                      onTap: () {
                        if (url != null) _loadSubtitles(url);
                        Navigator.pop(context);
                      },
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDanmakuInput() {
    final textController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E2C),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: textController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: '发个弹幕见证当下...',
                      hintStyle: TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (value) {
                       if (value.trim().isNotEmpty) {
                         widget.onSendDanmaku?.call(value.trim());
                         Navigator.pop(context);
                       }
                    },
                    autofocus: true,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Color(0xFF5D5FEF)),
                  onPressed: () {
                    if (textController.text.trim().isNotEmpty) {
                      widget.onSendDanmaku?.call(textController.text.trim());
                      Navigator.pop(context);
                    }
                  },
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
    final videoValue = widget.controller.value;
    final currentPosition = _isCasting ? _dlnaPosition : videoValue.position;
    final totalDuration = _isCasting ? _dlnaDuration : videoValue.duration;
    final isPlaying = _isCasting ? _dlnaIsPlaying : videoValue.isPlaying; 
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        onDoubleTap: () {
          if (_isCasting) {
             if (_dlnaIsPlaying) {
               _currentDlnaDevice?.pause();
             } else {
               _currentDlnaDevice?.play();
             }
             setState(() {
               _dlnaIsPlaying = !_dlnaIsPlaying;
             });
          } else {
            videoValue.isPlaying ? widget.controller.pause() : widget.controller.play();
          }
        },
        onHorizontalDragStart: _onHorizontalDragStart,
        onHorizontalDragUpdate: _onHorizontalDragUpdate,
        onHorizontalDragEnd: _onHorizontalDragEnd,
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_isCasting)
              Container(
                color: Colors.black,
                width: double.infinity,
                height: double.infinity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cast_connected, color: Colors.white54, size: 80),
                    const SizedBox(height: 24),
                    const Text(
                      '正在投屏中',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _currentDlnaDevice?.info.friendlyName ?? '未知设备',
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ],
                ),
              )
            else
              Center(
                child: AspectRatio(
                  aspectRatio: videoValue.aspectRatio > 0 ? videoValue.aspectRatio : 16/9,
                  child: VideoPlayer(widget.controller),
                ),
              ),
            
            Positioned.fill(
              child: DanmakuOverlay(
                videoController: widget.controller,
                danmakuList: widget.danmakuController?.items ?? [],
                isEnabled: _showDanmaku,
              ),
            ),
            
            if (_currentSubtitle.isNotEmpty)
              Positioned(
                bottom: widget.isFullScreen ? 40 : 10,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  // Transparent background as requested
                  color: Colors.transparent,
                  child: Text(
                    _currentSubtitle,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.isFullScreen ? 24 : 14,
                      shadows: const [
                        Shadow(
                          offset: Offset(0, 1),
                          blurRadius: 3.0,
                          color: Colors.black,
                        ),
                        Shadow(
                          offset: Offset(0, -1),
                          blurRadius: 3.0,
                          color: Colors.black,
                        ),
                        Shadow(
                          offset: Offset(1, 0),
                          blurRadius: 3.0,
                          color: Colors.black,
                        ),
                        Shadow(
                          offset: Offset(-1, 0),
                          blurRadius: 3.0,
                          color: Colors.black,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              
            if (_dragLabel.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_dragIcon, color: Colors.white, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      _dragLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
              
            IgnorePointer(
              ignoring: !_showControls,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Stack(
                children: [
                  // Top Bar
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black87, Colors.transparent],
                          ),
                        ),
                        child: Row(
                          children: [
                            if (widget.isFullScreen)
                              BackButton(color: Colors.white, onPressed: widget.onToggleFullScreen),
                            Expanded(
                              child: Text(
                                widget.title,
                                style: const TextStyle(color: Colors.white, fontSize: 16),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.onSync != null && !widget.isFullScreen) ...[
                              TextButton(
                                onPressed: widget.onSync,
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  minimumSize: const Size(48, 32),
                                  tapTargetSize: MaterialTapTargetSize.padded,
                                ),
                                child: const Text('同步', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ),
                            ],
                          IconButton(
                              icon: Icon(
                                _isCasting ? Icons.cast_connected : Icons.cast,
                                color: _isCasting ? const Color(0xFF5D5FEF) : Colors.white,
                              ),
                              onPressed: _showDlnaMenu,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // Bottom Bar
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  if (_isCasting) {
                                     if (_dlnaIsPlaying) {
                                       _currentDlnaDevice?.pause();
                                     } else {
                                       _currentDlnaDevice?.play();
                                     }
                                     setState(() {
                                       _dlnaIsPlaying = !_dlnaIsPlaying;
                                     });
                                  } else {
                                    videoValue.isPlaying ? widget.controller.pause() : widget.controller.play();
                                  }
                                },
                                child: Icon(
                                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatDuration(currentPosition),
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: widget.isFullScreen ? 6 : 8),
                                    trackHeight: widget.isFullScreen ? 2 : 4,
                                    overlayShape: RoundSliderOverlayShape(overlayRadius: widget.isFullScreen ? 12 : 20),
                                    activeTrackColor: const Color(0xFF5D5FEF),
                                    inactiveTrackColor: Colors.white24,
                                    thumbColor: Colors.white,
                                  ),
                                  child: Slider(
                                    value: currentPosition.inMilliseconds.toDouble().clamp(0, totalDuration.inMilliseconds.toDouble()),
                                    min: 0,
                                    max: totalDuration.inMilliseconds.toDouble() > 0 ? totalDuration.inMilliseconds.toDouble() : 1.0,
                                    onChanged: (value) {
                                      _startHideTimer(); // Reset timer
                                      setState(() {
                                      });
                                      final target = Duration(milliseconds: value.toInt());
                                      if (_isCasting) {
                                        _currentDlnaDevice?.seek(_formatDurationDlna(target));
                                      } else {
                                        widget.controller.seekTo(target);
                                      }
                                    },
                                  ),
                                ),
                              ),
                              Text(
                                _formatDuration(totalDuration),
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                              SizedBox(width: widget.isFullScreen ? 8 : 4),
                              if (widget.subtitles != null && widget.subtitles!.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.closed_caption_rounded, color: Colors.white),
                                  onPressed: _showSubtitleMenu,
                                  padding: widget.isFullScreen ? const EdgeInsets.all(8) : EdgeInsets.zero,
                                  constraints: widget.isFullScreen ? null : const BoxConstraints(),
                                  iconSize: widget.isFullScreen ? 24 : 20,
                                ),
                              SizedBox(width: widget.isFullScreen ? 0 : 4),
                              // Danmaku Toggle
                              IconButton(
                                icon: Icon(
                                  Icons.comment_rounded,
                                  color: _showDanmaku ? const Color(0xFF5D5FEF) : Colors.white,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _showDanmaku = !_showDanmaku;
                                  });
                                },
                                padding: widget.isFullScreen ? const EdgeInsets.all(8) : EdgeInsets.zero,
                                constraints: widget.isFullScreen ? null : const BoxConstraints(),
                                iconSize: widget.isFullScreen ? 24 : 20,
                              ),
                              // Send Danmaku Button (Fullscreen only)
                              if (widget.isFullScreen && widget.onSendDanmaku != null)
                                IconButton(
                                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                                  onPressed: _showDanmakuInput,
                                  tooltip: '发送弹幕',
                                ),
                              if (widget.onSync != null && widget.isFullScreen) ...[
                                const SizedBox(width: 0),
                                TextButton(
                                  onPressed: widget.onSync,
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    minimumSize: const Size(0, 40),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text('同步', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                ),
                              ],
                              if (widget.onToggleFullScreen != null) ...[
                                SizedBox(width: widget.isFullScreen ? 0 : 4),
                                IconButton(
                                  icon: Icon(
                                    widget.isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                    color: Colors.white,
                                  ),
                                  onPressed: widget.onToggleFullScreen,
                                  padding: widget.isFullScreen ? const EdgeInsets.all(8) : EdgeInsets.zero,
                                  constraints: widget.isFullScreen ? null : const BoxConstraints(),
                                  iconSize: widget.isFullScreen ? 24 : 20,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ],
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubtitleItem {
  final Duration start;
  final Duration end;
  final String text;

  _SubtitleItem(this.start, this.end, this.text);
}
