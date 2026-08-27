import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

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
  bool _screenOff = false;
  double _calculatedDistanceCm = 0.0;
  String _statusText = "Đang khởi tạo...";
  DateTime _lastProcessedTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initDetectorAndCamera();
  }

  Future<void> _initDetectorAndCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) setState(() => _statusText = "Cần cấp quyền Camera!");
      return;
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
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    try {
      await _cameraController!.initialize();
      await _cameraController!.startImageStream(_processCameraImage);
      if (mounted) {
        setState(() => _statusText = "Đang quét khuôn mặt...");
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusText = "Lỗi khởi tạo camera: $e");
      }
    }
  }

  void _processCameraImage(CameraImage image) async {
    final now = DateTime.now();
    if (_isProcessing || now.difference(_lastProcessedTime).inMilliseconds < 300) {
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
            double estimatedDistance = (450 * 6.3) / pixelDistance;

            if (mounted) {
              setState(() {
                _calculatedDistanceCm = estimatedDistance;
                _statusText = "Đã phát hiện khuôn mặt";
                // LOGIC MỚI: Tắt màn hình khi QUÁ GẦN (<= 30 cm), Mở lại khi XA ( > 30 cm)
                _screenOff = estimatedDistance <= 30.0;
              });
            }
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _statusText = "Chưa nhận diện được mắt";
          });
        }
      }
    } catch (e) {
      debugPrint("Lỗi nhận diện: $e");
    } finally {
      _isProcessing = false;
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    color: Colors.black,
                    child: _cameraController != null && _cameraController!.value.isInitialized
                        ? CameraPreview(_cameraController!)
                        : const Center(
                            child: CircularProgressIndicator(color: Colors.blue),
                          ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  color: Colors.white,
                  width: double.infinity,
                  child: Column(
                    children: [
                      Text(
                        _statusText,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Khoảng cách: ${_calculatedDistanceCm.toStringAsFixed(1)} cm",
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: _calculatedDistanceCm <= 30 ? Colors.red : Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // TẮT MÀN HÌNH KHI KHOẢNG CÁCH MẮT LE 30 CM
            if (_screenOff)
              Positioned.fill(
                child: Container(
                  color: Colors.black,
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 80, color: Colors.redAccent),
                        SizedBox(height: 16),
                        Text(
                          "ĐÃ TẮT MÀN HÌNH!\n\nKhoảng cách quá gần (< 30cm)\nVui lòng đưa điện thoại ra xa để mở lại.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
