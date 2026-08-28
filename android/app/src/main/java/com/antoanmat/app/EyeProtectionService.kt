package com.antoanmat.app

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import androidx.annotation.OptIn
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions

class EyeProtectionService : LifecycleService() {

    private lateinit var windowManager: WindowManager
    private var overlayView: View? = null
    private var isOverlayShown = false
    private val mainHandler = Handler(Looper.getMainLooper())

    private val faceDetector by lazy {
        val options = FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .build()
        FaceDetection.getClient(options)
    }

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        startForegroundServiceNotification()
        startCamera()
    }

    private fun startForegroundServiceNotification() {
        val channelId = "antoanmat_service"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId, "Bảo Vệ Mắt Service",
                NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("Antoanmat đang hoạt động")
            .setContentText("Đang giám sát khoảng cách mắt...")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .build()

        startForeground(1001, notification)
    }

    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener({
            val cameraProvider = cameraProviderFuture.get()
            val cameraSelector = CameraSelector.DEFAULT_FRONT_CAMERA

            val imageAnalysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()

            imageAnalysis.setAnalyzer(ContextCompat.getMainExecutor(this)) { imageProxy ->
                processImageProxy(imageProxy)
            }

            try {
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(this, cameraSelector, imageAnalysis)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }, ContextCompat.getMainExecutor(this))
    }

    @OptIn(ExperimentalGetImage::class)
    private fun processImageProxy(imageProxy: ImageProxy) {
        val mediaImage = imageProxy.image
        if (mediaImage != null) {
            val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
            faceDetector.process(image)
                .addOnSuccessListener { faces ->
                    if (faces.isNotEmpty()) {
                        val face = faces[0]
                        val faceWidthPx = face.boundingBox.width().toDouble()
                        val imageWidth = if (imageProxy.imageInfo.rotationDegrees == 90 || 
                            imageProxy.imageInfo.rotationDegrees == 270) imageProxy.height else imageProxy.width

                        // Công thức vật lý đo khoảng cách thực tế (cm)
                        val focalLengthPx = imageWidth * 0.85
                        val realFaceWidthCm = 14.0
                        val distanceCm = (realFaceWidthCm * focalLengthPx) / faceWidthPx

                        // YÊU CẦU 2 & 3: Tự động che màn hình khi < 30cm và tự mở khi >= 30cm
                        if (distanceCm < 30.0) {
                            showOverlay()
                        } else {
                            hideOverlay()
                        }
                    }
                    imageProxy.close()
                }
                .addOnFailureListener {
                    imageProxy.close()
                }
        } else {
            imageProxy.close()
        }
    }

    private fun showOverlay() {
        if (isOverlayShown) return
        mainHandler.post {
            if (overlayView == null) {
                val inflater = getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
                overlayView = inflater.inflate(R.layout.overlay_lock, null)
            }

            val layoutParamsType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }

            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                layoutParamsType,
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            )

            try {
                windowManager.addView(overlayView, params)
                isOverlayShown = true
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun hideOverlay() {
        if (!isOverlayShown) return
        mainHandler.post {
            try {
                if (overlayView != null && overlayView?.parent != null) {
                    windowManager.removeView(overlayView)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                isOverlayShown = false
            }
        }
    }

    override fun onDestroy() {
        hideOverlay()
        super.onDestroy()
    }
}
