import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'distance_monitor_page.dart'; // File đo khoảng cách chúng ta đã tạo trước đó

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ứng dụng Bảo vệ Mắt',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isServiceRunning = false;

  @override
  void initState() {
    super.initState();
    _checkPasswordSetup();
  }

  // Kiểm tra xem đã có mật khẩu bảo vệ chưa, nếu chưa thì yêu cầu cài đặt lần đầu
  void _checkPasswordSetup() async {
    final prefs = await SharedPreferences.getInstance();
    String? pin = prefs.getString('app_pin');
    if (pin == null) {
      // Nếu chưa có PIN, hiển thị popup tạo mật khẩu lần đầu
      _showSetupPinDialog();
    }
  }

  void _showSetupPinDialog() {
    final TextEditingController pinController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Thiết lập mật khẩu bảo vệ"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Nhập mã PIN gồm 4 chữ số để ngăn trẻ nhỏ tự ý tắt ứng dụng hoặc thay đổi cài đặt:"),
            const SizedBox(height: 12),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              decoration: const InputDecoration(labelText: 'Mã PIN'),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              if (pinController.text.length == 4) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('app_pin', pinController.text);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Đã lưu mật khẩu thành công!")),
                );
              }
            },
            child: const Text("Lưu mật khẩu"),
          ),
        ],
      ),
    );
  }

  // Hiển thị bảng yêu cầu nhập PIN trước khi muốn tắt ứng dụng hoặc vào cài đặt
  void _showPinVerificationDialog(VoidCallback onSuccess) {
    final TextEditingController pinController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Xác thực bảo mật"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Nhập mã PIN để tiếp tục:"),
            const SizedBox(height: 12),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              decoration: const InputDecoration(labelText: 'Mã PIN'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Hủy")),
          ElevatedButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              String? savedPin = prefs.getString('app_pin');
              if (pinController.text == savedPin) {
                Navigator.pop(context);
                onSuccess();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Sai mã PIN!"), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text("Xác nhận"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bảo Vệ Mắt Cho Bé'),
        actions: [
          // Nút cài đặt (Yêu cầu mật khẩu mới cho phép đổi cấu hình)
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              _showPinVerificationDialog(() {
                // Hành động khi nhập đúng PIN để vào cài đặt
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Đã mở cài đặt bảo mật")),
                );
              });
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isServiceRunning ? Icons.security : Icons.warning_amber_rounded,
              size: 80,
              color: _isServiceRunning ? Colors.green : Colors.orange,
            ),
            const SizedBox(height: 24),
            Text(
              _isServiceRunning
                  ? "Trạng thái: Đang bảo vệ mắt hoạt động"
                  : "Trạng thái: Đang tắt",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              "Ứng dụng dùng camera trước để nhận diện khoảng cách. Khi bé cầm máy quá gần, màn hình sẽ tự động hiển thị lớp phủ cảnh báo.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                backgroundColor: _isServiceRunning ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (_isServiceRunning) {
                  // Muốn tắt ứng dụng bắt buộc phải nhập PIN chống trẻ nhỏ lén tắt
                  _showPinVerificationDialog(() {
                    setState(() {
                      _isServiceRunning = false;
                    });
                  });
                } else {
                  setState(() {
                    _isServiceRunning = true;
                    // Chuyển hướng sang màn hình đo khoảng cách camera
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const DistanceMonitorPage()),
                    );
                  });
                }
              },
              icon: Icon(_isServiceRunning ? Icons.stop : Icons.play_arrow),
              label: Text(
                _isServiceRunning ? "TẮT BẢO VỆ (Cần PIN)" : "BẮT ĐẦU BẢO VỆ",
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
