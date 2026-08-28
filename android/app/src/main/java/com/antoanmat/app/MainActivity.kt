package com.antoanmat.app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.EditText
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import com.antoanmat.app.databinding.ActivityMainBinding

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        checkPermissions()
        setupPinProtection()
    }

    private fun checkPermissions() {
        // Xin quyền Camera
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.CAMERA), 101
        )

        // Xin quyền Vẽ đè màn hình (System Overlay)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            startActivityForResult(intent, 102)
        } else {
            startEyeProtectionService()
        }
    }

    private fun startEyeProtectionService() {
        val intent = Intent(this, EyeProtectionService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    // YÊU CẦU 4: Chống tắt lén - Thiết lập PIN ban đầu & Yêu cầu PIN khi tắt
    private fun setupPinProtection() {
        val prefs = getSharedPreferences("antoanmat_prefs", Context.MODE_PRIVATE)
        val savedPin = prefs.getString("user_pin", null)

        if (savedPin == null) {
            val input = EditText(this)
            input.hint = "Nhập mã PIN 4 số"
            AlertDialog.Builder(this)
                .setTitle("Thiết lập mật khẩu chống tắt lén")
                .setMessage("Nhập mã PIN để bảo vệ ứng dụng không bị trẻ tự ý tắt:")
                .setView(input)
                .setCancelable(false)
                .setPositiveButton("Lưu PIN") { _, _ ->
                    val pin = input.text.toString()
                    if (pin.length >= 4) {
                        prefs.edit().putString("user_pin", pin).apply()
                        Toast.makeText(this, "Đã lưu PIN thành công!", Toast.LENGTH_SHORT).show()
                        startEyeProtectionService()
                    } else {
                        setupPinProtection()
                    }
                }.show()
        }

        binding.btnToggleService.setOnClickListener {
            val input = EditText(this)
            input.hint = "Mật khẩu 4 số"
            AlertDialog.Builder(this)
                .setTitle("Xác nhận mật khẩu")
                .setMessage("Nhập PIN để dừng dịch vụ bảo vệ:")
                .setView(input)
                .setPositiveButton("Dừng dịch vụ") { _, _ ->
                    val currentPin = prefs.getString("user_pin", "")
                    if (input.text.toString() == currentPin) {
                        stopService(Intent(this, EyeProtectionService::class.java))
                        Toast.makeText(this, "Đã dừng dịch vụ bảo vệ.", Toast.LENGTH_SHORT).show()
                    } else {
                        Toast.makeText(this, "Sai mật khẩu!", Toast.LENGTH_SHORT).show()
                    }
                }
                .setNegativeButton("Hủy", null)
                .show()
        }
    }
}
