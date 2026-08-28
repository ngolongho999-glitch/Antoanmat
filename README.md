# An toàn mắt – Android Samsung

Ứng dụng mẫu dùng camera trước + ML Kit Face Detection để ước lượng tương đối khoảng cách mắt/mặt với màn hình.

## Quan trọng về độ chính xác
Android/Camera không thể tự biết chính xác khoảng cách thật chỉ từ một bounding box khuôn mặt nếu không có hiệu chuẩn hoặc dữ liệu camera/depth. Bản mẫu dùng hiệu chuẩn 40 cm và quan hệ nghịch đảo giữa kích thước khuôn mặt trên ảnh và khoảng cách.

Khuyến nghị bản production:
1. Thêm màn hình hiệu chuẩn 40 cm/35 cm.
2. Dùng khoảng cách hai mắt (landmark) thay vì toàn bộ khuôn mặt.
3. Lưu calibration riêng cho từng người/trẻ.
4. Thêm hysteresis để tránh bật/tắt liên tục.
5. Hiển thị hình hoạt hình thay vì nền đen.
6. Thêm màn hình quản trị có PIN.

## Quyền cần cấp trên Samsung
- Camera
- Hiển thị trên ứng dụng khác
- Thông báo (Android 13+)

## Giới hạn "chống tắt lén"
Ứng dụng Android thông thường không thể ngăn tuyệt đối chủ thiết bị vào Settings > Force stop hoặc gỡ ứng dụng. PIN chỉ khóa thao tác tắt trong app. Nếu cần quản lý thiết bị trẻ em ở mức hệ thống, nên triển khai Device Owner/Android Enterprise và chính sách quản trị thiết bị phù hợp.

## Build bằng Codemagic
Push toàn bộ thư mục lên GitHub rồi tạo app Android trên Codemagic.
Dùng Android workflow và build:
./gradlew assembleDebug
hoặc bản phát hành:
./gradlew bundleRelease

Có thể thêm `codemagic.yaml` sau khi repository đã được kết nối.
