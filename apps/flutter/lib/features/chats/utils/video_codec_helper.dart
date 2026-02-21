import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_min_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';

/// Helper для обработки видео с несовместимыми кодеками (HEVC/H.265)
class VideoCodecHelper {
  static const _supportedExtensions = ['.mp4', '.mov', '.mkv', '.webm', '.avi'];

  /// Проверяет, является ли видео HEVC/H.265 по расширению или имени файла
  static bool isPossibleHevcVideo(String path) {
    final lowerPath = path.toLowerCase();
    // Проверяем по расширению
    if (!_supportedExtensions.any((ext) => lowerPath.endsWith(ext))) {
      return false;
    }
    // Проверяем по наличию hevc/h265/hvc в имени
    return lowerPath.contains('hevc') || 
           lowerPath.contains('h265') || 
           lowerPath.contains('hvc1') ||
           lowerPath.contains('hvc2');
  }

  /// Конвертирует HEVC видео в H.264 с помощью FFmpeg
  /// Возвращает путь к сконвертированному файлу или null при ошибке
  static Future<String?> convertHevcToH264(String inputPath) async {
    try {
      debugPrint('Starting HEVC to H.264 conversion for: $inputPath');
      
      final inputFile = File(inputPath);
      if (!await inputFile.exists()) {
        debugPrint('Input file does not exist: $inputPath');
        return null;
      }

      // Создаём временный файл для вывода
      final tempDir = await getTemporaryDirectory();
      final fileName = inputFile.uri.pathSegments.last.replaceAll('.mp4', '');
      final outputPath = '${tempDir.path}/converted_${fileName}_h264.mp4';
      
      // Проверяем, существует ли уже сконвертированный файл
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        debugPrint('Using cached converted file: $outputPath');
        return outputPath;
      }

      // FFmpeg команда для конвертации в H.264
      // Используем libx264 для максимальной совместимости
      final ffmpegCommand = '-i "$inputPath" '
          '-c:v libx264 '           // Видео кодек H.264
          '-preset fast '            // Быстрая кодировка
          '-crf 28 '                 // Качество (выше = хуже качество, меньше размер)
          '-c:a aac '                // Аудио кодек AAC
          '-b:a 128k '               // Аудио битрейт
          '-movflags +faststart '    // Быстрый старт для стриминга
          '-y "$outputPath"';        // Перезаписать если существует

      debugPrint('Executing FFmpeg command: $ffmpegCommand');

      final session = await FFmpegKit.execute(ffmpegCommand);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        debugPrint('Successfully converted video to: $outputPath');
        return outputPath;
      } else {
        final failStackTrace = await session.getFailStackTrace();
        debugPrint('FFmpeg conversion failed: $failStackTrace');
        return null;
      }
    } catch (e, st) {
      debugPrint('Error during video conversion: $e\n$st');
      return null;
    }
  }

  /// Пытается воспроизвести видео, конвертируя при необходимости
  /// Возвращает путь к файлу для воспроизведения (оригинал или конвертированный)
  static Future<String?> getPlayableVideoPath(String inputPath) async {
    // Сначала пробуем оригинальный файл
    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      return null;
    }

    // Если это возможно HEVC видео, пробуем сконвертировать
    if (isPossibleHevcVideo(inputPath)) {
      debugPrint('Detected possible HEVC video, attempting conversion...');
      final convertedPath = await convertHevcToH264(inputPath);
      if (convertedPath != null) {
        return convertedPath;
      }
      debugPrint('Conversion failed, will try original file');
    }

    return inputPath;
  }

  /// Очищает кэш конвертированных видео
  static Future<void> clearCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(tempDir.path);
      if (await dir.exists()) {
        await dir.list().forEach((entity) async {
          if (entity is File && 
              entity.path.contains('converted_') && 
              entity.path.contains('_h264.mp4')) {
            await entity.delete();
          }
        });
      }
      debugPrint('Video conversion cache cleared');
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }
}
