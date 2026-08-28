package vn.ngolongho.antoanmat

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class MainActivity : Activity() {

    private lateinit var password: EditText
    private lateinit var status: TextView

    private val requestCode = 100

    override fun onCreate(savedInstanceState: Bundle?) {

        super.onCreate(savedInstanceState)

        val layout = LinearLayout(this)

        layout.orientation = LinearLayout.VERTICAL

        layout.setPadding(
            40,
            50,
            40,
            40
        )

        val title = TextView(this)

        title.text =
            "AN TOÀN MẮT\n\n" +
            "Ứng dụng giúp phát hiện khi điện thoại " +
            "được đưa quá gần khuôn mặt."

        title.textSize = 22f

        layout.addView(title)

        password = EditText(this)

        password.hint =
            "Mật khẩu quản trị"

        password.inputType = 2

        layout.addView(password)

        val savePassword = Button(this)

        savePassword.text =
            "LƯU MẬT KHẨU"

        savePassword.setOnClickListener {

            val pin =
                password.text.toString()

            if (pin.length < 4) {

                status.text =
                    "Mật khẩu phải có ít nhất 4 số."

                return@setOnClickListener
            }

            getPreferences(
                MODE_PRIVATE
            )
                .edit()
                .putString(
                    "admin_pin",
                    pin
                )
                .apply()

            status.text =
                "Đã lưu mật khẩu quản trị."
        }

        layout.addView(savePassword)

        val overlayButton =
            Button(this)

        overlayButton.text =
            "CẤP QUYỀN PHỦ MÀN HÌNH"

        overlayButton.setOnClickListener {

            val intent =
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse(
                        "package:$packageName"
                    )
                )

            startActivity(intent)
        }

        layout.addView(overlayButton)

        val startButton =
            Button(this)

        startButton.text =
            "BẬT BẢO VỆ MẮT"

        startButton.setOnClickListener {

            if (
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.CAMERA
                ) != PackageManager.PERMISSION_GRANTED
            ) {

                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(
                        Manifest.permission.CAMERA,
                        Manifest.permission.POST_NOTIFICATIONS
                    ),
                    requestCode
                )

            } else {

                val intent =
                    Intent(
                        this,
                        EyeGuardService::class.java
                    )

                ContextCompat.startForegroundService(
                    this,
                    intent
                )

                status.text =
                    "Đã bật bảo vệ mắt."
            }
        }

        layout.addView(startButton)

        val stopButton =
            Button(this)

        stopButton.text =
            "TẮT BẢO VỆ - CẦN MẬT KHẨU"

        stopButton.setOnClickListener {

            val savedPin =
                getPreferences(
                    MODE_PRIVATE
                )
                    .getString(
                        "admin_pin",
                        null
                    )

            if (savedPin == null) {

                status.text =
                    "Bạn chưa thiết lập mật khẩu."

                return@setOnClickListener
            }

            if (
                password.text.toString() != savedPin
            ) {

                status.text =
                    "Mật khẩu không đúng."

                return@setOnClickListener
            }

            stopService(
                Intent(
                    this,
                    EyeGuardService::class.java
                )
            )

            status.text =
                "Đã tắt bảo vệ mắt."
        }

        layout.addView(stopButton)

        status = TextView(this)

        status.text =
            "\nTrạng thái: Chưa bật"

        status.textSize = 16f

        layout.addView(status)

        setContentView(layout)
    }
}
