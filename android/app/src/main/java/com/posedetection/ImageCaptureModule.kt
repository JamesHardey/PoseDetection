package com.posedetection

import android.graphics.Bitmap
import android.net.Uri
import android.provider.MediaStore
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.modules.core.DeviceEventManagerModule
import java.io.File
import java.io.FileOutputStream

class ImageCaptureModule(reactContext: ReactApplicationContext) : ReactContextBaseJavaModule(reactContext) {

    override fun getName(): String {
        return "ImageCaptureModule"
    }

    @ReactMethod
    fun saveImage(imageUri: String, promise: Promise) {
        try {
            // For now, just resolve with the URI
            // The actual saving will be handled in CameraViewManager
            promise.resolve(imageUri)
        } catch (e: Exception) {
            promise.reject("SAVE_ERROR", "Failed to save image", e)
        }
    }

    fun sendCaptureEvent(imageUri: String) {
        val params = com.facebook.react.bridge.Arguments.createMap()
        params.putString("uri", imageUri)
        reactApplicationContext
            .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
            .emit("onImageCaptured", params)
    }
}
