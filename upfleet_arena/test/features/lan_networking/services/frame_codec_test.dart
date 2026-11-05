import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:upfleet_arena/features/lan_networking/services/frame_codec.dart';
import 'package:upfleet_arena/shared/protocol/protocol_constants.dart';

void main() {
  group('FrameCodec.encode', () {
    test('writes a 4-byte big-endian length header', () {
      final Uint8List frame = FrameCodec.encode(<String, dynamic>{
        'messageType': 'client:ping',
      });
      final int length = ByteData.sublistView(frame).getUint32(0, Endian.big);

      expect(length, frame.length - FrameCodec.headerSize);
      expect(frame.length, FrameCodec.headerSize + length);
    });

    test('round-trips the JSON payload', () {
      final Map<String, dynamic> payload = <String, dynamic>{
        'protocolVersion': 1,
        'messageType': 'client:ping',
        'payload': <String, dynamic>{'nonce': 'abc'},
      };

      final FrameDecoder decoder = FrameDecoder();
      final List<Map<String, dynamic>> frames = decoder.addChunk(
        FrameCodec.encode(payload),
      );

      expect(frames, hasLength(1));
      expect(frames.single['messageType'], 'client:ping');
      expect(
        (frames.single['payload'] as Map<String, dynamic>)['nonce'],
        'abc',
      );
    });

    test('rejects a payload larger than the frame limit', () {
      final String huge = 'x' * (FrameCodec.maxPayloadBytes + 1);

      expect(
        () => FrameCodec.encode(<String, dynamic>{'data': huge}),
        throwsA(
          isA<FrameFormatException>().having(
            (FrameFormatException error) => error.code,
            'code',
            ProtocolErrorCode.frameTooLarge,
          ),
        ),
      );
    });
  });

  group('FrameDecoder', () {
    test('reassembles a frame delivered in several chunks', () {
      final FrameDecoder decoder = FrameDecoder();
      final Uint8List frame = FrameCodec.encode(<String, dynamic>{
        'messageType': 'client:ping',
        'payload': <String, dynamic>{'filler': 'y' * 5000},
      });

      // Deliver the frame byte by byte: nothing may be emitted before the
      // last byte arrives (PLAN.md §6.4).
      for (int i = 0; i < frame.length - 1; i++) {
        expect(
          decoder.addChunk(<int>[frame[i]]),
          isEmpty,
          reason: 'a partial frame must not produce a message',
        );
      }

      final List<Map<String, dynamic>> frames = decoder.addChunk(
        <int>[frame.last],
      );
      expect(frames, hasLength(1));
      expect(
        (frames.single['payload'] as Map<String, dynamic>)['filler'],
        'y' * 5000,
      );
      expect(decoder.bufferedBytes, 0);
    });

    test('splits several frames received in one chunk', () {
      final FrameDecoder decoder = FrameDecoder();
      final Uint8List first = FrameCodec.encode(<String, dynamic>{
        'messageType': 'a',
      });
      final Uint8List second = FrameCodec.encode(<String, dynamic>{
        'messageType': 'b',
      });

      final List<int> combined = <int>[...first, ...second];
      final List<Map<String, dynamic>> frames = decoder.addChunk(combined);

      expect(frames, hasLength(2));
      expect(frames[0]['messageType'], 'a');
      expect(frames[1]['messageType'], 'b');
      expect(decoder.bufferedBytes, 0);
    });

    test('handles a frame boundary split across two chunks', () {
      final FrameDecoder decoder = FrameDecoder();
      final Uint8List first = FrameCodec.encode(<String, dynamic>{
        'messageType': 'a',
      });
      final Uint8List second = FrameCodec.encode(<String, dynamic>{
        'messageType': 'b',
      });
      final List<int> combined = <int>[...first, ...second];

      // The split lands inside the header of the second frame: the first
      // frame is complete, the second one is still partial.
      final int split = first.length + 3;
      final List<Map<String, dynamic>> firstBatch = decoder.addChunk(
        combined.sublist(0, split),
      );
      expect(firstBatch, hasLength(1));
      expect(firstBatch.single['messageType'], 'a');

      final List<Map<String, dynamic>> frames = decoder.addChunk(
        combined.sublist(split),
      );
      expect(frames, hasLength(1));
      expect(frames.single['messageType'], 'b');
      expect(decoder.bufferedBytes, 0);
    });

    test('rejects a frame whose declared length exceeds the limit', () {
      final FrameDecoder decoder = FrameDecoder();
      final int oversized = FrameCodec.maxPayloadBytes + 1;
      final List<int> header = <int>[
        oversized >> 24 & 0xFF,
        oversized >> 16 & 0xFF,
        oversized >> 8 & 0xFF,
        oversized & 0xFF,
      ];

      expect(
        () => decoder.addChunk(header),
        throwsA(
          isA<FrameFormatException>().having(
            (FrameFormatException error) => error.code,
            'code',
            ProtocolErrorCode.frameTooLarge,
          ),
        ),
      );
    });

    test('rejects a frame whose payload is not valid JSON', () {
      final FrameDecoder decoder = FrameDecoder();
      final List<int> body = '{not-json'.codeUnits;
      final List<int> frame = <int>[
        body.length >> 24 & 0xFF,
        body.length >> 16 & 0xFF,
        body.length >> 8 & 0xFF,
        body.length & 0xFF,
        ...body,
      ];

      expect(
        () => decoder.addChunk(frame),
        throwsA(
          isA<FrameFormatException>().having(
            (FrameFormatException error) => error.code,
            'code',
            ProtocolErrorCode.malformedFrame,
          ),
        ),
      );
    });

    test('rejects a frame whose payload is not a JSON object', () {
      final FrameDecoder decoder = FrameDecoder();
      final List<int> body = utf8.encode('[1,2,3]');
      final List<int> frame = <int>[
        body.length >> 24 & 0xFF,
        body.length >> 16 & 0xFF,
        body.length >> 8 & 0xFF,
        body.length & 0xFF,
        ...body,
      ];

      expect(
        () => decoder.addChunk(frame),
        throwsA(
          isA<FrameFormatException>().having(
            (FrameFormatException error) => error.code,
            'code',
            ProtocolErrorCode.malformedPayload,
          ),
        ),
      );
    });

    test('rejects a payload that is not valid UTF-8', () {
      final FrameDecoder decoder = FrameDecoder();
      final List<int> body = <int>[0xC3, 0x28];
      final List<int> frame = <int>[
        body.length >> 24 & 0xFF,
        body.length >> 16 & 0xFF,
        body.length >> 8 & 0xFF,
        body.length & 0xFF,
        ...body,
      ];

      expect(
        () => decoder.addChunk(frame),
        throwsA(
          isA<FrameFormatException>().having(
            (FrameFormatException error) => error.code,
            'code',
            ProtocolErrorCode.malformedPayload,
          ),
        ),
      );
    });

    test('drops buffered bytes on reset', () {
      final FrameDecoder decoder = FrameDecoder();
      final Uint8List frame = FrameCodec.encode(<String, dynamic>{
        'messageType': 'a',
      });

      decoder.addChunk(frame.sublist(0, 6));
      expect(decoder.bufferedBytes, greaterThan(0));

      decoder.reset();
      expect(decoder.bufferedBytes, 0);
    });

    test('keeps the buffer consistent across many mixed chunks', () {
      final FrameDecoder decoder = FrameDecoder();
      final List<Map<String, dynamic>> received = <Map<String, dynamic>>[];

      for (int i = 0; i < 25; i++) {
        final Uint8List frame = FrameCodec.encode(<String, dynamic>{
          'messageType': 'm$i',
          'payload': <String, dynamic>{'index': i},
        });
        final int split = frame.length ~/ 2;
        received.addAll(decoder.addChunk(frame.sublist(0, split)));
        received.addAll(decoder.addChunk(frame.sublist(split)));
      }

      expect(received, hasLength(25));
      expect(received.first['messageType'], 'm0');
      expect(received.last['messageType'], 'm24');
      expect(decoder.bufferedBytes, 0);
    });
  });
}
