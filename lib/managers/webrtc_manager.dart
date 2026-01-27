import 'dart:async';
import 'dart:io';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';
import 'package:audio_session/audio_session.dart';
import 'package:synctv_app/utils/audio_util.dart';

typedef SignalingCallback = void Function(String type, Map<String, dynamic> data);

class WebRTCManager {
  final Map<String, RTCPeerConnection> _peerConnections = {};
  MediaStream? _localStream;
  final Map<String, MediaStream> _remoteStreams = {}; 
  final Set<String> _connectedPeers = {};
  final SignalingCallback onSignalingMessage;
  final VoidCallback onStateChange;
  
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  bool get hasPeersConnected => _connectedPeers.isNotEmpty;
  int get participantCount => _connectedPeers.length + (_isConnected ? 1 : 0);

  WebRTCManager({
    required this.onSignalingMessage,
    required this.onStateChange,
  });

  void handleSignalingMessage(String type, Map<String, dynamic> data) {
    final fromId = data['from'];
    if (fromId == null) return;
    
    switch (type) {
      case 'join':
        handleJoin(fromId);
        break;
      case 'offer':
        handleOffer(fromId, data);
        break;
      case 'answer':
        handleAnswer(fromId, data);
        break;
      case 'candidate':
        handleCandidate(fromId, data);
        break;
      case 'leave':
        handleLeave(fromId);
        break;
    }
  }

  Future<void> join() async {
    if (_isConnected) return;
    
    try {
      await AudioUtil.stopPlaying();

      await AudioUtil.setVoiceCallMode(true);
      
      final mediaConstraints = {
        'audio': true,
        'video': false,
      };
      
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    
    await Helper.setSpeakerphoneOn(true);
      
      onSignalingMessage('join', {});
      
      _isConnected = true;
      onStateChange();
      
    } catch (e) {
      debugPrint('WebRTC Join Error: $e');
      await leave();
      rethrow;
    }
  }

  Future<RTCPeerConnection> _createPeerConnection(String remoteId) async {
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    };
    
    final pc = await createPeerConnection(configuration);
    
    _localStream?.getTracks().forEach((track) {
      pc.addTrack(track, _localStream!);
    });
    
    pc.onIceCandidate = (candidate) {
      onSignalingMessage('candidate', {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'to': remoteId,
      });
    };
    
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
         debugPrint('WebRTC Peer Connected: $remoteId');
         _connectedPeers.add(remoteId);
         onStateChange();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
                 state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
                 state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
         _connectedPeers.remove(remoteId);
         onStateChange();
      }
    };
    
    pc.onTrack = (event) {
      if (event.track.kind == 'audio') {
        event.track.enabled = true;
        Helper.setSpeakerphoneOn(true);
      }
    };

    _peerConnections[remoteId] = pc;
    return pc;
  }

  Future<void> handleJoin(String fromId) async {
    try {
      final pc = await _createPeerConnection(fromId);
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      
      onSignalingMessage('offer', {
        'sdp': offer.sdp,
        'type': offer.type,
        'to': fromId,
      });
    } catch (e) {
      debugPrint('Handle Join Error: $e');
    }
  }

  Future<void> handleOffer(String fromId, Map<String, dynamic> data) async {
    try {
      final pc = await _createPeerConnection(fromId);
      final description = RTCSessionDescription(data['sdp'], data['type']);
      await pc.setRemoteDescription(description);
      
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      
      onSignalingMessage('answer', {
        'sdp': answer.sdp,
        'type': answer.type,
        'to': fromId,
      });

    } catch (e) {
      debugPrint('Handle Offer Error: $e');
    }
  }

  Future<void> handleAnswer(String fromId, Map<String, dynamic> data) async {
    try {
      final pc = _peerConnections[fromId];
      if (pc == null) return;
      
      final description = RTCSessionDescription(data['sdp'], data['type']);
      await pc.setRemoteDescription(description);


    } catch (e) {
      debugPrint('Handle Answer Error: $e');
    }
  }

  Future<void> handleCandidate(String fromId, Map<String, dynamic> data) async {
    try {
      final candidate = RTCIceCandidate(
        data['candidate'],
        data['sdpMid'],
        data['sdpMLineIndex'],
      );

      final pc = _peerConnections[fromId];
      if (pc == null) {
        return;
      }
      
      await pc.addCandidate(candidate);
    } catch (e) {
      debugPrint('Handle Candidate Error: $e');
    }
  }

  Future<void> handleLeave(String fromId) async {
    final pc = _peerConnections.remove(fromId);
    await pc?.close();
    
    // Cleanup remote stream
    final stream = _remoteStreams.remove(fromId);
    stream?.getTracks().forEach((track) => track.stop());
    await stream?.dispose();
  }

  Future<void> leave() async {
    await Helper.setSpeakerphoneOn(false);
    if (_isConnected) {
      onSignalingMessage('leave', {});
    }

    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _localStream = null;
    
    for (var stream in _remoteStreams.values) {
      stream.getTracks().forEach((track) => track.stop());
      await stream.dispose();
    }
    _remoteStreams.clear();

    for (var pc in _peerConnections.values) {
      await pc.close();
    }
    _peerConnections.clear();
    _connectedPeers.clear();
    
    _isConnected = false;
    onStateChange();
  }
  
  void dispose() {
    leave();
  }

  void toggleMute() {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      for (var track in audioTracks) {
        track.enabled = !track.enabled;
      }
      onStateChange();
    }
  }

  bool get isMuted {
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      return !_localStream!.getAudioTracks().first.enabled;
    }
    return false;
  }
}
