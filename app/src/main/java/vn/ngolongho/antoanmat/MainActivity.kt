package vn.ngolongho.antoanmat

import android.os.Bundle
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val textView = TextView(this).apply {
            text = "AN TOÀN MẮT\n\nỨng dụng đang khởi động..."
            textSize = 24f
            gravity = android.view.Gravity.CENTER
            setPadding(40, 40, 40, 40)
        }

        setContentView(textView)
    }
}
