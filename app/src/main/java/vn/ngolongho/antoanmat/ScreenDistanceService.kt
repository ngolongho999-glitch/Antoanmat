package com.example.screendistance

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class ScreenDistanceService : LifecycleService() {

    private lateinit var cameraExecutor: ExecutorService
    private lateinit var windowManager: WindowManager
    private var overlayView: View? = null
    private var isOverlayVisible = false

    override fun onCreate() {
        super.onCreate()
        cameraExecutor = Executors.newSingleThreadExecutor()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        initOverlayView()
        startForegroundServiceWithNotification()
        startCameraAnalysis()
    }

    private fun startForegroundServiceWithNotification() {
        val channelId = "screen_distance_channel"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Bảo Vệ Mắt",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }

        val notification: Notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("Bảo vệ mắt đang hoạt động")
            .setContentText("Đang tự động đo khoảng cách màn hình...")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setOngoing(true)
            .build()

        startForeground(1001, notification)
    }

    private fun initOverlayView() {
        val inflater = getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
        overlayView = inflater.inflate(R.layout.overlay_warning, null)
    }

    private fun startCameraAnalysis() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener({
            val cameraProvider = cameraProviderFuture.get()

            val imageAnalyzer = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
                .also {
                    it.setAnalyzer(cameraExecutor, FaceDistanceAnalyzer { isTooClose ->
                        Handler(Looper.getMainLooper()).post {
                            updateOverlayState(isTooClose)
                        }
                    })
                }

            val cameraSelector = CameraSelector.DEFAULT_FRONT_CAMERA

            try {
                cameraProvider.unbindAll()
                // Gắn CameraX vào vòng đời của Service
                cameraProvider.bindToLifecycle(this, cameraSelector, imageAnalyzer)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun updateOverlayState(isTooClose: Boolean) {
        if (isTooClose && !isOverlayVisible) {
            showOverlay()
        } else if (!isTooClose && isOverlayVisible) {
            hideOverlay()
        }
    }

    private fun showOverlay() {
        if (overlayView == null || isOverlayVisible) return
        
        val layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
        }

        try {
            windowManager.addView(overlayView, layoutParams)
            isOverlayVisible = true
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun hideOverlay() {
        if (overlayView != null && isOverlayVisible) {
            try {
                windowManager.removeView(overlayView)
                isOverlayVisible = false
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        hideOverlay()
        cameraExecutor.shutdown()
    }
}
