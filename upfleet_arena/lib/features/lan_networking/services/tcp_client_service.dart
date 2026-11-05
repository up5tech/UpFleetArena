import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../../shared/protocol/protocol_constants.dart';
import '../../../shared/protocol/protocol_message.dart';
import 'frame_codec.dart';

/// Opens a single long-lived TCP connection to the Host (PLAN.md §6.2, §6.4).
///
/// Clients never connect to each other; every command travels to the Host.
class TcpClientService {
  Socket? _socket;
  final FrameDecoder _decoder = FrameDecoder();
  // Single subscription on purpose: the controllers buffer frames that
  // arrive before the caller subscribes.
  final StreamController<ProtocolMessage> _frames =
      StreamController<ProtocolMessage>();
  final StreamController<ProtocolError> _errors = StreamController<ProtocolError>();
  bool _closed = false;

  /// Frames received from the Host.
  Stream<ProtocolMessage> get frames => _frames.stream;

  /// Transport-level errors (connect failures, malformed frames).
  Stream<ProtocolError> get errors => _errors.stream;

  /// Whether the socket is currently connected.
  bool get isConnected => _socket != null && !_closed;

  /// Connects to the Host.
  ///
  /// Throws [SocketException] when the Host is unreachable, and
  /// [TimeoutException] when [timeout] elapses first. This is the situation
  /// described in PLAN.md §17 (router blocks device-to-device traffic) and
  /// must be surfaced as a readable message, never as a silent hang.
  Future<void> connect(
    InternetAddress address,
    int port, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_socket != null) {
      throw StateError('TcpClientService is already connected.');
    }
    final socket = await Socket.connect(address, port, timeout: timeout);
    _socket = socket;
    _closed = false;

    socket.listen(
      (Uint8List data) {
        try {
          for (final Map<String, dynamic> json in _decoder.addChunk(data)) {
            _frames.add(ProtocolMessage.fromJson(json));
          }
        } on ProtocolMessageFormatException catch (error) {
          _errors.add(
            ProtocolError(
              ProtocolErrorCode.malformedPayload,
              error.message,
            ),
          );
        } on FrameFormatException catch (error) {
          _errors.add(ProtocolError(error.code, error.message));
        }
      },
      onError: (Object error) {
        _errors.add(
          ProtocolError(
            ProtocolErrorCode.hostUnreachable,
            'Connection to the Host failed: $error',
          ),
        );
      },
      onDone: () {
        _closed = true;
      },
      cancelOnError: true,
    );
  }

  /// Sends [message] to the Host.
  void send(ProtocolMessage message) {
    final socket = _socket;
    if (socket == null || _closed) {
      throw StateError('Cannot send on a closed client connection.');
    }
    socket.add(FrameCodec.encode(message.toJson()));
  }

  /// Writes raw bytes. Used by the Phase 0 diagnostics to prove that partial
  /// frames survive a real TCP stream.
  void sendRaw(List<int> bytes) {
    final socket = _socket;
    if (socket == null || _closed) {
      throw StateError('Cannot send on a closed client connection.');
    }
    socket.add(Uint8List.fromList(bytes));
  }

  /// Closes the connection and releases its resources.
  ///
  /// The service is single-use: create a new instance for the next
  /// connection attempt.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final socket = _socket;
    _socket = null;
    _decoder.reset();
    if (socket != null) {
      try {
        await socket.close();
      } on SocketException {
        // Already closed.
      }
    }
    await _frames.close();
    await _errors.close();
  }
}

/// A transport-level failure with a stable, client-safe code.
class ProtocolError {
  const ProtocolError(this.code, this.message);

  /// Stable machine-readable error code.
  final String code;

  /// Human-readable explanation.
  final String message;

  @override
  String toString() => 'ProtocolError($code): $message';
}
