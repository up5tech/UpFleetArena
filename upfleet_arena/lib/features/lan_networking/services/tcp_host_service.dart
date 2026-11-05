import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../../shared/protocol/protocol_constants.dart';
import '../../../shared/protocol/protocol_message.dart';
import 'frame_codec.dart';

/// A single accepted client connection on the Host.
class LanHostConnection {
  LanHostConnection({
    required this.id,
    required this.socket,
    required this.remoteAddress,
    required this.remotePort,
  });

  /// Stable identifier for this connection within the Host session.
  final String id;

  /// The accepted socket.
  final Socket socket;

  /// Remote peer address, `null` when the platform did not expose it.
  final InternetAddress? remoteAddress;

  /// Remote peer port.
  final int remotePort;

  // Single subscription on purpose: the controller buffers frames that
  // arrive before the Host subscribes, so a fast client cannot lose its
  // first message in a race.
  final StreamController<ProtocolMessage> _frames =
      StreamController<ProtocolMessage>();
  final FrameDecoder _decoder = FrameDecoder();
  bool _closed = false;

  /// Decoded frames received from this client.
  Stream<ProtocolMessage> get frames => _frames.stream;

  /// Whether the connection has been closed.
  bool get isClosed => _closed;

  /// Encodes and writes [message] to this client.
  void send(ProtocolMessage message) {
    if (_closed) return;
    try {
      socket.add(FrameCodec.encode(message.toJson()));
    } on SocketException {
      // The peer vanished mid-write. The socket's onDone handler closes the
      // connection and reports it to the Host runtime.
    }
  }

  /// Writes raw bytes. Used by the Phase 0 diagnostics to prove that partial
  /// frames survive a real TCP stream.
  void sendRaw(List<int> bytes) {
    if (_closed) return;
    socket.add(Uint8List.fromList(bytes));
  }

  /// Feeds raw bytes to the frame decoder and publishes complete frames.
  ///
  /// Throws [FrameFormatException] when the peer violates the transport
  /// limits; the caller is expected to answer with `protocol:error` and
  /// close the connection.
  List<ProtocolMessage> ingest(List<int> bytes) {
    final frames = <ProtocolMessage>[];
    for (final Map<String, dynamic> json in _decoder.addChunk(bytes)) {
      frames.add(ProtocolMessage.fromJson(json));
    }
    return frames;
  }

  /// Closes the connection and releases its resources.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _decoder.reset();
    try {
      await socket.close();
    } on SocketException {
      // Already gone.
    }
    await _frames.close();
  }
}

/// Hosts a TCP listener and accepts LAN clients (PLAN.md §6.1, §6.2).
///
/// The Host phone is the only authority in the room; every client opens a
/// single long-lived connection to it (star topology).
class TcpHostService {
  ServerSocket? _serverSocket;
  final StreamController<LanHostConnection> _connectionController =
      StreamController<LanHostConnection>.broadcast();
  final List<LanHostConnection> _connections = <LanHostConnection>[];
  int _connectionCounter = 0;

  /// The port the listener is bound to, or `null` when not listening.
  int? get port => _serverSocket?.port;

  /// Whether the listener is currently accepting connections.
  bool get isListening => _serverSocket != null;

  /// Currently accepted connections.
  List<LanHostConnection> get connections =>
      List<LanHostConnection>.unmodifiable(_connections);

  /// Emits every newly accepted connection.
  Stream<LanHostConnection> get onConnection => _connectionController.stream;

  /// Opens a TCP listener.
  ///
  /// [port] defaults to `0` (ephemeral) so the Host never collides with an
  /// already-used port; the effective port is returned (PLAN.md §6.3 step 2).
  ///
  /// [address] defaults to [InternetAddress.anyIPv4] so the listener accepts
  /// connections on the Wi-Fi interface.
  Future<int> start({int port = 0, InternetAddress? address}) async {
    if (_serverSocket != null) {
      throw StateError('TcpHostService is already listening.');
    }
    final server = await ServerSocket.bind(
      address ?? InternetAddress.anyIPv4,
      port,
      shared: false,
    );
    _serverSocket = server;
    server.listen(
      _handleSocket,
      onError: (Object _) {
        // Listener-level failures surface through the connection stream.
      },
    );
    return server.port;
  }

  void _handleSocket(Socket socket) {
    final connection = LanHostConnection(
      id: 'conn-${++_connectionCounter}',
      socket: socket,
      remoteAddress: socket.remoteAddress,
      remotePort: socket.remotePort,
    );
    _connections.add(connection);
    _connectionController.add(connection);

    socket.listen(
      (Uint8List data) {
        try {
          for (final ProtocolMessage message in connection.ingest(data)) {
            connection._frames.add(message);
          }
        } on ProtocolMessageFormatException catch (error) {
          connection.send(
            ProtocolMessage(
              messageType: HostEventType.error,
              payload: <String, dynamic>{
                'code': ProtocolErrorCode.malformedPayload,
                'message': error.message,
              },
            ),
          );
        } on FrameFormatException catch (error) {
          connection.send(
            ProtocolMessage(
              messageType: HostEventType.error,
              payload: <String, dynamic>{
                'code': error.code,
                'message': error.message,
              },
            ),
          );
          unawaited(connection.close());
        }
      },
      onError: (Object _) => unawaited(connection.close()),
      onDone: () => unawaited(connection.close()),
      cancelOnError: true,
    );
  }

  /// Closes the listener and every accepted connection.
  ///
  /// Called when the Host closes the room so that no client is left with a
  /// half-open socket (PLAN.md §9.5). The service stays reusable: calling
  /// [start] again opens a fresh listener.
  Future<void> stop() async {
    final server = _serverSocket;
    _serverSocket = null;
    if (server != null) {
      try {
        await server.close();
      } on SocketException {
        // Already closed.
      }
    }
    for (final LanHostConnection connection in List.of(_connections)) {
      await connection.close();
    }
    _connections.clear();
  }

  /// Releases the service for good. The connection stream is closed and no
  /// further [start] call is allowed.
  Future<void> dispose() async {
    await stop();
    await _connectionController.close();
  }
}
