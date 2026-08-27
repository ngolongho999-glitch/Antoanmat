import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:system_alert_window/system_alert_window.dart';

List<CameraDescription> _cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _cameras = await availableCameras();
  } catch (e) {
    debugPrint("Lỗi camera: $e");
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: DistanceScreenGuard(),
    );
  }
}

class DistanceScreenGuard extends StatefulWidget {
  const DistanceScreenGuard({super.key});

  @override
  State<DistanceScreenGuard> createState() => _DistanceScreenGuardState();
}

class _DistanceScreenGuardState extends State<DistanceScreenGuard> {
  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  bool _isProcessing = false;
  bool _isOverlayShowing = false;
  bool _isServiceRunning = false;
  double _calculatedDistanceCm = 0.0;
  String _statusText = "Sẵn sàng khởi chạy";

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    await Permission.camera.request();
    bool? isGranted = await SystemAlertWindow.checkPermissions();
    if (isGranted != true) {
      await SystemAlertWindow.requestPermissions();
    }
  }

  Future<void> _startGuardService() async {
    bool? isGranted = await SystemAlertWindow.checkPermissions();
    if (isGranted != true) {
      await SystemAlertWindow.requestPermissions();
      return;
    }

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
      ),
    );

    if (_cameras.isEmpty) {
      _cameras = await availableCameras();
    }

    if (_cameras.isEmpty) {
      if (mounted) setState(() => _statusText = "Không tìm thấy camera!");
      return;
    }

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

    try {
      await _cameraController!.initialize();
      await _cameraController!.startImageStream(_processCameraImage);
      if (mounted) {
        setState(() {
          _isServiceRunning = true;
          _statusText = "Bảo vệ mắt đang chạy ngầm...";
        });
      }
    } catch (e) {
      if (mounted) setState(() => _statusText = "Lỗi khởi tạo: $e");
    }
  }

  void _processCameraImage(CameraImage image) async {
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
        double estimatedDistance = (image.width * 18.0) / faceWidthInPixels;

        if (mounted) {
          setState(() {
            _calculatedDistanceCm = estimatedDistance;
          });
        }

        if (estimatedDistance <= 30.0) {
          _showOverlay();
        } else {
          _hideOverlay();
        }
      } else {
        if (_calculatedDistanceCm > 0 && _calculatedDistanceCm <= 35.0) {
          _showOverlay();
        }
      }
    } catch (e) {
      debugPrint("Lỗi nhận diện: $e");
    } finally {
      await Future.delayed(const Duration(milliseconds: 100));
      _isProcessing = false;
    }
  }

  void _showOverlay() async {
    if (_isOverlayShowing) return;
    _isOverlayShowing = true;

    await SystemAlertWindow.showSystemWindow(
      height: 2500,
      width: 1500,
      gravity: SystemWindowGravity.CENTER,
      prefMode: SystemWindowPrefMode.OVERLAY,
      notificationTitle: "CẢNH BÁO KHOẢNG CÁCH MẮT!",
      notificationBody: "Bạn đang ở quá gần màn hình (< 30cm). Hãy đưa điện thoại ra xa!",
    );
  }

  void _hideOverlay() async {
    if (!_isOverlayShowing) return;
    _isOverlayShowing = false;
    await SystemAlertWindow.closeSystemWindow(prefMode: SystemWindowPrefMode.OVERLAY);
  }

  void _stopService() async {
    await _cameraController?.stopImageStream();
    await _cameraController?.dispose();
    await _faceDetector?.close();
    _hideOverlay();
    if (mounted) {
      setState(() {
        _isServiceRunning = false;
        _statusText = "Đã dừng dịch vụ";
        _calculatedDistanceCm = 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Safety Screen - Bảo Vệ Mắt"),
        backgroundColor: const Color(0xFF1B6B93),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isServiceRunning ? Icons.shield : Icons.shield_outlined,
              size: 100,
              color: _isServiceRunning ? const Color(0xFF1B6B93) : Colors.grey,
            ),
            const SizedBox(height: 24),
            Text(
              _statusText,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Text(
              "Khoảng cách: ${_calculatedDistanceCm.toStringAsFixed(1)} cm",
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: _calculatedDistanceCm <= 30 && _calculatedDistanceCm > 0 ? Colors.red : Colors.green,
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isServiceRunning ? Colors.redAccent : const Color(0xFF1B6B93),
                ),
                onPressed: () {
                  if (_isServiceRunning) {
                    _stopService();
                  } else {
                    _startGuardService();
                  }
                },
                child: Text(
                  _isServiceRunning ? "TẮT BẢO VỆ" : "BẬT BẢO VỆ CHẠY NGẦM",
                  style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
