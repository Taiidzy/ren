import 'dart:math' as math;
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:record/record.dart';
import 'package:camera/camera.dart';
import 'package:ffmpeg_kit_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_min_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';

import 'package:ren/features/chats/presentation/widgets/chat_attach_menu.dart';
import 'package:ren/features/chats/presentation/widgets/chat_pending_attachment.dart';
import 'package:ren/shared/widgets/glass_surface.dart';
import 'package:ren/features/chats/presentation/widgets/chat_recorder_ui.dart';
import 'package:ren/shared/widgets/glass_snackbar.dart';

final Logger _logger = Logger();

class ChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isDark;
  final bool isEditing;
  final VoidCallback onCancelEditing;
  final bool hasReply;
  final String replyText;
  final VoidCallback onCancelReply;
  final List<PendingChatAttachment> pending;
  final void Function(int index) onRemovePending;
  final void Function(int index)? onRetryPending;
  final Future<void> Function() onPickPhotos;
  final Future<void> Function() onPickFiles;
  final Future<void> Function() onTakePhoto;
  final VoidCallback onSend;
  final void Function(RecorderMode mode, bool isRecording)? onRecordingChanged;
  final void Function(String durationText)? onRecordingDurationChanged;
  final void Function(RecorderMode mode, bool isLocked)?
  onRecordingLockedChanged;
  final void Function(VoidCallback cancel, VoidCallback stop)?
  onRecorderController;
  final Future<void> Function(PendingChatAttachment attachment)?
  onAddRecordedFile;
  final void Function(CameraController? controller)? onVideoControllerChanged;
  final void Function(
    Future<bool> Function(bool enabled) setTorch,
    Future<bool> Function(bool useFront) setUseFrontCamera,
  )?
  onVideoActionsController;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isDark,
    required this.isEditing,
    required this.onCancelEditing,
    required this.hasReply,
    required this.replyText,
    required this.onCancelReply,
    required this.pending,
    required this.onRemovePending,
    this.onRetryPending,
    required this.onPickPhotos,
    required this.onPickFiles,
    required this.onTakePhoto,
    required this.onSend,
    this.onRecordingChanged,
    this.onRecordingDurationChanged,
    this.onRecordingLockedChanged,
    this.onRecorderController,
    this.onAddRecordedFile,
    this.onVideoControllerChanged,
    this.onVideoActionsController,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final GlobalKey<ChatRecorderButtonState> _recorderKey =
      GlobalKey<ChatRecorderButtonState>();

  VoidCallback? _controllerListener;

  bool _lastShowSendButton = false;

  RecorderMode _activeRecordingMode = RecorderMode.audio;

  bool _isRecording = false;
  bool _isRecordingLocked = false;
  String _durationText = "0:00";
  Timer? _timer;
  int _seconds = 0;

  // Audio recording
  final AudioRecorder _audioRecorder = AudioRecorder();

  // Video recording
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _videoEnableAudio = true;
  bool _useFrontCamera = false;
  List<CameraDescription>? _availableCameras;
  final List<String> _videoSegmentPaths = <String>[];
  bool _isSwitchingVideoCamera = false;

  void _disposeCamera() {
    widget.onVideoControllerChanged?.call(null);
    _cameraController?.dispose();
    _cameraController = null;
    _isCameraInitialized = false;
  }

  Future<List<CameraDescription>> _getCameras() async {
    _availableCameras ??= await availableCameras();
    return _availableCameras!;
  }

  CameraDescription? _pickCamera(
    List<CameraDescription> cams, {
    required bool useFront,
  }) {
    if (cams.isEmpty) return null;
    final desired = useFront
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final found = cams.where((c) => c.lensDirection == desired).toList();
    return found.isNotEmpty ? found.first : cams.first;
  }

  Future<bool> _setTorch(bool enabled) async {
    final c = _cameraController;
    if (c == null || !c.value.isInitialized) {
      _showPermissionSnack('Камера не инициализирована.');
      return false;
    }
    try {
      await c.setFlashMode(enabled ? FlashMode.torch : FlashMode.off);
      return true;
    } catch (_) {
      _showInfoSnack('Фонарик недоступен на этой камере.');
      return false;
    }
  }

  Future<bool> _setUseFrontCamera(bool useFront) async {
    if (_isSwitchingVideoCamera) return false;

    final current = _cameraController;
    final wasRecording = current != null && current.value.isRecordingVideo;

    _isSwitchingVideoCamera = true;
    try {
      if (wasRecording) {
        try {
          final file = await current.stopVideoRecording();
          _videoSegmentPaths.add(file.path);
        } catch (_) {
          _showPermissionSnack('Не удалось переключить камеру.');
          return false;
        }
      }

      _useFrontCamera = useFront;

      final cams = await _getCameras();
      final desc = _pickCamera(cams, useFront: useFront);
      if (desc == null) {
        _showPermissionSnack('Камера недоступна на устройстве.');
        return false;
      }

      _disposeCamera();
      try {
        _cameraController = CameraController(
          desc,
          ResolutionPreset.high,
          enableAudio: _videoEnableAudio,
        );
        await _cameraController!.initialize();
        _isCameraInitialized = true;
        await _setTorch(false);
        widget.onVideoControllerChanged?.call(_cameraController);
        if (mounted) setState(() {});
      } catch (_) {
        _disposeCamera();
        _showPermissionSnack('Не удалось инициализировать камеру.');
        return false;
      }

      if (wasRecording) {
        final ok = await _startVideoRecording();
        if (!ok) {
          _showPermissionSnack(
            'Не удалось продолжить запись после переключения.',
          );
          return false;
        }
      }

      return true;
    } finally {
      _isSwitchingVideoCamera = false;
    }
  }

  // Слушатель для кнопки Send/Mic
  bool get _hasQueuedPending => widget.pending.any((p) => p.canSend);
  bool get _showSendButton =>
      widget.controller.text.trim().isNotEmpty || _hasQueuedPending;

  @override
  void initState() {
    super.initState();
    _lastShowSendButton = _showSendButton;
    _controllerListener = () {
      if (!mounted) return;
      final next = _showSendButton;
      if (next == _lastShowSendButton) {
        return;
      }
      _lastShowSendButton = next;
      setState(() {});
    };
    widget.controller.addListener(_controllerListener!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onRecorderController?.call(
        () => _recorderKey.currentState?.cancelRecording(),
        () => _recorderKey.currentState?.stopRecording(),
      );
      widget.onVideoActionsController?.call(_setTorch, _setUseFrontCamera);
    });
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller &&
        _controllerListener != null) {
      oldWidget.controller.removeListener(_controllerListener!);
      widget.controller.addListener(_controllerListener!);
    }

    final next = _showSendButton;
    if (next != _lastShowSendButton && mounted) {
      _lastShowSendButton = next;
      setState(() {});
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onRecorderController?.call(
        () => _recorderKey.currentState?.cancelRecording(),
        () => _recorderKey.currentState?.stopRecording(),
      );
      widget.onVideoActionsController?.call(_setTorch, _setUseFrontCamera);
    });
  }

  void _startTimer() {
    _seconds = 0;
    _durationText = "0:00";
    widget.onRecordingDurationChanged?.call(_durationText);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _seconds++;
      if (_activeRecordingMode == RecorderMode.video && _seconds >= 60) {
        _recorderKey.currentState?.stopRecording();
        return;
      }
      final m = (_seconds ~/ 60).toString();
      final s = (_seconds % 60).toString().padLeft(2, '0');
      if (mounted) {
        setState(() {
          _durationText = "$m:$s";
        });
      }
      widget.onRecordingDurationChanged?.call(_durationText);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
  }

  void _resetRecordingUi() {
    _isRecording = false;
    _isRecordingLocked = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_controllerListener != null) {
      widget.controller.removeListener(_controllerListener!);
    }
    _audioRecorder.dispose();
    _disposeCamera();
    super.dispose();
  }

  void _showPermissionSnack(String text, {VoidCallback? action}) {
    if (!mounted) return;
    showGlassSnack(
      context,
      text,
      kind: GlassSnackKind.error,
      duration: const Duration(seconds: 3),
      actionLabel: action == null ? null : 'Настройки',
      onAction: action,
    );
  }

  void _showInfoSnack(String text) {
    if (!mounted) return;
    showGlassSnack(
      context,
      text,
      kind: GlassSnackKind.info,
      duration: const Duration(seconds: 3),
    );
  }

  Future<bool> _requestPermissions(RecorderMode mode) async {
    if (mode == RecorderMode.audio) {
      try {
        final allowed = await _audioRecorder.hasPermission();
        if (allowed) return true;
      } catch (_) {}

      final micStatus = await Permission.microphone.request();
      return micStatus.isGranted;
    } else {
      final cameraBefore = await Permission.camera.status;
      final micBefore = await Permission.microphone.status;

      // Some OEMs / app states may report denied here even when camera works
      // (e.g. via image_picker). We only hard-fail on permanentlyDenied/restricted.
      if (cameraBefore.isPermanentlyDenied || cameraBefore.isRestricted) {
        _showPermissionSnack(
          'Нет доступа к камере. Разреши доступ в настройках.',
          action: () => openAppSettings(),
        );
        return false;
      }

      // Request (best-effort). Even if it returns denied, we still try to init camera.
      await Permission.camera.request();

      // Microphone is optional for video.
      bool micAllowed = micBefore.isGranted;
      if (!micAllowed) {
        try {
          micAllowed = await _audioRecorder.hasPermission();
        } catch (_) {}
      }

      if (micAllowed) {
        _videoEnableAudio = true;
      } else {
        final micAfter = await Permission.microphone.request();
        _videoEnableAudio = micAfter.isGranted;
        if (!_videoEnableAudio) {
          _showInfoSnack(
            'Микрофон недоступен. Видео будет записано без звука.',
          );
        }
      }

      return true;
    }
  }

  Future<bool> _initializeCamera() async {
    if (_isCameraInitialized && _cameraController != null) return true;

    try {
      final cameras = await _getCameras();
      if (cameras.isEmpty) {
        _logger.e('No cameras available');
        _showPermissionSnack('Камера недоступна на устройстве.');
        return false;
      }

      final camera =
          _pickCamera(cameras, useFront: _useFrontCamera) ?? cameras.first;
      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: _videoEnableAudio,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
      widget.onVideoControllerChanged?.call(_cameraController);
      return true;
    } catch (e) {
      _logger.e('Camera initialization failed: $e');
      _showPermissionSnack('Не удалось инициализировать камеру.');
      return false;
    }
  }

  Future<void> _startAudioRecording() async {
    try {
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${dir.path}/voice_$timestamp.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );
    } catch (e) {
      _logger.e('Failed to start audio recording: $e');
    }
  }

  Future<bool> _startVideoRecording() async {
    if (!_isCameraInitialized || _cameraController == null) {
      final ok = await _initializeCamera();
      if (!ok) return false;
    }

    if (!_isCameraInitialized || _cameraController == null) {
      _logger.w('Camera not initialized');
      _showPermissionSnack('Камера не инициализирована.');
      return false;
    }

    try {
      await _cameraController!.startVideoRecording();
      return true;
    } catch (e) {
      _logger.e('Failed to start video recording: $e');
      _showPermissionSnack('Не удалось начать запись видео.');
      return false;
    }
  }

  Future<String?> _concatVideoSegments(List<String> segmentPaths) async {
    if (segmentPaths.isEmpty) return null;
    if (segmentPaths.length == 1) return segmentPaths.first;

    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final listFile = File('${dir.path}/video_concat_$ts.txt');
    final outPath = '${dir.path}/video_merged_$ts.mp4';

    final lines = segmentPaths
        .map((p) {
          final escaped = p.replaceAll("'", "'\\''");
          return "file '$escaped'";
        })
        .join('\n');
    await listFile.writeAsString(lines);

    final audioArgs = _videoEnableAudio ? "-c:a aac -b:a 128k" : "-an";
    final cmd =
        "-y -f concat -safe 0 -i '${listFile.path}' -c:v libx264 -preset ultrafast -crf 23 $audioArgs -movflags +faststart '$outPath'";
    try {
      final session = await FFmpegKit.execute(cmd);
      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc)) {
        return null;
      }

      final outFile = File(outPath);
      if (!await outFile.exists()) return null;
      return outPath;
    } on MissingPluginException {
      _showInfoSnack(
        'Склейка видео недоступна (плагин не подключен). Отправляем без склейки.',
      );
      return null;
    } catch (_) {
      _logger.e('Failed to concat video segments');
      _showInfoSnack('Не удалось склеить видео. Отправляем без склейки.');
      return null;
    } finally {
      try {
        if (await listFile.exists()) await listFile.delete();
      } catch (_) {}
    }
  }

  Future<String?> _stopAudioRecording() async {
    try {
      final path = await _audioRecorder.stop();
      return path;
    } catch (e) {
      _logger.e('Failed to stop audio recording: $e');
      return null;
    }
  }

  Future<String?> _stopVideoRecording() async {
    if (_cameraController == null ||
        !_cameraController!.value.isRecordingVideo) {
      if (_videoSegmentPaths.isEmpty) return null;
      final merged = await _concatVideoSegments(
        List<String>.from(_videoSegmentPaths),
      );
      return merged;
    }

    try {
      final file = await _cameraController!.stopVideoRecording();
      final segmentPath = file.path;
      _videoSegmentPaths.add(segmentPath);
      _disposeCamera();

      final merged = await _concatVideoSegments(
        List<String>.from(_videoSegmentPaths),
      );
      if (merged == null) {
        // Fallback: send the last recorded segment.
        return segmentPath;
      }

      for (final p in _videoSegmentPaths) {
        if (p == merged) continue;
        try {
          final f = File(p);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      _videoSegmentPaths
        ..clear()
        ..add(merged);

      return merged;
    } catch (e) {
      _logger.e('Failed to stop video recording: $e');
      _disposeCamera();
      return null;
    }
  }

  Future<void> _cancelRecording() async {
    if (_activeRecordingMode == RecorderMode.audio) {
      try {
        final path = await _audioRecorder.stop();
        if (path != null) {
          final audioFile = File(path);
          if (await audioFile.exists()) {
            await audioFile.delete();
          }
        }
      } catch (_) {}
    } else {
      if (_cameraController != null &&
          _cameraController!.value.isRecordingVideo) {
        try {
          final file = await _cameraController!.stopVideoRecording();
          final videoFile = File(file.path);
          if (await videoFile.exists()) {
            await videoFile.delete();
          }
        } catch (_) {}
      }
      _disposeCamera();

      for (final p in _videoSegmentPaths) {
        try {
          final f = File(p);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      _videoSegmentPaths.clear();
    }
  }

  Future<void> _handleRecordedFile(String? path, RecorderMode mode) async {
    if (path == null || !await File(path).exists()) {
      return;
    }

    final file = File(path);
    final size = await file.length();

    String filename;
    String mimetype;

    if (mode == RecorderMode.audio) {
      filename = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      mimetype = 'audio/m4a';
    } else {
      filename = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      mimetype = 'video/mp4';
    }

    final attachment = PendingChatAttachment(
      clientId: 'pending_${DateTime.now().microsecondsSinceEpoch}',
      filename: filename,
      mimetype: mimetype,
      sizeBytes: size,
      localPath: path,
    );

    await widget.onAddRecordedFile?.call(attachment);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 360;

    const double inputHeight = 44;
    final outerHorizontal = compact ? 10.0 : 14.0;
    final pendingTileSize = compact ? 56.0 : 64.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(outerHorizontal, 10, outerHorizontal, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isRecording) ...[
            if (widget.isEditing)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassSurface(
                  borderRadius: 16,
                  blurSigma: 10,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Редактирование',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: widget.onCancelEditing,
                        child: Icon(
                          Icons.close,
                          size: 18,
                          color: theme.colorScheme.onSurface.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (widget.hasReply)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeOut,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SizeTransition(
                      sizeFactor: animation,
                      axisAlignment: -1,
                      child: child,
                    ),
                  );
                },
                child: Padding(
                  key: ValueKey<String>('reply_${widget.replyText.trim()}'),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassSurface(
                    borderRadius: 16,
                    blurSigma: 12,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.reply,
                          size: 16,
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.replyText.trim().isNotEmpty
                                ? widget.replyText.trim()
                                : 'Сообщение',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.9,
                              ),
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: widget.onCancelReply,
                          child: Icon(
                            Icons.close,
                            size: 18,
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (widget.pending.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  height: pendingTileSize,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.pending.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final p = widget.pending[index];
                      final isImg = p.mimetype.startsWith('image/');
                      final canRetry =
                          p.canRetry && widget.onRetryPending != null;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: pendingTileSize,
                              height: pendingTileSize,
                              color: theme.colorScheme.surface,
                              child: isImg
                                  ? (() {
                                      final lp = p.localPath;
                                      if (lp != null && lp.isNotEmpty) {
                                        return Image.file(
                                          File(lp),
                                          fit: BoxFit.cover,
                                          errorBuilder: (c, e, s) =>
                                              const SizedBox(),
                                        );
                                      }
                                      final b = p.bytes;
                                      if (b == null || b.isEmpty) {
                                        return const SizedBox();
                                      }
                                      return Image.memory(
                                        b,
                                        fit: BoxFit.cover,
                                        errorBuilder: (c, e, s) =>
                                            const SizedBox(),
                                      );
                                    })()
                                  : Center(
                                      child: Icon(
                                        Icons.insert_drive_file,
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.65),
                                      ),
                                    ),
                            ),
                          ),
                          Positioned(
                            right: -6,
                            top: -6,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (canRetry)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: GestureDetector(
                                      onTap: () =>
                                          widget.onRetryPending?.call(index),
                                      child: Container(
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.surface,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: theme.colorScheme.onSurface
                                                .withOpacity(0.25),
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.refresh,
                                          size: 13,
                                          color: theme.colorScheme.onSurface
                                              .withOpacity(0.85),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (p.canRemove)
                                  GestureDetector(
                                    onTap: () => widget.onRemovePending(index),
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surface,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: theme.colorScheme.onSurface
                                              .withOpacity(0.25),
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.close,
                                        size: 14,
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.8),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (p.isSending)
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (p.isFailed)
                            Positioned(
                              left: 6,
                              right: 6,
                              bottom: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.error.withOpacity(
                                    0.88,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Ошибка',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: theme.colorScheme.onError,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
          ],

          Row(
            children: [
              if (!_isRecording)
                GlassSurface(
                  borderRadius: 18,
                  blurSigma: 12,
                  width: inputHeight,
                  height: inputHeight,
                  onTap: () => showChatAttachMenu(
                    context,
                    onPickPhotos: () async => await widget.onPickPhotos(),
                    onPickFiles: () async => await widget.onPickFiles(),
                    onTakePhoto: () async => await widget.onTakePhoto(),
                  ),
                  child: Center(
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedAttachment01,
                      color: theme.colorScheme.onSurface.withOpacity(0.9),
                      size: 18,
                    ),
                  ),
                ),
              if (!_isRecording) const SizedBox(width: 10),
              Expanded(
                child: GlassSurface(
                  borderRadius: 18,
                  blurSigma: 12,
                  height: inputHeight,
                  borderColor: theme.colorScheme.onSurface.withOpacity(
                    widget.isDark ? 0.20 : 0.10,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeOut,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SizeTransition(
                          sizeFactor: animation,
                          axisAlignment: -1,
                          child: child,
                        ),
                      );
                    },
                    child: _isRecording
                        ? Padding(
                            key: const ValueKey('recording_ui'),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.error,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _durationText,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const Spacer(),
                                if (_isRecordingLocked) ...[
                                  Text(
                                    'Отмена',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.75),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  GlassSurface(
                                    borderRadius: 18,
                                    blurSigma: 12,
                                    width: 32,
                                    height: 32,
                                    onTap: () {
                                      _recorderKey.currentState
                                          ?.cancelRecording();
                                    },
                                    child: Center(
                                      child: HugeIcon(
                                        icon: HugeIcons.strokeRoundedCancel01,
                                        size: 16,
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.85),
                                      ),
                                    ),
                                  ),
                                ] else ...[
                                  ShimmerText(
                                    text: '< Свайп для отмены',
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.6),
                                  ),
                                  const SizedBox(width: 20),
                                ],
                              ],
                            ),
                          )
                        : TextField(
                            key: const ValueKey('input_field'),
                            controller: widget.controller,
                            focusNode: widget.focusNode,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 14,
                            ),
                            cursorColor: theme.colorScheme.primary,
                            decoration: InputDecoration(
                              hintText: 'Введите сообщение...',
                              hintStyle: TextStyle(
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.55,
                                ),
                              ),
                              filled: false,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                            ),
                          ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Кнопка записи / Отправки
              ChatRecorderButton(
                key: _recorderKey,
                showSendButton: _showSendButton,
                onSendText: widget.onSend,
                onStartRecording: (mode) async {
                  final hasPermission = await _requestPermissions(mode);
                  if (!hasPermission) {
                    return false;
                  }

                  bool started = false;

                  if (mode == RecorderMode.audio) {
                    setState(() {
                      _isRecording = true;
                      _isRecordingLocked = false;
                    });
                    _activeRecordingMode = mode;
                    widget.onRecordingChanged?.call(mode, true);
                    widget.onRecordingLockedChanged?.call(mode, false);
                    _startTimer();
                    await _startAudioRecording();
                    started = true;
                  } else {
                    _videoSegmentPaths.clear();

                    // For video, verify camera initialization/recording actually started.
                    final ok = await _startVideoRecording();
                    if (!ok) {
                      widget.onRecordingChanged?.call(mode, false);
                      widget.onRecordingLockedChanged?.call(mode, false);
                      return false;
                    }

                    setState(() {
                      _isRecording = true;
                      _isRecordingLocked = false;
                    });
                    _activeRecordingMode = mode;
                    widget.onRecordingChanged?.call(mode, true);
                    widget.onRecordingLockedChanged?.call(mode, false);
                    _startTimer();
                    started = true;
                  }

                  return started;
                },
                onStopRecording: (mode, path, canceled) async {
                  String? recordedPath;

                  // Stop UI/timer immediately to avoid confusing lag.
                  if (mounted) {
                    setState(() {
                      _resetRecordingUi();
                    });
                  }
                  _stopTimer();
                  widget.onRecordingChanged?.call(mode, false);
                  widget.onRecordingLockedChanged?.call(mode, false);

                  if (!canceled) {
                    if (mode == RecorderMode.audio) {
                      recordedPath = await _stopAudioRecording();
                    } else {
                      recordedPath = await _stopVideoRecording();
                    }

                    if (recordedPath != null) {
                      await _handleRecordedFile(recordedPath, mode);
                    }
                  } else {
                    await _cancelRecording();
                  }
                },
                onCancelRecording: () async {
                  await _cancelRecording();
                  setState(() {
                    _resetRecordingUi();
                  });
                  _stopTimer();
                  widget.onRecordingChanged?.call(_activeRecordingMode, false);
                  widget.onRecordingLockedChanged?.call(
                    _activeRecordingMode,
                    false,
                  );
                },
                onLockRecording: () {
                  if (!mounted) return;
                  setState(() {
                    _isRecordingLocked = true;
                  });
                  widget.onRecordingLockedChanged?.call(
                    _activeRecordingMode,
                    true,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Простой виджет для мерцающего текста (Slide to cancel)
class ShimmerText extends StatefulWidget {
  final String text;
  final Color color;
  const ShimmerText({super.key, required this.text, required this.color});

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.5 + 0.5 * math.sin(_controller.value * 2 * math.pi).abs(),
          child: Text(widget.text, style: TextStyle(color: widget.color)),
        );
      },
    );
  }
}
