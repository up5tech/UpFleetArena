import 'dart:math';

/// Cryptographically secure random helpers.
///
/// Room codes, player IDs and resume tokens must not be predictable
/// (PLAN.md §12). [Random.secure] is the platform CSPRNG.
class SecureRandom {
  SecureRandom._();

  static final Random _random = Random.secure();

  /// Returns a random RFC 4122 version 4 UUID.
  static String uuidV4() {
    final List<int> bytes = List<int>.generate(
      16,
      (int _) => _random.nextInt(256),
    );
    // Version 4 and RFC 4122 variant bits.
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    final String hex = bytes
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  /// Returns a random lowercase alphanumeric token.
  ///
  /// [length] is the number of characters. The alphabet contains no visually
  /// ambiguous characters.
  static String token({
    int length = 32,
    String alphabet = 'abcdefghijkmnopqrstuvwxyz23456789',
  }) {
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < length; i++) {
      buffer.write(alphabet[_random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  /// Returns a random invitation code.
  ///
  /// The alphabet excludes `0`, `O`, `1` and `I` so the code can be read
  /// aloud without ambiguity (PLAN.md §2.1).
  static String inviteCode({
    int length = 6,
    String alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
  }) {
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < length; i++) {
      buffer.write(alphabet[_random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }
}
