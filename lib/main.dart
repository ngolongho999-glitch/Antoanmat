import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

List<CameraDescription> _cameras = [];

// MÀN HÌNH TỐI ĐEN CHE TOÀN MÀN HÌNH KHI KHOẢNG CÁCH < 30CM
@pragma("vm:entry-point")
void overlayMain() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      ),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _cameras = await availableCameras();
  } catch (e) {
    debugPrint("Lỗi camera: $e");
  }
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: DistanceGuardApp(),
  ));
}

class DistanceGuardApp extends StatefulWidget {
  const DistanceGuardApp({super.key});

  @override
  State<DistanceGuardApp> createState() => _DistanceGuardAppState();
}

class _DistanceGuardAppState extends State<DistanceGuardApp> {
  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  bool _isProcessing = false;
  bool _isServiceRunning = false;
  bool _isOverlayShowing = false;
  double _calculatedDistanceCm = 0.0;

  @override
  void initState() {
    super.initState();
    _initForegroundTask();
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'eye_guard_channel',
        channelName: 'Bảo Vệ Khoảng Cách Mắt',
        channelDescription: 'Đang chạy ngầm để giám sát khoảng cách mắt',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  Future<void> _toggleService() async {
    if (_isServiceRunning) {
      _stopGuardService();
    } else {
      await Permission.camera.request();
      await Permission.notification.request();

      bool isGranted = await FlutterOverlayWindow.isPermissionGranted();
      if (!isGranted) {
        await FlutterOverlayWindow.requestPermission();
        return;
      }

      _startGuardService();
    }
  }

  Future<void> _startGuardService() async {
    // Khởi chạy thông báo chạy ngầm bắt buộc để giữ Camera hoạt động ngoài app
    await FlutterForegroundTask.startService(
      notificationTitle: 'Bảo Vệ Mắt Đang Bật',
      notificationText: 'Sẽ tự động tối màn hình khi xem quá gần',
    );

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
    );

    if (_cameras.isEmpty) {
      _cameras = await availableCameras();
    }
    if (_cameras.isEmpty) return;

    final frontCamera = _cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    await _cameraController!.initialize();
    await _cameraController!.startImageStream(_processImageStream);

    setState(() {
      _isServiceRunning = true;
    });
  }

  void _processImageStream(CameraImage image) async {
    if (_isProcessing || _faceDetector == null || _cameraController == null) return;
    _isProcessing = true;

    try {
      final camera = _cameraController!.description;
      final imageRotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation270deg;
      final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;

      final inputImage = InputImage.fromBytes(
        bytes: image.planes[0].bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: imageRotation,
          format: inputImageFormat,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final faces = await _faceDetector!.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        double faceWidthInPixels = face.boundingBox.width;
        double distance = (image.width * 18.0) / faceWidthInPixels;

        if (mounted) {
          setState(() {
            _calculatedDistanceCm = distance;
          });
        }

        // KHOẢNG CÁCH <= 30CM: TỐI MÀN HÌNH (DÙ ĐANG Ở YOUTUBE HAY BẤT KỲ APP NÀO)
        if (distance <= 30.0 && !_isOverlayShowing) {
          _isOverlayShowing = true;
          await FlutterOverlayWindow.showOverlay(
            enableDrag: false,
            flag: OverlayFlag.defaultFlag,
            alignment: OverlayAlignment.center,
            visibility: NotificationVisibility.visibilitySecret,
            positionGravity: PositionGravity.none,
          );
        } 
        // KHOẢNG CÁCH > 30CM: MÀN HÌNH SÁNG LẠI Y CŨ
        else if (distance > 30.0 && _isOverlayShowing) {
          _isOverlayShowing = false;
          await FlutterOverlayWindow.closeOverlay();
        }
      }
    } catch (e) {
      debugPrint("Lỗi đo: $e");
    } finally {
      await Future.delayed(const Duration(milliseconds: 150));
      _isProcessing = false;
    }
  }

  void _stopGuardService() async {
    await FlutterForegroundTask.stopService();
    await _cameraController?.stopImageStream();
    await _cameraController?.dispose();
    await _faceDetector?.close();
    if (_isOverlayShowing) {
      _isOverlayShowing = false;
      await FlutterOverlayWindow.closeOverlay();
    }
    setState(() {
      _isServiceRunning = false;
      _calculatedDistanceCm = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Bảo Vệ Khoảng Cách Mắt"),
          backgroundColor: Colors.blueGrey,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Khoảng cách: ${_calculatedDistanceCm.toStringAsFixed(1)} cm",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: _calculatedDistanceCm <= 30 && _calculatedDistanceCm > 0 ? Colors.red : Colors.green,
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _toggleService,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isServiceRunning ? Colors.red : Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
                child: Text(
                  _isServiceRunning ? "TẮT BẢO VỆ" : "BẬT BẢO VỆ",
                  style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
