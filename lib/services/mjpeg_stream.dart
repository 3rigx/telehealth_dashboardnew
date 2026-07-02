import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Connects to an MJPEG HTTP stream and emits one [Uint8List] (JPEG) per frame.
/// Handles reconnection automatically if the server drops.
class MjpegStream {
  final String url;
  final Duration reconnectDelay;

  MjpegStream(this.url, {this.reconnectDelay = const Duration(seconds: 2)});

  StreamController<Uint8List>? _controller;
  HttpClient? _client;
  bool _closed = false;

  Stream<Uint8List> get stream {
    _controller ??= StreamController<Uint8List>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
    return _controller!.stream;
  }

  void _start() {
    _closed = false;
    // Some HttpClient connection errors (e.g. the endpoint isn't a real MJPEG
    // server, or it speaks a different protocol) are raised asynchronously on
    // the pooled connection, escaping the await-ed try/catch below. Guard the
    // whole loop so such errors can never become unhandled and crash the app —
    // the loop just keeps retrying.
    runZonedGuarded(_connect, (_, _) {});
  }

  void _stop() {
    _closed = true;
    _client?.close(force: true);
    _client = null;
    _controller?.close();
    _controller = null;
  }

  Future<void> _connect() async {
    while (!_closed) {
      HttpClient? client;
      try {
        client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 5)
          ..idleTimeout       = const Duration(hours: 1);
        _client = client;

        final req  = await client.getUrl(Uri.parse(url));
        req.headers.set('Accept', 'multipart/x-mixed-replace');
        final resp = await req.close();

        if (resp.statusCode == 200) {
          // Find the boundary string from Content-Type header
          final ct = resp.headers.value('content-type') ?? '';
          final boundary = _parseBoundary(ct);
          if (boundary != null) await _parseMjpeg(resp, boundary);
        }
      } catch (_) {
        // Server not up yet / not a valid MJPEG stream — wait and retry.
      } finally {
        // Always tear down the client so a poisoned pooled connection is never
        // reused on the next attempt (and we don't leak one per retry).
        client?.close(force: true);
        if (identical(_client, client)) _client = null;
      }

      if (!_closed) await Future.delayed(reconnectDelay);
    }
  }

  Future<void> _parseMjpeg(Stream<List<int>> source, String boundary) async {
    // Buffer incoming bytes and split on MJPEG boundaries
    final boundaryBytes = '--$boundary'.codeUnits;
    final buf = <int>[];

    await for (final chunk in source) {
      if (_closed) return;
      buf.addAll(chunk);

      // Process all complete frames in the buffer
      while (true) {
        // Find start of a part (boundary line)
        final start = _indexOf(buf, boundaryBytes);
        if (start < 0) break;

        // Skip past boundary + CRLF
        int pos = start + boundaryBytes.length;
        if (pos + 2 > buf.length) break;
        pos += _skipCrlf(buf, pos);

        // Read headers until blank line
        final headerEnd = _findBlankLine(buf, pos);
        if (headerEnd < 0) break;

        final headerStr  = String.fromCharCodes(buf.sublist(pos, headerEnd));
        final contentLen = _parseContentLength(headerStr);
        int dataStart    = headerEnd + 4; // skip \r\n\r\n

        if (contentLen != null) {
          // We know the exact length — wait for enough bytes
          if (dataStart + contentLen > buf.length) break;

          final jpeg = Uint8List.fromList(buf.sublist(dataStart, dataStart + contentLen));
          if (!_closed) _controller?.add(jpeg);

          buf.removeRange(0, dataStart + contentLen);
        } else {
          // No Content-Length — scan for next boundary
          final nextBoundary = _indexOf(buf, boundaryBytes, dataStart);
          if (nextBoundary < 0) break;

          // Strip trailing CRLF before boundary
          int end = nextBoundary;
          if (end > 2 && buf[end - 2] == 13 && buf[end - 1] == 10) end -= 2;

          final jpeg = Uint8List.fromList(buf.sublist(dataStart, end));
          if (!_closed && jpeg.isNotEmpty) _controller?.add(jpeg);

          buf.removeRange(0, nextBoundary);
        }
      }

      // Drop excess buffer (safety valve — max 4 MB)
      if (buf.length > 4 * 1024 * 1024) buf.removeRange(0, buf.length - 512 * 1024);
    }
  }

  // ── Parsing helpers ───────────────────────────────────────────────────────

  static String? _parseBoundary(String contentType) {
    final m = RegExp(r'boundary=([^\s;]+)', caseSensitive: false).firstMatch(contentType);
    return m?.group(1);
  }

  static int? _parseContentLength(String headers) {
    final m = RegExp(r'content-length:\s*(\d+)', caseSensitive: false).firstMatch(headers);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  static int _indexOf(List<int> data, List<int> pattern, [int from = 0]) {
    outer:
    for (int i = from; i <= data.length - pattern.length; i++) {
      for (int j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  static int _findBlankLine(List<int> data, int from) {
    // Find \r\n\r\n
    for (int i = from; i <= data.length - 4; i++) {
      if (data[i] == 13 && data[i+1] == 10 && data[i+2] == 13 && data[i+3] == 10) {
        return i;
      }
    }
    return -1;
  }

  static int _skipCrlf(List<int> data, int pos) {
    if (pos + 1 < data.length && data[pos] == 13 && data[pos+1] == 10) return 2;
    if (pos < data.length && data[pos] == 10) return 1;
    return 0;
  }

  void dispose() => _stop();
}
