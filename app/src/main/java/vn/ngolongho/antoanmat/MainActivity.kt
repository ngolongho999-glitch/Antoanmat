package com.example.screendistance

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Button
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Màn hình giao diện đơn giản có nút Bật/Tắt giám sát
        val button = Button(this).apply {
            text = "Kích hoạt bảo vệ mắt"
            setOnClickListener {
                checkPermissionsAndStartService()
            }
        }
        setContentView(button)
    }

    private fun checkPermissionsAndStartService() {
        // 1. Kiểm tra quyền Camera
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), 100)
            return
        }

        // 2. Kiểm tra quyền hiển thị trên ứng dụng khác (Overlay)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            startActivityForResult(intent, 101)
            Toast.makeText(this, "Vui lòng cấp quyền Hiển thị trên ứng dụng khác", Toast.LENGTH_LONG).show()
            return
        }

        // 3. Khởi chạy Foreground Service
        val serviceIntent = Intent(this, ScreenDistanceService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
        
        Toast.makeText(this, "Đã bật tính năng bảo vệ mắt ngầm!", Toast.LENGTH_SHORT).show()
    }
}
