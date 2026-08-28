package vn.ngolongho.antoanmat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import java.util.concurrent.Executors
import kotlin.math.max

class EyeGuardService : LifecycleService() {

    private val executor =
        Executors.newSingleThreadExecutor()

    private var shieldView: View? = null

    private var windowManager:
        WindowManager? = null

    private var referenceFaceWidth =
        0f

    private var closeStartTime =
        0L

    override fun onCreate() {

        super.onCreate()

        createNotificationChannel()

        startForeground(
            10,
            createNotification()
        )

        startFrontCamera()
    }

    private fun createNotificationChannel() {

        val manager =
            getSystemService(
                NotificationManager::class.java
            )

        val channel =
            NotificationChannel(
                "eye_guard",
                "An toàn mắt",
                NotificationManager.IMPORTANCE_LOW
            )

        manager.createNotificationChannel(
            channel
        )
    }

    private fun createNotification():
        Notification {

        return Notification.Builder(
            this,
            "eye_guard"
        )
            .setContentTitle(
                "An toàn mắt đang hoạt động"
            )
            .setContentText(
                "Đang theo dõi khoảng cách"
            )
            .setSmallIcon(
                android.R.drawable.ic_menu_view
            )
            .setOngoing(true)
            .build()
    }

    private fun startFrontCamera() {

        if (!Settings.canDrawOverlays(this)) {
            return
        }

        val cameraProviderFuture =
            ProcessCameraProvider.getInstance(
                this
            )

        cameraProviderFuture.addListener({

            val cameraProvider =
                cameraProviderFuture.get()

            val analysis =
                ImageAnalysis.Builder()
                    .setBackpressureStrategy(
                        ImageAnalysis
                            .STRATEGY_KEEP_ONLY_LATEST
                    )
                    .build()

            val detector =
                FaceDetection.getClient(
                    FaceDetectorOptions.Builder()
                        .setPerformanceMode(
                            FaceDetectorOptions
                                .PERFORMANCE_MODE_FAST
                        )
                        .enableTracking()
                        .build()
                )

            analysis.setAnalyzer(
                executor
            ) { imageProxy ->

                val mediaImage =
                    imageProxy.image

                if (mediaImage == null) {

                    imageProxy.close()

                    return@setAnalyzer
                }

                val image =
                    InputImage.fromMediaImage(
                        mediaImage,
                        imageProxy
                            .imageInfo
                            .rotationDegrees
                    )

                detector.process(image)

                    .addOnSuccessListener { faces ->

                        if (faces.isEmpty()) {

                            closeStartTime = 0L

                            hideShield()

                            return@addOnSuccessListener
                        }

                        val face =
                            faces.maxBy {
                                it.boundingBox.width()
                            }

                        val width =
                            face.boundingBox
                                .width()
                                .toFloat()

                        if (
                            referenceFaceWidth == 0f
                        ) {

                            referenceFaceWidth =
                                width
                        }

                        val distance =
                            40f *
                            referenceFaceWidth /
                            max(width, 1f)

                        val tooClose =
                            distance < 35f

                        if (tooClose) {

                            if (
                                closeStartTime == 0L
                            ) {

                                closeStartTime =
                                    System.currentTimeMillis()
                            }

                            val elapsed =
                                System.currentTimeMillis() -
                                closeStartTime

                            if (
                                elapsed >= 1500
                            ) {

                                showShield()
                            }

                        } else {

                            closeStartTime = 0L

                            hideShield()
                        }
                    }

                    .addOnCompleteListener {
                        imageProxy.close()
                    }
            }

            cameraProvider.unbindAll()

            cameraProvider.bindToLifecycle(
                this,
                CameraSelector.DEFAULT_FRONT_CAMERA,
                analysis
            )

        }, ContextCompat.getMainExecutor(this))
    }

    private fun showShield() {

        if (shieldView != null) {
            return
        }

        windowManager =
            getSystemService(
                Context.WINDOW_SERVICE
            ) as WindowManager

        val view =
            View(this)

        view.setBackgroundColor(
            Color.BLACK
        )

        view.alpha = 0.98f

        val windowType =
            if (Build.VERSION.SDK_INT >= 26)
                WindowManager.LayoutParams
                    .TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams
                    .TYPE_PHONE

        val params =
            WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                windowType,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT
            )

        params.gravity =
            Gravity.CENTER

        try {

            windowManager?.addView(
                view,
                params
            )

            shieldView = view

        } catch (_: Exception) {
        }
    }

    private fun hideShield() {

        val view =
            shieldView ?: return

        try {

            windowManager?.removeView(
                view
            )

        } catch (_: Exception) {
        }

        shieldView = null
    }

    override fun onDestroy() {

        hideShield()

        executor.shutdown()

        super.onDestroy()
    }

    override fun onBind(
        intent: android.content.Intent
    ): IBinder? {

        return super.onBind(intent)
    }
}
