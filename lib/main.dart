import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_alert_window/system_alert_window.dart';
import 'package:permission_handler/permission_handler.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
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
  
  String? _savedPin;
  final TextEditingController _pinController = TextEditingController();

  final double _safeDistanceCm = 30.0; 
  final double _focalLengthPx = 450.0; 
  final double _realFaceWidthCm = 14.0; 

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _checkAndSetupPin();
    _initFaceDetector();
    _initCamera();
    SystemAlertWindow.registerOnClickListener(overlayCallBack);
  }

  Future<void> _requestPermissions() async {
    await Permission.camera.request();
    await Permission.systemAlertWindow.request();
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
        _detectFaceDistance(image);
      });
    } catch (e) {
      debugPrint("Lỗi camera: $e");
    }
  }

  void _detectFaceDistance(CameraImage image) async {
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
        double calculatedCm = (_realFaceWidthCm * _focalLengthPx) / faceWidthPx;
        
        bool currentlyTooClose = calculatedCm < _safeDistanceCm;

        setState(() {
          _currentDistanceCm = double.parse(calculatedCm.toStringAsFixed(1));
        });

        // XỬ LÝ YÊU CẦU 2 & 3: Hiển thị/Ẩn màn hình che toàn hệ thống
        if (currentlyTooClose && !_isTooClose) {
          _isTooClose = true;
          _showSystemOverlay();
        } else if (!currentlyTooClose && _isTooClose) {
          _isTooClose = false;
          _hideSystemOverlay();
        }
      }
    } catch (e) {
      debugPrint("Lỗi xử lý hình ảnh: $e");
    } finally {
      _isProcessing = false;
    }
  }

  // Bật cửa sổ che nổi đè lên YouTube/Game/Màn hình chính
  void _showSystemOverlay() {
    SystemWindowHeader header = SystemWindowHeader(
      title: SystemWindowText(text: "BẢO VỆ MẮT ANTOANMAT", fontSize: 16, textColor: Colors.white),
      backgroundColor: Colors.redAccent,
    );

    SystemWindowBody body = SystemWindowBody(
      rows: [
        EachRow(
          columns: [
            EachColumn(
              text: SystemWindowText(
                text: "Ú Ớ! BẠN ĐANG XEM QUÁ GẦN!\n\nHãy đưa điện thoại ra xa trên 30cm để tiếp tục sử dụng.",
                fontSize: 18,
                textColor: Colors.black87,
              ),
            ),
          ],
        ),
      ],
      padding: SystemWindowPadding(left: 16, right: 16, bottom: 16, top: 16),
    );

    SystemAlertWindow.showSystemWindow(
      height: 400,
      header: header,
      body: body,
      margin: SystemWindowMargin(left: 20, right: 20, top: 100, bottom: 0),
      gravity: SystemWindowGravity.CENTER,
      prefMode: SystemWindowPrefMode.OVERLAY,
    );
  }

  void _hideSystemOverlay() {
    SystemAlertWindow.closeSystemWindow();
  }

  // XỬ LÝ YÊU CẦU 4: Chống tắt lén bằng mã PIN
  void _showUnlockDialog() {
    _pinController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận mật khẩu quản trị'),
        content: TextField(
          controller: _pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
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
                _hideSystemOverlay();
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sai mật khẩu! Không thể dừng.')),
                );
              }
            },
            child: const Text('Xác nhận tắt'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              const SizedBox(height: 20),
              TextField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Tạo mã PIN quản trị (4 số)',
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
                child: const Text('Kích hoạt bảo vệ'),
              )
            ],
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Antoanmat'),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.visibility,
                size: 80,
                color: _isProtectionActive ? Colors.green : Colors.grey,
              ),
              const SizedBox(height: 20),
              Text(
                'Khoảng cách: ${_currentDistanceCm} cm',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: _currentDistanceCm < _safeDistanceCm ? Colors.red : Colors.green,
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isProtectionActive ? Colors.red : Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () {
                  if (_isProtectionActive) {
                    _showUnlockDialog();
                  } else {
                    setState(() => _isProtectionActive = true);
                  }
                },
                icon: Icon(_isProtectionActive ? Icons.lock : Icons.lock_open),
                label: Text(
                  _isProtectionActive ? 'Tắt dịch vụ (Cần PIN)' : 'Bật lại dịch vụ',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
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

void overlayCallBack(String tag) {
  debugPrint("Overlay Callback: $tag");
}
