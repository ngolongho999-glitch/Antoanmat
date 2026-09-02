package com.example.screendistance

import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions

class FaceDistanceAnalyzer(
    private val onDistanceCheck: (isTooClose: Boolean) -> Unit
) : ImageAnalysis.Analyzer {

    private var lastAnalyzedTime = 0L
    private val intervalMs = 1500L // Tối ưu Pin: Phân tích 1 frame mỗi 1.5 giây

    private val options = FaceDetectorOptions.Builder()
        .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
        .build()

    private val detector = FaceDetection.getClient(options)

    @ExperimentalGetImage
    override fun analyze(imageProxy: ImageProxy) {
        val currentTime = System.currentTimeMillis()
        
        // Bỏ qua khung hình nếu chưa đủ khoảng thời gian intervalMs
        if (currentTime - lastAnalyzedTime < intervalMs) {
            imageProxy.close()
            return
        }

        val mediaImage = imageProxy.image
        if (mediaImage != null) {
            val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)

            detector.process(image)
                .addOnSuccessListener { faces ->
                    if (faces.isNotEmpty()) {
                        val face = faces[0]

                        // Xử lý góc xoay khung hình (nếu camera bị xoay 90/270 độ)
                        val isRotated = imageProxy.imageInfo.rotationDegrees == 90 || imageProxy.imageInfo.rotationDegrees == 270
                        val frameWidth = if (isRotated) imageProxy.height else imageProxy.width

                        // Tính tỷ lệ % chiều rộng mặt so với khung hình camera
                        val faceWidthRatio = face.boundingBox.width().toFloat() / frameWidth.toFloat()

                        // Ngưỡng an toàn: Mặt chiếm trên 42% chiều rộng khung hình -> Khoảng cách < 30cm
                        val isTooClose = faceWidthRatio > 0.42f
                        onDistanceCheck(isTooClose)
                    } else {
                        onDistanceCheck(false)
                    }
                    lastAnalyzedTime = currentTime
                }
                .addOnFailureListener {
                    onDistanceCheck(false)
                }
                .addOnCompleteListener {
                    imageProxy.close() // Giải phóng frame bắt buộc
                }
        } else {
            imageProxy.close()
        }
    }
}
