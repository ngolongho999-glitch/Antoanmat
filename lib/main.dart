import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MaterialApp(home: EyeProtectionApp()));
}

class EyeProtectionApp extends StatefulWidget {
  const EyeProtectionApp({Key? key}) : super(key: key);
  @override
  State<EyeProtectionApp> createState() => _EyeProtectionAppState();
}

class _EyeProtectionAppState extends State<EyeProtectionApp> {
  CameraController? _cameraController;
  late FaceDetector _faceDetector;
  bool _isDetecting = false;
  bool _isTooClose = false;
  String? _savedPin;
  final TextEditingController _pinController = TextEditingController();

  // Ngưỡng phát hiện khoảng cách gần (tỷ lệ độ rộng khuôn mặt / độ rộng khung hình)
  final double _closeThreshold = 0.55; 

  @override
  void initState() {
    super.initState();
    _loadPin();
    _initCamera();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
    );
  }

  Future<void> _loadPin() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _savedPin = prefs.getString('user_pin'));
  }

  Future<void> _savePin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_pin', pin);
    setState(() => _savedPin = pin);
  }

  void _initCamera() async {
    // Lấy camera front (camera selfie)
    final frontCamera = cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.front,
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.low,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    _cameraController!.startImageStream((CameraImage image) {
      if (_isDetecting) return;
      _isDetecting = true;
      _processCameraImage(image);
    });
  }

  void _processCameraImage(CameraImage image) async {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final InputImage inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation270deg,
        format: InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );

    final faces = await _faceDetector.processImage(inputImage);

    if (faces.isNotEmpty) {
      final face = faces.first;
      // Tính tỷ lệ chiều rộng khuôn mặt so với chiều rộng khung hình
      double faceRatio = face.boundingBox.width / image.width;

      if (faceRatio > _closeThreshold && !_isTooClose) {
        setState(() => _isTooClose = true);
      } else if (faceRatio <= _closeThreshold && _isTooClose) {
        setState(() => _isTooClose = false);
      }
    }
    _isDetecting = false;
  }

  void _showUnlockDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Nhập mật khẩu để tắt ứng dụng'),
        content: TextField(
          controller: _pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Mật khẩu 4 số'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (_pinController.text == _savedPin) {
                Navigator.pop(context);
                _cameraController?.stopImageStream();
                setState(() => _isTooClose = false);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sai mật khẩu!')),
                );
              }
            },
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext meContext) {
    if (_savedPin == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Thiết lập mật khẩu ban đầu')),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Tạo mã PIN quản trị'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _savePin(_pinController.text),
                child: const Text('Lưu mật khẩu'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(title: const Text('Antoanmat - Đang hoạt động')),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Ứng dụng đang giám sát khoảng cách mắt.'),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _showUnlockDialog,
                  child: const Text('Dừng dịch vụ (Yêu cầu PIN)'),
                ),
              ],
            ),
          ),
        ),
        // Màn hình mờ / hình ảnh hoạt hình che lại khi đưa gần
        if (_isTooClose)
          Positioned.fill(
            child: Container(
              color: Colors.redAccent,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/cartoon.png', height: 250, errorBuilder: (_, __, ___) => 
                    const Icon(Icons.warning_amber_rounded, size: 150, color: Colors.white)),
                  const SizedBox(height: 20),
                  const Text(
                    'BẠN ĐANG ĐỂ ĐIỆN THOẠI QUÁ GẦN!\nHãy đưa ra xa để tiếp tục.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }
}
