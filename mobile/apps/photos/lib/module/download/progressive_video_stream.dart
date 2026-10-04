import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ente_crypto/ente_crypto.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:photos/core/cache/video_cache_manager.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/network/network.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/module/download/file_url.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/utils/file_key.dart';

/// One playback attempt. The caller owns disposal, including when open returns
/// null. A null source means the existing full-download path should be used.
class ProgressiveVideoStream {
  static final _logger = Logger('ProgressiveVideo');

  ProgressiveVideoStream(this.file, {required this.onProgress}) {
    _source.future.ignore();
    _failure.future.ignore();
    _commands.future.ignore();
  }

  final EnteFile file;
  final void Function(int, int) onProgress;
  final _source = Completer<String?>();
  final _failure = Completer<void>();
  final _commands = Completer<SendPort>();
  final _exited = Completer<void>();
  final _events = ReceivePort();
  final _urlRequest = CancelToken();
  Isolate? _worker;
  Directory? _directory;
  Future<void>? _opening, _closing, _caching;
  String? url;

  /// Remains pending after download completion so player errors can still cause
  /// fallback. Disposal completes it normally; download/player errors reject it.
  Future<void> get failure => _failure.future;

  Future<String?> open() async {
    _opening = _start();
    await _opening;
    return _source.future;
  }

  Future<void> _start() async {
    final extension = p.extension(file.title ?? '').toLowerCase();
    final size = file.fileSize;
    final token = Configuration.instance.getToken();
    if (file.fileType != FileType.video ||
        !{'.mp4', '.mov', '.m4v'}.contains(extension) ||
        size == null ||
        size <= 0 ||
        token == null ||
        file.uploadedFileID == null ||
        file.collectionID == null ||
        file.fileDecryptionHeader == null ||
        CollectionsService.instance.isSharedPublicLink(file.collectionID!)) {
      _source.complete(null);
      return;
    }
    if (await VideoCacheManager.instance.getFileFromCache(file.downloadUrl) !=
        null) {
      if (!_source.isCompleted) {
        _source.complete(null);
      }
      return;
    }
    if (_closing != null) {
      return;
    }
    final signedUrl = await FileUrl.tryGetV3Url(
      NetworkClient.instance.enteDio,
      file.uploadedFileID!,
      FileUrlType.download,
      headers: {'X-Auth-Token': token},
      cancelToken: _urlRequest,
    );
    if (_closing != null) {
      return;
    }
    _directory = await Directory(
      Configuration.instance.getTempDirectory(),
    ).createTemp('video-');
    if (_closing != null) {
      return;
    }
    final output = '${_directory!.path}/original$extension';
    _events.listen((dynamic event) {
      switch (event) {
        case final SendPort port:
          _commands.complete(port);
        case (source: final String source):
          if (_closing == null && !_source.isCompleted) {
            url = source;
            _source.complete(source);
          }
        case (received: final int count):
          if (_closing == null) {
            onProgress(count, size);
          }
        case (complete: true):
          if (_closing == null) {
            _caching = _cache(output, extension.substring(1));
          }
        case (unsupported: true):
          if (!_source.isCompleted) {
            _source.complete(null);
          }
        case (error: final String kind):
          _fail(StateError('Progressive video failed ($kind)'));
        case null:
          _exited.complete();
          if (!_commands.isCompleted) {
            _commands.completeError(StateError('Video worker did not start'));
          }
          if (_closing == null) {
            _fail(StateError('Video worker exited'));
          }
      }
    });
    _worker = await Isolate.spawn(_runVideoServer, (
      events: _events.sendPort,
      source: signedUrl ?? file.downloadUrl,
      token: signedUrl == null ? token : null,
      output: output,
      size: size,
      header: CryptoUtil.base642bin(file.fileDecryptionHeader!),
      key: getFileKey(file),
    ), onExit: _events.sendPort);
    await _commands.future;
  }

  void playbackFailed() => _fail(StateError('Progressive player failed'));

  void _fail(Object error) {
    if (!_source.isCompleted) {
      _source.completeError(error);
    }
    if (!_failure.isCompleted) {
      _failure.completeError(error);
    }
  }

  Future<void> _cache(String output, String extension) async {
    try {
      await VideoCacheManager.instance.putFileStream(
        file.downloadUrl,
        File(output).openRead(),
        fileExtension: extension,
        maxAge: const Duration(days: 365),
      );
    } catch (error) {
      _logger.warning('Cache failed (${error.runtimeType})');
    }
  }

  Future<void> dispose() => _closing ??= _dispose();

  Future<void> _dispose() async {
    _urlRequest.cancel();
    if (!_source.isCompleted) {
      _source.complete(null);
    }
    if (!_failure.isCompleted) {
      _failure.complete();
    }
    await _opening?.catchError((Object _) {});
    if (_worker != null) {
      if (_commands.isCompleted && !_exited.isCompleted) {
        (await _commands.future).send(null);
      }
      try {
        await _exited.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        _worker!.kill(priority: Isolate.immediate);
        await _exited.future;
      }
    }
    await _caching;
    _events.close();
    try {
      await _directory?.delete(recursive: true);
    } on FileSystemException catch (error) {
      _logger.warning('Cleanup failed (${error.runtimeType})');
    }
  }
}

typedef _Download = ({
  SendPort events,
  String source,
  String? token,
  String output,
  int size,
  Uint8List header,
  Uint8List key,
});

Future<void> _runVideoServer(_Download download) =>
    _VideoServer(download).run();

class _VideoServer {
  _VideoServer(this.download);
  final _Download download;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  final _commands = ReceivePort();
  final _stopped = Completer<void>();
  Completer<void> _changed = Completer<void>();
  HttpServer? _server;
  int _written = 0;
  bool _closed = false;

  // Every encrypted Ente record adds 17 authentication bytes.
  int get _length =>
      download.size -
      ((download.size + decryptionChunkSize - 1) ~/ decryptionChunkSize) *
          (decryptionChunkSize - encryptionChunkSize);

  void _wakeReaders() {
    _changed.complete();
    _changed = Completer<void>();
  }

  Future<void> run() async {
    download.events.send(_commands.sendPort);
    _commands.listen((_) {
      _closed = true;
      _client.close(force: true);
      _wakeReaders();
      if (!_stopped.isCompleted) {
        _stopped.complete();
      }
    });
    RandomAccessFile? output;
    try {
      CryptoUtil.init();
      output = File(download.output).openSync(mode: FileMode.write);
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final random = Random.secure();
      final path =
          '/${List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}${p.extension(download.output)}';
      _server!.listen((request) => unawaited(_serve(request, path)));
      final request = await _client.getUrl(Uri.parse(download.source));
      // Legacy authenticated endpoints may redirect. Let the existing downloader
      // handle that path rather than forwarding X-Auth-Token to another host.
      request.followRedirects = download.token == null;
      if (download.token != null) {
        request.headers.set('X-Auth-Token', download.token!);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok ||
          (response.contentLength >= 0 &&
              response.contentLength != download.size)) {
        throw const HttpException('Unexpected encrypted video response');
      }
      var received = 0;
      final input = response.timeout(const Duration(seconds: 30)).map((bytes) {
        received += bytes.length;
        if (received > download.size) {
          throw const FormatException('Video too long');
        }
        return bytes;
      });
      await for (final bytes in decryptFileStream(
        input,
        header: download.header,
        key: download.key,
      )) {
        if (_closed) {
          return;
        }
        if (_written == 0 && !_hasFrontMovie(bytes)) {
          download.events.send((unsupported: true));
          return;
        }
        output.writeFromSync(bytes);
        final first = _written == 0;
        _written += bytes.length;
        _wakeReaders();
        if (first) {
          download.events.send((
            source: 'http://127.0.0.1:${_server!.port}$path',
          ));
        }
        download.events.send((received: received));
      }
      if (_closed) {
        return;
      }
      if (received != download.size || _written != _length) {
        throw const FormatException('Incomplete video');
      }
      output.closeSync();
      output = null;
      download.events.send((complete: true));
      await _stopped.future;
    } catch (error) {
      if (!_closed) {
        download.events.send((error: error.runtimeType.toString()));
      }
    } finally {
      _closed = true;
      _wakeReaders();
      _client.close(force: true);
      await _server?.close(force: true);
      output?.closeSync();
      _commands.close();
    }
  }

  Future<void> _serve(HttpRequest request, String path) async {
    final response = request.response;
    try {
      if (request.uri.path != path || request.headers.host != '127.0.0.1') {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final header = request.method == 'GET'
          ? request.headers.value('Range')
          : null;
      // Ignore unsupported range syntax (including multiple ranges) with a 200.
      final range = header == null
          ? null
          : RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header);
      var start = 0;
      var end = _length;
      if (range != null) {
        final left = int.tryParse(range[1]!);
        final right = int.tryParse(range[2]!);
        if (left == null) {
          start = max(0, end - (right ?? 0));
        } else {
          start = left;
          if (right != null) {
            end = min(end, right + 1);
          }
        }
        if (start >= end) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers.set('Content-Range', 'bytes */$_length');
          return;
        }
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          'Content-Range',
          'bytes $start-${end - 1}/$_length',
        );
      }
      response.headers
        ..set('Accept-Ranges', 'bytes')
        ..set(
          'Content-Type',
          download.output.endsWith('.mov') ? 'video/quicktime' : 'video/mp4',
        )
        ..set('Cache-Control', 'no-store')
        ..set('X-Content-Type-Options', 'nosniff');
      response.contentLength = end - start;
      if (request.method == 'HEAD') {
        return;
      }
      while (start < end && !_closed) {
        if (start >= _written) {
          await _changed.future;
        } else {
          final available = min(_written, end);
          await response.addStream(
            File(download.output).openRead(start, available),
          );
          start = available;
        }
      }
    } catch (_) {
      // The player closes range requests when seeking or switching sources.
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }
}

// Keep all metadata in the first record: the native plugin reads it synchronously.
// A moov box after mdat, or one extending beyond this record, uses full download.
bool _hasFrontMovie(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var offset = 0;
  while (offset + 8 <= bytes.length) {
    var size = data.getUint32(offset);
    final type = data.getUint32(offset + 4);
    var headerSize = 8;
    if (size == 1) {
      if (offset + 16 > bytes.length) {
        return false;
      }
      size = data.getUint64(offset + 8);
      headerSize = 16;
    }
    if (size < headerSize || size > bytes.length - offset) {
      return false;
    }
    if (type == 0x6d6f6f76) {
      return true; // moov
    }
    if (type == 0x6d646174) {
      return false; // mdat
    }
    offset += size;
  }
  return false;
}
