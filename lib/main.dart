import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

List<CameraDescription> _cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
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
  late FaceDetector _faceDetector;
  bool _isBusy = false;
  bool _screenOff = false;
  double _calculatedDistanceCm = 0.0;

  @override
  void initState() {
    super.initState();
    _initDetectorAndCamera();
  }

  Future<void> _initDetectorAndCamera() async {
    await Permission.camera.request();

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        performanceMode: FaceDetectorMode.fast,
      ),
    );

    // Chọn Camera trước (Front Camera)
    final frontCamera = _cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.front,
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.low,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    _cameraController!.startImageStream(_processCameraImage);
    if (mounted) setState(() {});
  }

  void _processCameraImage(CameraImage image) async {
    if (_isBusy) return;
    _isBusy = true;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final InputImageRotation imageRotation = InputImageRotation.rotation270deg;
      final InputImageFormat inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: imageRotation,
          format: inputImageFormat,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
        final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;

        if (leftEye != null && rightEye != null) {
          // Tính khoảng cách pixel giữa 2 mắt trên ảnh
          double pixelDistance = sqrt(
            pow(leftEye.x - rightEye.x, 2) + pow(leftEye.y - rightEye.y, 2),
          );

          // Công thức ước tính khoảng cách thực tế (D = (f * W) / P)
          // f: Tiêu cự giả định (~500), W: Khoảng cách giữa 2 mắt trung bình (6.3 cm)
          double estimatedDistance = (500 * 6.3) / pixelDistance;

          setState(() {
            _calculatedDistanceCm = estimatedDistance;
            // Tắt màn hình khi xa hơn 30cm, Bật khi <= 30cm
            _screenOff = estimatedDistance > 30.0;
          });
        }
      }
    } catch (e) {
      debugPrint("Lỗi xử lý ảnh: $e");
    } finally {
      _isBusy = false;
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Giao diện chính của ứng dụng
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.remove_red_eye, size: 80, color: Colors.blue),
                const SizedBox(height: 20),
                const Text(
                  "Ứng dụng đang theo dõi khoảng cách mắt",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  "Khoảng cách hiện tại: ${_calculatedDistanceCm.toStringAsFixed(1)} cm",
                  style: TextStyle(
                    fontSize: 22,
                    color: _calculatedDistanceCm > 30 ? Colors.red : Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Lớp màn hình đen giả lập TẮT màn hình khi khoảng cách > 30cm
          if (_screenOff)
            Container(
              color: Colors.black,
              width: double.infinity,
              height: double.infinity,
              child: const Center(
                child: Text(
                  "Đã tắt màn hình\n(Khoảng cách mắt > 30cm)",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 16),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
