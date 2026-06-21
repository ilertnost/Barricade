import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../models/models.dart';
import 'api_service.dart';

/// Result of a save/open action, for showing user feedback.
class TransferResult {
  final bool ok;
  final String message;
  TransferResult(this.ok, this.message);
}

/// Downloading a chat file (with auth), then opening it in an external app or
/// saving it to the public Downloads folder via MediaStore (scoped-storage safe).
class FileSaver {
  static const _channel = MethodChannel('barricade/downloads');

  /// GET the file bytes (auth) and write to a temp file named [filename].
  static Future<File> _downloadToTemp(String fileId, String filename) async {
    final headers = await ApiService.headers();
    final res = await http.get(Uri.parse(ApiService.getFileUrl(fileId)), headers: headers);
    if (res.statusCode != 200 && res.statusCode != 206) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final dir = await getTemporaryDirectory();
    final safe = filename.isEmpty ? fileId : filename.replaceAll(RegExp(r'[/\\]'), '_');
    final file = File('${dir.path}/$safe');
    await file.writeAsBytes(res.bodyBytes);
    return file;
  }

  /// Download (if needed) and open with an external app.
  static Future<TransferResult> openExternally(String fileId, String filename) async {
    try {
      final file = await _downloadToTemp(fileId, filename);
      final res = await OpenFilex.open(file.path);
      if (res.type == ResultType.done) return TransferResult(true, 'Открыто');
      if (res.type == ResultType.noAppToOpen) {
        return TransferResult(false, 'Нет приложения для этого типа файла');
      }
      if (res.type == ResultType.permissionDenied) {
        return TransferResult(false, 'Нет разрешения на открытие');
      }
      return TransferResult(false, res.message);
    } catch (e) {
      return TransferResult(false, 'Не удалось открыть: $e');
    }
  }

  /// Download and save to the public Downloads/Barricade folder.
  /// On non-Android, saves to a temporary location and opens the file.
  static Future<TransferResult> saveToDownloads(String fileId, FileInfo? info) async {
    final name = info?.originalName ?? fileId;
    final mime = info?.mimeType ?? 'application/octet-stream';
    try {
      final file = await _downloadToTemp(fileId, name);
      if (!Platform.isAndroid) {
        final res = await OpenFilex.open(file.path);
        if (res.type == ResultType.done) return TransferResult(true, 'Файл открыт');
        return TransferResult(false, res.message);
      }
      final ok = await _channel.invokeMethod<bool>('saveToDownloads', {
        'path': file.path,
        'name': name,
        'mime': mime,
      });
      if (ok == true) return TransferResult(true, 'Сохранено в Загрузки');
      return TransferResult(false, 'Не удалось сохранить');
    } on PlatformException catch (e) {
      return TransferResult(false, 'Ошибка сохранения: ${e.message}');
    } catch (e) {
      return TransferResult(false, 'Ошибка сохранения: $e');
    }
  }
}
