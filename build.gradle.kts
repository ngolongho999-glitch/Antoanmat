dependencies {
    // CameraX
    val cameraVersion = "1.3.4"
    implementation("androidx.camera:camera-camera2:$cameraVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraVersion")
    implementation("androidx.camera:camera-view:$cameraVersion")

    // Google ML Kit Face Detection
    implementation("com.google.mlkit:face-detection:16.1.6")

    // Lifecycle Service cho CameraX trong Background
    implementation("androidx.lifecycle:lifecycle-service:2.8.4")
}
