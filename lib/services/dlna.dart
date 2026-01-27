import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'xmlParser.dart';

String removeTrailing(String pattern, String from) {
  int i = from.length;
  while (from.startsWith(pattern, i - pattern.length)) {
    i -= pattern.length;
  }
  return from.substring(0, i);
}

String trimLeading(String pattern, String from) {
  int i = 0;
  while (from.startsWith(pattern, i)) {
    i += pattern.length;
  }
  return from.substring(i);
}

String htmlEncode(String text) {
  Map<String, String> mapping = Map.from({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "'": "&#39;",
    '"': '&quot;',
  });
  mapping.forEach((key, value) {
    text = text.replaceAll(key, value);
  });
  return text;
}

class DLNADevice {
  final DeviceInfo info;
  final _rendering_control = Set.from([
    'SetMute',
    'GetMute',
    'SetVolume',
    'GetVolume',
  ]);
  DateTime activeTime = DateTime.now();
  final currPosition = StreamController<PositionParser>.broadcast();

  late final PositionPoller positionPoller;
  DLNADevice(this.info) {
    positionPoller = PositionPoller(this, this.currPosition);
  }

  void updateActive(DateTime t) {
    activeTime = t;
  }

  String controlURL(String type) {
    final base = removeTrailing("/", info.URLBase);
    final s = info.serviceList.firstWhere(
      (element) => element['serviceId'].contains(type),
    );
    if (s != null) {
      final controlURL = trimLeading("/", s["controlURL"]);
      return base + '/' + controlURL;
    }
    throw Exception("not found controlURL");
  }

  Future<String> request(String action, List<int> data) {
    final soapAction = _rendering_control.contains(action)
        ? 'RenderingControl'
        : 'AVTransport';
    final Map<String, Object> headers = Map.from({
      'SOAPAction': '"urn:schemas-upnp-org:service:$soapAction:1#$action"',
      'Content-Type': 'text/xml',
    });
    return DLNAHttp.post(Uri.parse(controlURL(soapAction)), headers, data);
  }

  Future<String> setUrl(
    String url, {
    String title = "",
    PlayType type = VideoMime.any,
  }) {
    final data = XmlText.setPlayURLXml(url, title: title, type: type);
    return request('SetAVTransportURI', Utf8Encoder().convert(data));
  }

  Future<String> play() {
    final data = XmlText.playActionXml();
    return request('Play', Utf8Encoder().convert(data));
  }

  Future<String> pause() {
    final data = XmlText.pauseActionXml();
    return request('Pause', Utf8Encoder().convert(data));
  }

  Future<String> stop() {
    final data = XmlText.stopActionXml();
    return request('Stop', Utf8Encoder().convert(data));
  }

  Future<String> seek(String sk) {
    final data = XmlText.seekToXml(sk);
    return request('Seek', Utf8Encoder().convert(data));
  }

  Future<String> position() {
    final data = XmlText.getPositionXml();
    return request('GetPositionInfo', Utf8Encoder().convert(data));
  }

  Future<String> seekByCurrent(String text, int n) {
    final p = PositionParser(text);
    final sk = p.seek(n);
    return seek(sk);
  }

  Future<String> getCurrentTransportActions() {
    final data = XmlText.getCurrentTransportActionsXml();
    return request('GetCurrentTransportActions', Utf8Encoder().convert(data));
  }

  Future<String> getMediaInfo() {
    final data = XmlText.getMediaInfoXml();
    return request('GetMediaInfo', Utf8Encoder().convert(data));
  }

  Future<String> getTransportInfo() {
    final data = XmlText.getTransportInfoXml();
    return request('GetTransportInfo', Utf8Encoder().convert(data));
  }

  Future<String> next() {
    final data = XmlText.nextXml();
    return request('Next', Utf8Encoder().convert(data));
  }

  Future<String> previous() {
    final data = XmlText.previousXml();
    return request('Previous', Utf8Encoder().convert(data));
  }

  Future<String> setPlayMode(String modeName) {
    final data = XmlText.setPlayModeXml(modeName);
    return request('SetPlayMode', Utf8Encoder().convert(data));
  }

  Future<String> getDeviceCapabilities() {
    final data = XmlText.getDeviceCapabilitiesXml();
    return request('GetDeviceCapabilities', Utf8Encoder().convert(data));
  }

  Future<String> mute(bool mute) {
    final data = XmlText.muteXml(mute);
    return request('SetMute', Utf8Encoder().convert(data));
  }

  Future<String> getMute() {
    final data = XmlText.muteStateXml();
    return request('GetMute', Utf8Encoder().convert(data));
  }

  Future<String> volume(int volume) {
    final data = XmlText.volumeXml(volume);
    return request('SetVolume', Utf8Encoder().convert(data));
  }

  Future<String> getVolume() {
    final data = XmlText.volumeStateXml();
    return request('GetVolume', Utf8Encoder().convert(data));
  }

  Future<String> changeVolume(int value) async {
    final v = VolumeParser(await getVolume()).change(value);
    return await volume(v);
  }

  void dispose() {
    currPosition.close();
    positionPoller.stop();
  }
}

class PositionPoller {
  final DLNADevice _dev;
  StreamController<PositionParser> position;
  Timer? _timer;
  bool _isPolling = false;
  PositionPoller(this._dev, this.position);

  void start() {
    if (_isPolling) {
      return;
    }
    _isPolling = true;
    _fetchPositionPeriodically();
  }

  void stop() {
    if (!_isPolling) {
      return;
    }
    _isPolling = false;
    _timer?.cancel();
  }

  void _fetchPositionPeriodically() async {
    // 安全检查：如果轮询已通过 stop() 停止，则立即退出
    if (!_isPolling) {
      return;
    }
    try {
      final text = await _dev.position();
      // 安全检查：在 await 期间，轮询可能已被外部调用 stop() 停止
      if (!_isPolling) return;
      // 更新内部状态
      position.add(PositionParser(text));
    } catch (e) {
      // 捕获请求或解析过程中可能发生的异常,2秒后重新开始轮询
      print("$e. Will try again after 2 seconds.");
    } finally {
      // 无论成功或失败，只要轮询标志为 true，就安排下一次调用
      if (_isPolling) {
        _timer = Timer(const Duration(seconds: 2), _fetchPositionPeriodically);
      }
    }
  }
}

class XmlText {
  static String setPlayURLXml(
    String url, {
    String title = "",
    required PlayType type,
  }) {
    final time = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch,
    );
    final douyu = RegExp(r'^https?://(\d+)\?douyu$');
    final isdouyu = douyu.firstMatch(url);
    if (isdouyu != null) {
      final roomId = isdouyu.group(1);
      // 斗鱼tv的dlna server,只能指定直播间ID,不接受url资源,必须是如下格式
      title = "roomId = $roomId, line = 0";
    } else if (title.isEmpty) {
      title = url;
    }
    title = htmlEncode(title);
    url = htmlEncode(url);
    var oclass = 'object.item.videoItem';
    var res = '';
    if (type is AudioMime) {
      oclass = 'object.item.audioItem';
    } else if (type is ImageMime) {
      oclass = 'object.item.imageItem';
    }
    if (type.protocolInfo.isNotEmpty) {
      res = '<res protocolInfo="${type.protocolInfo}">$url</res>';
    }
    return '''<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
    <s:Body>
        <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
            <InstanceID>0</InstanceID>
            <CurrentURI>$url</CurrentURI>
            <CurrentURIMetaData>
              <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/">
                <item id="id" parentID="0" restricted="0"><dc:title>$title</dc:title><upnp:artist>unknow</upnp:artist><dc:date>$time</dc:date><upnp:class>$oclass</upnp:class>$res</item>
              </DIDL-Lite>
            </CurrentURIMetaData>
        </u:SetAVTransportURI>
    </s:Body>
</s:Envelope>
        ''';
  }

  static String playActionXml() {
    return '''<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
    <s:Body>
        <u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
            <InstanceID>0</InstanceID>
            <Speed>1</Speed>
        </u:Play>
    </s:Body>
</s:Envelope>''';
  }

  static String pauseActionXml() {
    return '''<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
	<s:Body>
		<u:Pause xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
			<InstanceID>0</InstanceID>
		</u:Pause>
	</s:Body>
</s:Envelope>''';
  }

  static String stopActionXml() {
    return '''<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
    <s:Body>
        <u:Stop xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
            <InstanceID>0</InstanceID>
        </u:Stop>
    </s:Body>
</s:Envelope>''';
  }

  static String getPositionXml() {
    return '''<?xml version="1.0" encoding="utf-8" standalone="no"?>
    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body>
            <u:GetPositionInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
                <InstanceID>0</InstanceID>
                <MediaDuration />
            </u:GetPositionInfo>
        </s:Body>
    </s:Envelope>''';
  }

  static String seekToXml(sk) {
    return '''<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
	<s:Body>
		<u:Seek xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
			<InstanceID>0</InstanceID>
			<Unit>REL_TIME</Unit>
			<Target>$sk</Target>
		</u:Seek>
	</s:Body>
</s:Envelope>''';
  }

  static String getCurrentTransportActionsXml() {
    return '''<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
	<s:Body>
		<u:GetCurrentTransportActions xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
			<InstanceID>0</InstanceID>
		</u:GetCurrentTransportActions>
	</s:Body>
</s:Envelope>''';
  }

  static String getMediaInfoXml() {
    return '''<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
	<s:Body>
		<u:GetMediaInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
			<InstanceID>0</InstanceID>
		</u:GetMediaInfo>
	</s:Body>
</s:Envelope>''';
  }

  static String getTransportInfoXml() {
    return '''<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
	<s:Body>
		<u:GetTransportInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
			<InstanceID>0</InstanceID>
		</u:GetTransportInfo>
	</s:Body>
</s:Envelope>''';
  }

  static String nextXml() {
    return '''<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
	<s:Body>
		<u:Next xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
			<InstanceID>0</InstanceID>
		</u:Next>
	</s:Body>
</s:Envelope>''';
  }

  static String previousXml() {
    return '''<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
	<s:Body>
		<u:Previous xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
			<InstanceID>0</InstanceID>
		</u:Previous>
	</s:Body>
</s:Envelope>''';
  }

  static String setPlayModeXml(String modeName) {
    return '''<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
	<s:Body>
		<u:SetPlayMode xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
			<InstanceID>0</InstanceID>
			<NewPlayMode>$modeName</NewPlayMode>
		</u:SetPlayMode>
	</s:Body>
</s:Envelope>''';
  }

  static String getDeviceCapabilitiesXml() {
    return '''<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
	<s:Body>
		<u:GetDeviceCapabilities xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
			<InstanceID>0</InstanceID>
		</u:GetDeviceCapabilities>
	</s:Body>
</s:Envelope>''';
  }

  static String muteXml(bool mute) {
    final value = mute ? '1' : '0';
    return '''<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
	<s:Body>
		<u:SetMute xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
			<InstanceID>0</InstanceID>
			<Channel>Master</Channel>
			<DesiredMute>$value</DesiredMute>
		</u:SetMute>
	</s:Body>
</s:Envelope>''';
  }

  static String muteStateXml() {
    return '''<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
	<s:Body>
		<u:GetMute xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
			<InstanceID>0</InstanceID>
			<Channel>Master</Channel>
		</u:GetMute>
	</s:Body>
</s:Envelope>''';
  }

  static String volumeXml(int volume) {
    return '''<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
	<s:Body>
		<u:SetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
			<InstanceID>0</InstanceID>
			<Channel>Master</Channel>
			<DesiredVolume>$volume</DesiredVolume>
		</u:SetVolume>
	</s:Body>
</s:Envelope>''';
  }

  static String volumeStateXml() {
    return '''<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
	<s:Body>
		<u:GetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
			<InstanceID>0</InstanceID>
			<Channel>Master</Channel>
		</u:GetVolume>
	</s:Body>
</s:Envelope>''';
  }
}

class DLNAHttp {
  static final _client = HttpClient();
  static Future<String> get(Uri uri) async {
    const timeout = Duration(seconds: 15);
    final req = await _client.getUrl(uri);
    final res = await req.close().timeout(timeout);
    if (res.statusCode != HttpStatus.ok) {
      throw Exception("request $uri error , status ${res.statusCode}");
    }
    final body = await res.transform(utf8.decoder).join().timeout(timeout);
    return body;
  }

  static Future<String> post(
    Uri uri,
    Map<String, Object> headers,
    List<int> data,
  ) async {
    const timeout = Duration(seconds: 15);
    final req = await _client.postUrl(uri);
    headers.forEach((name, values) {
      req.headers.set(name, values);
    });
    req.contentLength = data.length;
    req.add(data);
    final res = await req.close().timeout(timeout);
    if (res.statusCode != HttpStatus.ok) {
      final body = await res.transform(utf8.decoder).join().timeout(timeout);
      throw Exception("request $uri error , status ${res.statusCode} $body");
    }
    final body = await res.transform(utf8.decoder).join().timeout(timeout);
    return body;
  }
}

class _upnp_msg_parser {
  final String message;
  _upnp_msg_parser(this.message);
  Future<DeviceInfo?> parse() async {
    final lines = message.split('\n');
    final arr = lines.first.split(' ');
    if (arr.length < 3) {
      return null;
    }
    final method = arr[0];
    if (method == 'M-SEARCH') {
      // 忽略别人的搜索请求
    } else if (method == 'NOTIFY' ||
        method == "HTTP/1.1" ||
        method == "HTTP/1.0") {
      lines.removeAt(0);
      return await onNotify(lines);
    } else {
      print(message);
    }
    return null;
  }

  Future<DeviceInfo?> onNotify(List<String> lines) async {
    String uri = '';
    lines.forEach((element) {
      final arr = element.split(':');
      final key = arr[0].trim().toUpperCase();
      if (key == "LOCATION") {
        arr.removeAt(0);
        final value = arr.join(':');
        uri = value.trim();
      }
    });
    if (uri != '') {
      return await getInfo(uri);
    }
    return null;
  }

  Future<DeviceInfo?> getInfo(String uri) async {
    try {
      final target = Uri.parse(uri);
      final body = await DLNAHttp.get(target);
      final info = DeviceInfoParser(body).parse(target);
      return info;
    } catch (e) {
      print(uri + " error: " + e.toString());
      return null;
    }
  }
}

class DeviceManager {
  var t = DateTime.now();
  final Map<String, DLNADevice> deviceList = Map();
  final StreamController<Map<String, DLNADevice>> devices = StreamController();
  DeviceManager();
  void cleanInactiveDevices(DateTime now) {
    deviceList.removeWhere((key, device) {
      final inactiveDuration = now.difference(device.activeTime).inSeconds;
      return inactiveDuration > 120; // 超过120秒未活跃
    });
  }

  onMessage(String message) async {
    final DeviceInfo? info = await _upnp_msg_parser(message).parse();
    if (info == null) {
      return;
    }
    final now = DateTime.now();
    final device = deviceList[info.URLBase];
    if (device != null) {
      device.updateActive(now);
    } else {
      deviceList[info.URLBase] = DLNADevice(info);
    }
    final newFound = device == null;
    if (newFound || now.difference(t).inSeconds.abs() > 5) {
      if (!devices.isClosed) {
        cleanInactiveDevices(now);
        devices.add(deviceList);
        t = now;
      }
    }
  }

  void dispose() {
    devices.close();
  }
}

class DLNAManager {
  static const String UPNP_IP_V4 = '239.255.255.250';
  static const int UPNP_PORT = 1900;
  final InternetAddress UPNP_AddressIPv4 = InternetAddress(UPNP_IP_V4);
  Timer _sender = Timer(Duration(seconds: 2), () {});
  RawDatagramSocket? _socket_server;
  StreamSubscription? _clientSubscription;
  StreamSubscription? _serverSubscription;
  int _searchCount = 0;
  DeviceManager? _deviceManager;
  Future<DeviceManager> start({reusePort = false}) async {
    stop();
    _deviceManager?.devices.close();
    final dm = DeviceManager();
    _deviceManager = dm;
    _socket_server = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      UPNP_PORT,
      reusePort: reusePort,
    );
    // https://github.com/dart-lang/sdk/issues/42250 截止到 dart 2.13.4 仍存在问题,期待新版修复
    // 修复IOS joinMulticast 的问题
    if (Platform.isIOS) {
      final List<NetworkInterface> interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddress.anyIPv4.type,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        final value = Uint8List.fromList(
          UPNP_AddressIPv4.rawAddress + interface.addresses[0].rawAddress,
        );
        _socket_server!.setRawOption(
          RawSocketOption(RawSocketOption.levelIPv4, 12, value),
        );
      }
    } else {
      _socket_server!.joinMulticast(UPNP_AddressIPv4);
    }
    final socket_client = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
    );

    _clientSubscription = socket_client.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        while (true) {
          final datagram = socket_client.receive();
          if (datagram == null) break;

          try {
            String message = String.fromCharCodes(datagram.data).trim();
            dm.onMessage(message);
          } catch (e) {
            print(e);
          }
        }
      }
    });

    _serverSubscription = _socket_server?.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        while (true) {
          final datagram = _socket_server?.receive();
          if (datagram == null) break;

          try {
            String message = String.fromCharCodes(datagram.data).trim();
            // print('Datagram from ${d.address.address}:${d.port}: ${message}');
            dm.onMessage(message);
          } catch (e) {
            print(e);
          }
        }
      }
    });

    _sendSearchRequest(socket_client);
    _sender = Timer.periodic(Duration(seconds: 2), (Timer t) async {
      _sendSearchRequest(socket_client);
    });
    return dm;
  }

  Future<void> _sendSearchRequest(RawDatagramSocket socket) async {
    List<String> stList;
    if (_searchCount == 0) {
      stList = [
        "ssdp:all",
        "urn:schemas-upnp-org:device:MediaRenderer:1",
        "urn:schemas-upnp-org:service:AVTransport:1",
      ];
    } else if (_searchCount % 5 == 0) {
      stList = ["ssdp:all"];
    } else if (_searchCount % 5 == 1 || _searchCount % 5 == 3) {
      stList = ["urn:schemas-upnp-org:device:MediaRenderer:1"];
    } else {
      stList = ["urn:schemas-upnp-org:service:AVTransport:1"];
    }

    for (int i = 0; i < stList.length; i++) {
      final st = stList[i];
      String msg =
          'M-SEARCH * HTTP/1.1\r\n' +
          'HOST: 239.255.255.250:1900\r\n' +
          'ST: $st\r\n' +
          'MX: ${_searchCount == 0 ? 1 : 3}\r\n' +
          'MAN: \"ssdp:discover\"\r\n\r\n';
      socket.send(msg.codeUnits, UPNP_AddressIPv4, UPNP_PORT);
      if (i < stList.length - 1) {
        await Future.delayed(Duration(milliseconds: 30));
      }
    }
    _searchCount++;
  }

  stop() {
    _sender.cancel();
    _clientSubscription?.cancel();
    _serverSubscription?.cancel();
    _socket_server?.close();
    _socket_server = null;
    _deviceManager?.dispose();
  }
}