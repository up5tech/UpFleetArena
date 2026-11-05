import 'protocol_constants.dart';

/// A protocol envelope as defined in PLAN.md §8.1.
///
/// Every frame carries the same envelope so that the Host can route a
/// message, correlate an acknowledgement with its request, and reject frames
/// that reference a stale state version.
class ProtocolMessage {
  const ProtocolMessage({
    required this.messageType,
    this.requestId,
    this.roomId,
    this.playerId,
    this.expectedStateVersion,
    this.payload = const {},
  });

  /// Builds an envelope from a decoded JSON object.
  factory ProtocolMessage.fromJson(Map<String, dynamic> json) {
    final Object? version = json['protocolVersion'];
    final Object? type = json['messageType'];
    final Object? payload = json['payload'];

    if (version is! int) {
      throw const ProtocolMessageFormatException(
        'Frame envelope is missing an integer "protocolVersion".',
      );
    }
    if (type is! String || type.isEmpty) {
      throw const ProtocolMessageFormatException(
        'Frame envelope is missing a non-empty "messageType".',
      );
    }
    if (payload != null && payload is! Map<String, dynamic>) {
      throw const ProtocolMessageFormatException(
        'Frame envelope field "payload" must be a JSON object.',
      );
    }

    return ProtocolMessage(
      messageType: type,
      requestId: _optionalString(json['requestId']),
      roomId: _optionalString(json['roomId']),
      playerId: _optionalString(json['playerId']),
      expectedStateVersion: _optionalInt(json['expectedStateVersion']),
      payload: (payload as Map<String, dynamic>?) ?? const {},
    );
  }

  /// Protocol version of this envelope.
  int get protocolVersion => AppProtocol.version;

  /// Route key, e.g. `room:join` or `game:fire`.
  final String messageType;

  /// Correlation id echoed back in the Host acknowledgement.
  final String? requestId;

  /// Room this message belongs to.
  final String? roomId;

  /// Sender identity. The Host must resolve the real identity from the
  /// accepted socket and must NOT trust this field (PLAN.md §9.3 step 1).
  final String? playerId;

  /// State version the sender believed was current.
  final int? expectedStateVersion;

  /// Message body.
  final Map<String, dynamic> payload;

  /// Serializes the envelope to its JSON object form.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'protocolVersion': protocolVersion,
    'messageType': messageType,
    if (requestId != null) 'requestId': requestId,
    if (roomId != null) 'roomId': roomId,
    if (playerId != null) 'playerId': playerId,
    if (expectedStateVersion != null)
      'expectedStateVersion': expectedStateVersion,
    'payload': payload,
  };

  /// Returns a copy with the given fields replaced.
  ProtocolMessage copyWith({
    String? messageType,
    String? requestId,
    String? roomId,
    String? playerId,
    int? expectedStateVersion,
    Map<String, dynamic>? payload,
  }) => ProtocolMessage(
    messageType: messageType ?? this.messageType,
    requestId: requestId ?? this.requestId,
    roomId: roomId ?? this.roomId,
    playerId: playerId ?? this.playerId,
    expectedStateVersion: expectedStateVersion ?? this.expectedStateVersion,
    payload: payload ?? this.payload,
  );

  static String? _optionalString(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    throw const ProtocolMessageFormatException(
      'Frame envelope field must be a string when present.',
    );
  }

  static int? _optionalInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    throw const ProtocolMessageFormatException(
      'Frame envelope field "expectedStateVersion" must be an integer.',
    );
  }
}

/// Raised when an envelope is structurally invalid.
class ProtocolMessageFormatException implements Exception {
  const ProtocolMessageFormatException(this.message);

  /// Client-safe explanation.
  final String message;

  @override
  String toString() => 'ProtocolMessageFormatException: $message';
}
