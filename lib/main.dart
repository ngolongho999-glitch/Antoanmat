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
    debugPrint("Lỗi khởi tạo camera: $e");
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
  String _statusText = "Sẵn sàng khởi chạy ngầm";
  DateTime _lastProcessedTime = DateTime.now();

  final List<double> _distanceHistory = [];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // 1. Xin quyền Camera
    await Permission.camera.request();
    // 2. Xin quyền Hiển thị trên ứng dụng khác (Draw over other apps)
    await SystemAlertWindow.requestPermissions();
  }

  Future<void> _startGuardService() async {
    final camStatus = await Permission.camera.status;
    if (!camStatus.isGranted) {
      await Permission.camera.request();
    }

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
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
      ResolutionPreset.medium,
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
      if (mounted) {
        setState(() => _statusText = "Lỗi khởi tạo: $e");
      }
    }
  }

  void _processCameraImage(CameraImage image) async {
    final now = DateTime.now();
    if (_isProcessing || now.difference(_lastProcessedTime).inMilliseconds < 150) {
      return;
    }

    if (_faceDetector == null || _cameraController == null) return;
    _isProcessing = true;
    _lastProcessedTime = now;

    try {
      final BytesBuilder bytesBuilder = BytesBuilder();
      for (final Plane plane in image.planes) {
        bytesBuilder.add(plane.bytes);
      }
      final Uint8List bytes = bytesBuilder.toBytes();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final camera = _cameraController!.description;
      
      final imageRotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation270deg;
      final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: imageRotation,
          format: inputImageFormat,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final faces = await _faceDetector!.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
        final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;

        if (leftEye != null && rightEye != null) {
          double dx = (leftEye.x - rightEye.x).toDouble();
          double dy = (leftEye.y - rightEye.y).toDouble();
          double pixelDistance = sqrt(dx * dx + dy * dy);

          if (pixelDistance > 0) {
            double focalLength = image.width * 0.8;
            double averageInterpupillaryDistance = 6.3;
            double rawDistance = (focalLength * averageInterpupillaryDistance) / pixelDistance;

            _distanceHistory.add(rawDistance);
            if (_distanceHistory.length > 4) {
              _distanceHistory.removeAt(0);
            }
            double smoothedDistance = _distanceHistory.reduce((a, b) => a + b) / _distanceHistory.length;

            if (mounted) {
              setState(() {
                _calculatedDistanceCm = smoothedDistance;
              });
            }

            // XỬ LÝ CHẠY NGẦM VÀ PHỦ ĐEN MÀN HÌNH KHI DÙNG ỨNG DỤNG KHÁC
            if (smoothedDistance <= 30.0) {
              _showBlackOverlay();
            } else {
              _hideBlackOverlay();
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Lỗi nhận diện: $e");
    } finally {
      _isProcessing = false;
    }
  }

  void _showBlackOverlay() async {
    if (_isOverlayShowing) return;
    _isOverlayShowing = true;

    SystemWindowHeader header = SystemWindowHeader(
      title: SystemWindowText(
        text: "ĐÃ TẮT MÀN HÌNH!",
        fontSize: 20,
        textColor: Colors.white,
        fontWeight: FontWeight.BOLD,
      ),
      subTitle: SystemWindowText(
        text: "Khoảng cách quá gần (< 30cm). Đưa điện thoại ra xa để mở lại.",
        fontSize: 14,
        textColor: Colors.redAccent,
      ),
      backgroundColor: Colors.black,
    );

    await SystemAlertWindow.showSystemWindow(
      height: 2000,
      header: header,
      margin: SystemWindowMargin(left: 0, right: 0, top: 0, bottom: 0),
      gravity: SystemWindowGravity.TOP,
      prefMode: SystemWindowPrefMode.OVERLAY,
    );
  }

  void _hideBlackOverlay() async {
    if (!_isOverlayShowing) return;
    _isOverlayShowing = false;
    await SystemAlertWindow.closeSystemWindow(prefMode: SystemWindowPrefMode.OVERLAY);
  }

  void _stopService() async {
    await _cameraController?.stopImageStream();
    await _cameraController?.dispose();
    await _faceDetector?.close();
    _hideBlackOverlay();
    setState(() {
      _isServiceRunning = false;
      _statusText = "Đã dừng dịch vụ";
    });
  }

  @override
  void dispose() {
    _stopService();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Bảo Vệ Mắt Chạy Ngầm"),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isServiceRunning ? Icons.security : Icons.security_outlined,
              size: 90,
              color: _isServiceRunning ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 20),
            Text(
              _statusText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 10),
            Text(
              "Khoảng cách hiện tại: ${_calculatedDistanceCm.toStringAsFixed(1)} cm",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _calculatedDistanceCm <= 30 && _calculatedDistanceCm > 0 ? Colors.red : Colors.green,
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isServiceRunning ? Colors.red : Colors.green,
                ),
                onPressed: () {
                  if (_isServiceRunning) {
                    _stopService();
                  } else {
                    _startGuardService();
                  }
                },
                child: Text(
                  _isServiceRunning ? "DỪNG BẢO VỆ" : "BẬT CHẾ ĐỘ CHẠY NGẦM",
                  style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Lưu ý: Sau khi bấm BẬT, bạn có thể thoát ra màn hình chính, mở Facebook, YouTube hay chơi game. Nếu đưa mắt gần hơn 30cm, màn hình phủ đen cảnh báo sẽ ngay lập tức hiện đè lên mọi ứng dụng.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
