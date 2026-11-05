import 'dart:convert';
import 'dart:typed_data';

import '../../../shared/protocol/protocol_constants.dart';

/// Raised when an inbound frame cannot be decoded or violates a transport
/// limit.
///
/// The [code] is a stable [ProtocolErrorCode] value so the Host can answer
/// with a `protocol:error` event instead of dropping the connection silently.
class FrameFormatException implements Exception {
  const FrameFormatException(this.code, this.message);

  /// Stable machine-readable error code.
  final String code;

  /// Human-readable, client-safe explanation.
  ///
  /// Never include stack traces, local file paths, or raw exception text
  /// (PLAN.md §8.4).
  final String message;

  @override
  String toString() => 'FrameFormatException($code): $message';
}

/// Encodes and decodes length-prefixed JSON frames.
///
/// Wire format (PLAN.md §6.4):
///
/// ```text
/// +--------------------+---------------------------+
/// | uint32 BE length  | UTF-8 JSON payload        |
/// | 4 bytes            | `length` bytes            |
/// +--------------------+---------------------------+
/// ```
///
/// A single TCP read is NOT guaranteed to contain exactly one frame, and a
/// frame may be split across many reads. [FrameDecoder] absorbs both cases.
class FrameCodec {
  const FrameCodec._();

  /// Size of the length prefix in bytes.
  static const int headerSize = 4;

  /// Maximum accepted payload size in bytes (PLAN.md §6.4).
  static const int maxPayloadBytes = AppProtocol.maxFrameBytes;

  /// Encodes a JSON payload into a single length-prefixed frame.
  ///
  /// Throws [FrameFormatException] with [ProtocolErrorCode.frameTooLarge] if
  /// the payload exceeds [maxPayloadBytes].
  static Uint8List encode(Map<String, dynamic> payload) {
    final List<int> body = utf8.encode(jsonEncode(payload));
    if (body.length > maxPayloadBytes) {
      throw FrameFormatException(
        ProtocolErrorCode.frameTooLarge,
        'Frame payload of ${body.length} bytes exceeds the '
        '$maxPayloadBytes byte limit.',
      );
    }
    final frame = Uint8List(headerSize + body.length);
    ByteData.sublistView(frame).setUint32(0, body.length, Endian.big);
    frame.setRange(headerSize, frame.length, body);
    return frame;
  }
}

/// Incrementally decodes length-prefixed JSON frames from a byte stream.
///
/// Feed arbitrary chunks with [addChunk]; it returns every frame that became
/// complete. Bytes that do not yet form a whole frame stay buffered for the
/// next chunk, which is what makes partial reads safe.
class FrameDecoder {
  FrameDecoder({this.maxPayloadBytes = FrameCodec.maxPayloadBytes})
    : assert(maxPayloadBytes > 0, 'maxPayloadBytes must be positive');

  /// Maximum accepted payload size in bytes.
  final int maxPayloadBytes;

  Uint8List _buffer = Uint8List(0);
  int _start = 0;

  /// Number of bytes currently held back waiting for more data.
  int get bufferedBytes => _buffer.length - _start;

  /// Appends [chunk] to the internal buffer and returns all frames that are
  /// now complete.
  ///
  /// Throws [FrameFormatException] when the stream declares an oversized
  /// frame or contains a malformed payload. Callers are expected to close the
  /// connection in that case (PLAN.md §12).
  List<Map<String, dynamic>> addChunk(List<int> chunk) {
    _append(chunk);
    final frames = <Map<String, dynamic>>[];

    while (true) {
      final available = _buffer.length - _start;
      if (available < FrameCodec.headerSize) break;

      final length = ByteData.sublistView(
        _buffer,
        _start,
        _start + FrameCodec.headerSize,
      ).getUint32(0, Endian.big);

      if (length > maxPayloadBytes) {
        throw FrameFormatException(
          ProtocolErrorCode.frameTooLarge,
          'Frame payload of $length bytes exceeds the $maxPayloadBytes byte '
          'limit.',
        );
      }
      if (available < FrameCodec.headerSize + length) break;

      final payloadStart = _start + FrameCodec.headerSize;
      final payloadBytes = _buffer.sublist(
        payloadStart,
        payloadStart + length,
      );
      _start = payloadStart + length;
      frames.add(_decodePayload(payloadBytes));
    }

    if (_start == _buffer.length) {
      _buffer = Uint8List(0);
      _start = 0;
    }
    return frames;
  }

  /// Drops all buffered bytes. Used when a connection is reset.
  void reset() {
    _buffer = Uint8List(0);
    _start = 0;
  }

  void _append(List<int> chunk) {
    if (chunk.isEmpty) return;
    final used = _buffer.length - _start;
    final next = Uint8List(used + chunk.length);
    if (used > 0) next.setRange(0, used, _buffer, _start);
    next.setRange(used, next.length, chunk);
    _buffer = next;
    _start = 0;
  }

  Map<String, dynamic> _decodePayload(List<int> payloadBytes) {
    if (payloadBytes.isEmpty) {
      throw const FrameFormatException(
        ProtocolErrorCode.malformedPayload,
        'Frame payload is empty.',
      );
    }
    final String text;
    try {
      text = utf8.decode(payloadBytes);
    } on FormatException {
      throw const FrameFormatException(
        ProtocolErrorCode.malformedPayload,
        'Frame payload is not valid UTF-8.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const FrameFormatException(
        ProtocolErrorCode.malformedFrame,
        'Frame payload is not valid JSON.',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FrameFormatException(
        ProtocolErrorCode.malformedPayload,
        'Frame payload must be a JSON object.',
      );
    }
    return decoded;
  }
}
