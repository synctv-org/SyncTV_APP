import 'dart:typed_data';
import 'dart:convert';

enum MessageType {
  UNKNOWN, // 0
  ERROR, // 1
  CHAT, // 2
  STATUS, // 3
  CHECK_STATUS, // 4
  EXPIRED, // 5
  CURRENT, // 6
  MOVIES, // 7
  VIEWER_COUNT, // 8
  SYNC, // 9
  MY_STATUS, // 10
  WEBRTC_OFFER, // 11
  WEBRTC_ANSWER, // 12
  WEBRTC_ICE_CANDIDATE, // 13
  WEBRTC_JOIN, // 14
  WEBRTC_LEAVE, // 15
}

class SimpleProto {
  // Wire types
  static const int WIRE_TYPE_VARINT = 0;
  static const int WIRE_TYPE_64BIT = 1;
  static const int WIRE_TYPE_LENGTH_DELIMITED = 2;

  // Field numbers from message.proto
  static const int FIELD_TYPE = 1;
  static const int FIELD_TIMESTAMP = 2;
  static const int FIELD_SENDER = 3;
  static const int FIELD_ERROR_MESSAGE = 4;
  static const int FIELD_CHAT_CONTENT = 5;
  static const int FIELD_PLAYBACK_STATUS = 6;
  static const int FIELD_EXPIRATION_ID = 7;
  static const int FIELD_VIEWER_COUNT = 8;
  static const int FIELD_WEBRTC_DATA = 9;

  // Status fields
  static const int STATUS_IS_PLAYING = 1;
  static const int STATUS_CURRENT_TIME = 2;
  static const int STATUS_PLAYBACK_RATE = 3;

  // Sender fields
  static const int SENDER_USER_ID = 1;
  static const int SENDER_USERNAME = 2;

  // WebRTC Data fields
  static const int WEBRTC_DATA = 1;
  static const int WEBRTC_TO = 2;
  static const int WEBRTC_FROM = 3;

  static List<int> encodeChat(String content) {
    final builder = BytesBuilder();
    // Type = CHAT (2)
    _writeTag(builder, FIELD_TYPE, WIRE_TYPE_VARINT);
    _writeVarint(builder, MessageType.CHAT.index);
    
    // Content
    _writeTag(builder, FIELD_CHAT_CONTENT, WIRE_TYPE_LENGTH_DELIMITED);
    _writeString(builder, content);
    
    return builder.toBytes();
  }

  static List<int> encodeStatus(bool isPlaying, double currentTime, double playbackRate) {
    final builder = BytesBuilder();
    // Type = STATUS (3)
    _writeTag(builder, FIELD_TYPE, WIRE_TYPE_VARINT);
    _writeVarint(builder, MessageType.STATUS.index);

    // Status message
    final statusBuilder = BytesBuilder();
    _writeTag(statusBuilder, STATUS_IS_PLAYING, WIRE_TYPE_VARINT);
    _writeVarint(statusBuilder, isPlaying ? 1 : 0);
    
    _writeTag(statusBuilder, STATUS_CURRENT_TIME, WIRE_TYPE_64BIT);
    _writeDouble(statusBuilder, currentTime);
    
    _writeTag(statusBuilder, STATUS_PLAYBACK_RATE, WIRE_TYPE_64BIT);
    _writeDouble(statusBuilder, playbackRate);

    _writeTag(builder, FIELD_PLAYBACK_STATUS, WIRE_TYPE_LENGTH_DELIMITED);
    _writeBytes(builder, statusBuilder.toBytes());

    return builder.toBytes();
  }

  static List<int> encodeSync() {
    final builder = BytesBuilder();
    // Type = SYNC (9)
    _writeTag(builder, FIELD_TYPE, WIRE_TYPE_VARINT);
    _writeVarint(builder, MessageType.SYNC.index);
    return builder.toBytes();
  }

  static List<int> encodeWebRTC(MessageType type, Map<String, dynamic> data) {
    final builder = BytesBuilder();
    // Type
    _writeTag(builder, FIELD_TYPE, WIRE_TYPE_VARINT);
    _writeVarint(builder, type.index);

    // WebRTC Data
    final webrtcBuilder = BytesBuilder();
    if (data['data'] != null) {
      _writeTag(webrtcBuilder, WEBRTC_DATA, WIRE_TYPE_LENGTH_DELIMITED);
      _writeString(webrtcBuilder, data['data']);
    }
    if (data['to'] != null) {
      _writeTag(webrtcBuilder, WEBRTC_TO, WIRE_TYPE_LENGTH_DELIMITED);
      _writeString(webrtcBuilder, data['to']);
    }
    // 'from' is usually filled by server, but we can send if needed

    _writeTag(builder, FIELD_WEBRTC_DATA, WIRE_TYPE_LENGTH_DELIMITED);
    _writeBytes(builder, webrtcBuilder.toBytes());

    return builder.toBytes();
  }

  static Map<String, dynamic> decode(Uint8List data) {
    final result = <String, dynamic>{};
    var offset = 0;
    final view = ByteData.view(data.buffer);

    while (offset < data.length) {
      final tag = _readVarint(data, offset);
      offset = tag.offset;
      final wireType = tag.value & 0x07;
      final fieldNumber = tag.value >> 3;

      if (wireType == WIRE_TYPE_VARINT) {
        final val = _readVarint(data, offset);
        offset = val.offset;
        if (fieldNumber == FIELD_TYPE) {
          result['type'] = MessageType.values[val.value];
        } else if (fieldNumber == FIELD_VIEWER_COUNT) {
          result['viewerCount'] = val.value;
        }
      } else if (wireType == WIRE_TYPE_64BIT) {
        // Handle 64-bit fields
        if (fieldNumber == FIELD_TIMESTAMP) {
           final view = ByteData.view(data.buffer, data.offsetInBytes + offset, 8);
           result['timestamp'] = view.getInt64(0, Endian.little);
        }
        offset += 8;
      } else if (wireType == WIRE_TYPE_LENGTH_DELIMITED) {
        final len = _readVarint(data, offset);
        offset = len.offset;
        final bytes = data.sublist(offset, offset + len.value);
        offset += len.value;

        if (fieldNumber == FIELD_CHAT_CONTENT) {
          result['chatContent'] = utf8.decode(bytes);
        } else if (fieldNumber == FIELD_SENDER) {
          result['sender'] = _decodeSender(bytes);
        } else if (fieldNumber == FIELD_PLAYBACK_STATUS) {
          result['status'] = _decodeStatus(bytes);
        } else if (fieldNumber == FIELD_WEBRTC_DATA) {
          result['webrtcData'] = _decodeWebRTCData(bytes);
        }
      } else {
        // Skip unsupported wire types?
        break; 
      }
    }
    return result;
  }

  static Map<String, dynamic> _decodeSender(Uint8List data) {
    final result = <String, dynamic>{};
    var offset = 0;
    while (offset < data.length) {
      final tag = _readVarint(data, offset);
      offset = tag.offset;
      final fieldNumber = tag.value >> 3;
      
      if ((tag.value & 0x07) == WIRE_TYPE_LENGTH_DELIMITED) {
        final len = _readVarint(data, offset);
        offset = len.offset;
        final bytes = data.sublist(offset, offset + len.value);
        offset += len.value;
        
        if (fieldNumber == SENDER_USER_ID) {
          try {
            result['userId'] = utf8.decode(bytes);
          } catch (e) {
            result['userId'] = 'unknown_id';
          }
        } else if (fieldNumber == SENDER_USERNAME) {
          try {
            result['username'] = utf8.decode(bytes);
          } catch (e) {
            result['username'] = 'Unknown';
          }
        }
      } else {
         // skip
         break;
      }
    }
    return result;
  }

  static Map<String, dynamic> _decodeStatus(Uint8List data) {
    final result = <String, dynamic>{};
    var offset = 0;
    while (offset < data.length) {
      final tag = _readVarint(data, offset);
      offset = tag.offset;
      final fieldNumber = tag.value >> 3;
      final wireType = tag.value & 0x07;

      if (wireType == WIRE_TYPE_VARINT) {
        final val = _readVarint(data, offset);
        offset = val.offset;
        if (fieldNumber == STATUS_IS_PLAYING) {
          result['is_playing'] = val.value == 1;
        }
      } else if (wireType == WIRE_TYPE_64BIT) {
        final view = ByteData.view(data.buffer, data.offsetInBytes + offset, 8);
        final val = view.getFloat64(0, Endian.little);
        offset += 8;
        if (fieldNumber == STATUS_CURRENT_TIME) {
          result['current_time'] = val;
        } else if (fieldNumber == STATUS_PLAYBACK_RATE) {
          result['playback_rate'] = val;
        }
      } else {
         // skip unsupported
         break;
      }
    }
    return result;
  }

  static Map<String, dynamic> _decodeWebRTCData(Uint8List data) {
    final result = <String, dynamic>{};
    var offset = 0;
    while (offset < data.length) {
      final tag = _readVarint(data, offset);
      offset = tag.offset;
      final fieldNumber = tag.value >> 3;
      final wireType = tag.value & 0x07;

      if (wireType == WIRE_TYPE_LENGTH_DELIMITED) {
        final len = _readVarint(data, offset);
        offset = len.offset;
        final bytes = data.sublist(offset, offset + len.value);
        offset += len.value;

        if (fieldNumber == WEBRTC_DATA) {
          result['data'] = utf8.decode(bytes);
        } else if (fieldNumber == WEBRTC_TO) {
          result['to'] = utf8.decode(bytes);
        } else if (fieldNumber == WEBRTC_FROM) {
          result['from'] = utf8.decode(bytes);
        }
      } else {
        break;
      }
    }
    return result;
  }

  // Helpers
  static void _writeTag(BytesBuilder builder, int fieldNumber, int wireType) {
    _writeVarint(builder, (fieldNumber << 3) | wireType);
  }

  static void _writeVarint(BytesBuilder builder, int value) {
    while (true) {
      if ((value & ~0x7F) == 0) {
        builder.addByte(value);
        return;
      } else {
        builder.addByte((value & 0x7F) | 0x80);
        value >>= 7;
      }
    }
  }

  static void _writeString(BytesBuilder builder, String value) {
    final bytes = utf8.encode(value);
    _writeVarint(builder, bytes.length);
    builder.add(bytes);
  }
  
  static void _writeBytes(BytesBuilder builder, List<int> bytes) {
    _writeVarint(builder, bytes.length);
    builder.add(bytes);
  }

  static void _writeDouble(BytesBuilder builder, double value) {
    final b = ByteData(8);
    b.setFloat64(0, value, Endian.little);
    builder.add(b.buffer.asUint8List());
  }

  static _ReadResult _readVarint(Uint8List data, int offset) {
    int result = 0;
    int shift = 0;
    while (true) {
      if (offset >= data.length) break;
      final byte = data[offset++];
      result |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
    }
    return _ReadResult(result, offset);
  }
}

class _ReadResult {
  final int value;
  final int offset;
  _ReadResult(this.value, this.offset);
}
