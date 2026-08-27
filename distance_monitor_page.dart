import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class DistanceMonitorPage extends StatefulWidget {
  const DistanceMonitorPage({super.key});

  @override
  State<DistanceMonitorPage> createState() => _DistanceMonitorPageState();
}

class _DistanceMonitorPageState extends State<DistanceMonitorPage> {
  CameraController? _cameraController;
  bool _isTooClose = false;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
  );

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  void _initializeCamera() async {
    final cameras = await availableCameras();
    // Chọn camera trước (front camera)
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(frontCamera, ResolutionPreset.low, enableAudio: false);
    await _cameraController?.initialize();
    
    // Bắt đầu stream khung hình từ camera để đo khoảng cách khuôn mặt
    _cameraController?.startImageStream((CameraImage image) {
      // Xử lý logic ML Kit Face Detection tại đây để tính kích thước mặt
      // Nếu diện tích khuôn mặt lớn hơn ngưỡng quy định -> setState(() { _isTooClose = true; })
      // Ngược lại -> setState(() { _isTooClose = false; });
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Giao diện chính của ứng dụng (hoặc ẩn camera đi nếu chạy ngầm)
          Center(
            child: Text("Ứng dụng đang bảo vệ mắt cho bé..."),
          ),

          // Lớp phủ màn hình (Overlay) khi trẻ cầm quá gần
          if (_isTooClose)
            Container(
              color: Colors.yellow[700],
              child: const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                child: Text(
                    "🛡️ Bé đang để máy quá gần rồi!\nHãy lùi ra xa nhé!",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
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
    super.dispose();
  }
}
