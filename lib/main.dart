import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("Loi lay danh sach camera: $e");
  }
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: EyeProtectionApp(),
  ));
}

class EyeProtectionApp extends StatefulWidget {
  const EyeProtectionApp({Key? key}) : super(key: key);
  @override
  State<EyeProtectionApp> createState() => _EyeProtectionAppState();
}

class _EyeProtectionAppState extends State<EyeProtectionApp> {
  CameraController? _cameraController;
  late FaceDetector _faceDetector;
  bool _isProcessing = false;
  
  double _currentDistanceCm = 0.0;
  bool _isTooClose = false;
  bool _isProtectionActive = true;
  bool _permissionGranted = false;
  
  String? _savedPin;
  final TextEditingController _pinController = TextEditingController();

  final double _safeDistanceCm = 30.0; // Khoảng cách an toàn (cm)
  final double _focalLengthPx = 480.0;  // Tiêu cự camera selfie chuẩn
  final double _realFaceWidthCm = 14.0; // Chiều rộng khuôn mặt trung bình (cm)

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await _requestPermissions();
    await _checkAndSetupPin();
    _initFaceDetector();
    if (_permissionGranted) {
      _initCamera();
    }
  }

  Future<void> _requestPermissions() async {
    final status = await Permission.camera.request();
    setState(() {
      _permissionGranted = status.isGranted;
    });
  }

  void _initFaceDetector() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableTracking: false,
      ),
    );
  }

  Future<void> _checkAndSetupPin() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedPin = prefs.getString('user_pin');
    });
  }

  Future<void> _savePin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_pin', pin);
    setState(() {
      _savedPin = pin;
    });
  }

  void _initCamera() async {
    if (cameras.isEmpty) return;

    final frontCamera = cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    try {
      await _cameraController!.initialize();
      _cameraController!.startImageStream((CameraImage image) {
        if (_isProcessing || !_isProtectionActive) return;
        _isProcessing = true;
        _detectFaceDistance(image, frontCamera);
      });
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Loi khoi tao Camera: $e");
    }
  }

  void _detectFaceDistance(CameraImage image, CameraDescription camera) async {
    try {
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
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        double faceWidthPx = face.boundingBox.width;

        // Công thức tính khoảng cách thực tế từ khuôn mặt tới camera (cm)
        double calculatedCm = (_realFaceWidthCm * _focalLengthPx) / faceWidthPx;
        
        if (mounted) {
          setState(() {
            _currentDistanceCm = double.parse(calculatedCm.toStringAsFixed(1));
            // Yêu cầu 2 & 3: Tự động khóa khi < 30cm và tự mở lại khi >= 30cm
            _isTooClose = _currentDistanceCm < _safeDistanceCm;
          });
        }
      }
    } catch (e) {
      debugPrint("Loi xu ly Face Detection: $e");
    } finally {
      _isProcessing = false;
    }
  }

  // Yêu cầu 4: Chống tắt lén bằng mã PIN
  void _showUnlockDialog() {
    _pinController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận mật khẩu phụ huynh'),
        content: TextField(
          controller: _pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(
            hintText: 'Nhập mã PIN 4 số',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_pinController.text == _savedPin) {
                setState(() {
                  _isProtectionActive = false;
                  _isTooClose = false;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã tạm dừng bảo vệ.')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sai mật khẩu! Không thể tắt.')),
                );
              }
            },
            child: const Text('Mở khóa'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Màn hình khởi tạo PIN nếu chưa thiết lập
    if (_savedPin == null) {
      return Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield, size: 80, color: Colors.blue),
              const SizedBox(height: 20),
              const Text(
                'Thiết lập mật khẩu chống tắt lén',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Mật khẩu này ngăn không cho trẻ tự ý tắt ứng dụng bảo vệ mắt.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Tạo mã PIN 4 số',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (_pinController.text.length == 4) {
                    _savePin(_pinController.text);
                  }
                },
                child: const Text('Lưu mật khẩu & Bắt đầu'),
              )
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: false, // Ngăn bấm nút Back để thoát ứng dụng
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              title: const Text('Antoanmat - Bảo Vệ Mắt'),
              automaticallyImplyLeading: false,
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.remove_red_eye,
                    size: 90,
                    color: _isProtectionActive ? Colors.blue : Colors.grey,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Ứng dụng đang theo dõi khoảng cách mắt',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Khoảng cách hiện tại: ${_currentDistanceCm} cm',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: _currentDistanceCm < _safeDistanceCm ? Colors.red : Colors.green,
                    ),
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      backgroundColor: _isProtectionActive ? Colors.redAccent : Colors.green,
                    ),
                    onPressed: () {
                      if (_isProtectionActive) {
                        _showUnlockDialog();
                      } else {
                        setState(() {
                          _isProtectionActive = true;
                        });
                      }
                    },
                    icon: Icon(_isProtectionActive ? Icons.lock : Icons.lock_open),
                    label: Text(
                      _isProtectionActive ? 'Tắt bảo vệ (Cần PIN)' : 'Bật lại bảo vệ',
                      style: const TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Màn hình che hoạt hình ngộ nghĩnh phủ kín khi đưa mắt quá gần (<30cm)
          if (_isTooClose && _isProtectionActive)
            Positioned.fill(
              child: Container(
                color: Colors.orangeAccent,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.face_retouching_warning, size: 150, color: Colors.white),
                    const SizedBox(height: 20),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24.0),
                      child: Text(
                        'Ú Ớ! ĐƯA ĐIỆN THOẠI RA XA NÀO!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Hãy giữ khoảng cách trên ${_safeDistanceCm.toInt()} cm\n(Hiện tại: ${_currentDistanceCm} cm)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    _pinController.dispose();
    super.dispose();
  }
}
