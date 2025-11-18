package com.posedetection

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.speech.tts.TextToSpeech
import android.util.Log
import android.view.Choreographer
import android.view.View
import android.view.ViewGroup
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.pose.Pose
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.PoseDetector
import com.google.mlkit.vision.pose.PoseLandmark
import com.google.mlkit.vision.pose.defaults.PoseDetectorOptions
import java.nio.ByteBuffer
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.*

@ExperimentalGetImage
class CameraViewManager(private val reactContext: ReactApplicationContext) : SimpleViewManager<ConstraintLayout>() {
    
    companion object {
        private const val TAG = "CameraViewManager"
    }

    private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var currentLensFacing: Int = CameraSelector.LENS_FACING_FRONT
    private var currentView: ConstraintLayout? = null
    
    private var textToSpeech: TextToSpeech? = null
    private var lastSpokenTime = 0L
    private val SPEECH_COOLDOWN = 3000L // 3 seconds between voice instructions
    
    private val options = PoseDetectorOptions.Builder()
        .setDetectorMode(PoseDetectorOptions.STREAM_MODE)
        .build()

    private val poseDetector: PoseDetector = PoseDetection.getClient(options)
    
    private var isProcessing = false
    private val lock = Any()
    
    private var latestCleanBitmap: Bitmap? = null
    private var shouldCaptureClean = false

    // Countdown and capture state
    private var isCountingDown = false
    private var countdownValue = 5
    private var consecutiveGoodFrames = 0
    private val REQUIRED_GOOD_FRAMES = 10
    private var lastCountdownTime = 0L
    private var smileSaidTime = 0L
    private val SMILE_DELAY = 2000L // 2 seconds delay after saying smile
    private var imageCaptured = false // Flag to prevent multiple captures

    // Reference pose
    private val referencePose = ReferencePose(
        shoulderAngle = 90.0,
        shoulderAngleTolerance = 15.0,
        elbowAngleLeft = 180.0,
        elbowAngleRight = 180.0,
        elbowAngleTolerance = 20.0,
        spineAngle = 0.0,
        spineAngleTolerance = 10.0,
        hipAngleLeft = 180.0,
        hipAngleRight = 180.0,
        hipAngleTolerance = 15.0,
        shoulderLevelDiff = 0.0,
        shoulderLevelTolerance = 30.0
    )
    
    override fun getName(): String {
        return "CameraView"
    }

    override fun createViewInstance(reactContext: ThemedReactContext): ConstraintLayout {
        // Initialize TextToSpeech
        textToSpeech = TextToSpeech(reactContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                textToSpeech?.language = Locale.US
                Log.d(TAG, "TextToSpeech initialized successfully")
            } else {
                Log.e(TAG, "TextToSpeech initialization failed")
            }
        }
        
        val constraintLayout = ConstraintLayout(reactContext)
        constraintLayout.setBackgroundColor(Color.BLACK)
        constraintLayout.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        
        val previewView = PreviewView(reactContext)
        previewView.setBackgroundColor(Color.BLACK)
        previewView.implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        previewView.id = android.view.View.generateViewId()
        
        val previewParams = ConstraintLayout.LayoutParams(
            ConstraintLayout.LayoutParams.MATCH_PARENT,
            ConstraintLayout.LayoutParams.MATCH_PARENT
        )
        previewParams.topToTop = ConstraintLayout.LayoutParams.PARENT_ID
        previewParams.bottomToBottom = ConstraintLayout.LayoutParams.PARENT_ID
        previewParams.startToStart = ConstraintLayout.LayoutParams.PARENT_ID
        previewParams.endToEnd = ConstraintLayout.LayoutParams.PARENT_ID
        
        previewView.layoutParams = previewParams
        constraintLayout.addView(previewView)
        
        // Add overlay view
        val overlayView = PoseOverlayView(reactContext)
        overlayView.id = android.view.View.generateViewId()
        
        val overlayParams = ConstraintLayout.LayoutParams(
            ConstraintLayout.LayoutParams.MATCH_PARENT,
            ConstraintLayout.LayoutParams.MATCH_PARENT
        )
        overlayParams.topToTop = ConstraintLayout.LayoutParams.PARENT_ID
        overlayParams.bottomToBottom = ConstraintLayout.LayoutParams.PARENT_ID
        overlayParams.startToStart = ConstraintLayout.LayoutParams.PARENT_ID
        overlayParams.endToEnd = ConstraintLayout.LayoutParams.PARENT_ID
        
        overlayView.layoutParams = overlayParams
        constraintLayout.addView(overlayView)
        
        // Store views as tags
        constraintLayout.tag = previewView
        constraintLayout.setTag(R.id.pose_overlay_tag, overlayView)
        
        // Install hierarchy fitter AFTER adding views - critical for CameraX
        installHierarchyFitter(constraintLayout)
        
        // Store reference to current view
        currentView = constraintLayout
        
        Log.d(TAG, "ConstraintLayout created with PreviewView and PoseOverlayView")
        
        return constraintLayout
    }

    private fun installHierarchyFitter(view: ViewGroup) {
        // CameraX black screen fix - continuous layout with Choreographer
        // Solution from: https://stackoverflow.com/questions/79664703
        Choreographer.getInstance().postFrameCallback(object : Choreographer.FrameCallback {
            override fun doFrame(frameTimeNanos: Long) {
                manuallyLayoutChildren(view)
                view.viewTreeObserver.dispatchOnGlobalLayout()
                Choreographer.getInstance().postFrameCallback(this)
            }
        })
    }
    
    private fun manuallyLayoutChildren(viewGroup: ViewGroup) {
        for (i in 0 until viewGroup.childCount) {
            val child = viewGroup.getChildAt(i)
            child.measure(
                View.MeasureSpec.makeMeasureSpec(viewGroup.measuredWidth, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(viewGroup.measuredHeight, View.MeasureSpec.EXACTLY)
            )
            child.layout(0, 0, child.measuredWidth, child.measuredHeight)
        }
    }

    @ReactProp(name = "cameraType")
    fun setCameraType(view: ConstraintLayout, cameraType: String? = "front") {
        currentLensFacing = when (cameraType) {
            "front" -> CameraSelector.LENS_FACING_FRONT
            else -> CameraSelector.LENS_FACING_BACK
        }
        Log.d(TAG, "Setting camera type to: $cameraType (lensFacing: $currentLensFacing)")
        
        val previewView = view.tag as? PreviewView
        val overlayView = view.getTag(R.id.pose_overlay_tag) as? PoseOverlayView
        
        if (previewView != null && overlayView != null) {
            // Add delay to ensure view is fully ready and screen is active
            view.postDelayed({
                if (view.isAttachedToWindow) {
                    startCamera(previewView, overlayView, currentLensFacing)
                } else {
                    Log.w(TAG, "View not attached to window, skipping camera start")
                }
            }, 300) // 300ms delay
        } else {
            Log.e(TAG, "PreviewView or OverlayView not found")
        }
    }

    private fun startCamera(previewView: PreviewView, overlayView: PoseOverlayView, lensFacing: Int) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(reactContext)

        cameraProviderFuture.addListener({
            try {
                val cameraProvider = cameraProviderFuture.get()
                
                val preview = Preview.Builder()
                    .build()
                    .also {
                        it.setSurfaceProvider(previewView.surfaceProvider)
                    }

                val imageAnalysis = ImageAnalysis.Builder()
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()

                imageAnalysis.setAnalyzer(cameraExecutor) { imageProxy ->
                    synchronized(lock) {
                        if (isProcessing) {
                            imageProxy.close()
                            return@setAnalyzer
                        }
                        isProcessing = true
                    }

                    val image = imageProxy.image
                    if (image == null) {
                        synchronized(lock) { isProcessing = false }
                        imageProxy.close()
                        return@setAnalyzer
                    }

                    try {
                        // Skip processing if image already captured
                        if (imageCaptured) {
                            synchronized(lock) { isProcessing = false }
                            return@setAnalyzer
                        }
                        
                        val buffer: ByteBuffer = image.planes[0].buffer
                        buffer.rewind()
                        val bitmap = Bitmap.createBitmap(
                            imageProxy.width,
                            imageProxy.height,
                            Bitmap.Config.ARGB_8888
                        )
                        bitmap.copyPixelsFromBuffer(buffer)

                        val matrix = Matrix().apply {
                            postRotate(270f)
                            postScale(-1f, 1f, imageProxy.width / 2f, imageProxy.height / 2f)
                        }

                        val rotatedBitmap = Bitmap.createBitmap(
                            bitmap, 0, 0,
                            imageProxy.width, imageProxy.height, matrix, false
                        )
                        
                        // Store clean bitmap for potential capture
                        latestCleanBitmap = rotatedBitmap.copy(Bitmap.Config.ARGB_8888, false)

                        val inputImage = InputImage.fromBitmap(rotatedBitmap, 0)
                        poseDetector.process(inputImage)
                            .addOnSuccessListener { pose ->
                                // First check: Is a person fully detected?
                                val personDetected = isPersonFullyDetected(pose)
                                
                                if (!personDetected) {
                                    provideVoiceFeedback("Please stand in front of camera", null, null)
                                    
                                    if (!imageCaptured) {
                                        val activity = reactContext.currentActivity
                                        activity?.runOnUiThread {
                                            overlayView.updatePose(null, null, false, 0, false)
                                            overlayView.updateBitmap(rotatedBitmap)
                                        }
                                    }
                                    
                                    synchronized(lock) { isProcessing = false }
                                    return@addOnSuccessListener
                                }
                                
                                // Second check: Is person positioned correctly in box?
                                val positionCheck = checkBodyPosition(
                                    pose,
                                    rotatedBitmap.width,
                                    rotatedBitmap.height
                                )
                                
                                if (!positionCheck.inBox) {
                                    provideVoiceFeedback(positionCheck.issues.firstOrNull(), null, positionCheck)
                                    
                                    if (!imageCaptured) {
                                        val activity = reactContext.currentActivity
                                        activity?.runOnUiThread {
                                            overlayView.updatePose(pose, null, false, 0, false)
                                            overlayView.updateBitmap(rotatedBitmap)
                                        }
                                    }
                                    
                                    synchronized(lock) { isProcessing = false }
                                    return@addOnSuccessListener
                                }
                                
                                // Third check: Is posture accurate?
                                val metrics = calculatePostureMetrics(pose)
                                val accuracy = compareWithReference(metrics, referencePose)
                                val isPerfectPose = isPoseAccurate(accuracy, positionCheck)
                                
                                // Provide posture feedback if not perfect
                                if (!isPerfectPose) {
                                    provideVoiceFeedback(null, accuracy, positionCheck)
                                }
                                
                                handlePoseCapture(isPerfectPose)

                                // Skip overlay updates if image was already captured
                                if (!imageCaptured) {
                                    val activity = reactContext.currentActivity
                                    activity?.runOnUiThread {
                                        overlayView.updatePose(
                                            pose,
                                            accuracy,
                                            isPerfectPose,
                                            countdownValue,
                                            isCountingDown
                                        )
                                        overlayView.updateBitmap(rotatedBitmap)
                                    }
                                }

                                synchronized(lock) {
                                    isProcessing = false
                                }
                            }
                            .addOnFailureListener { e ->
                                Log.e(TAG, "Pose detection failed", e)
                                synchronized(lock) {
                                    isProcessing = false
                                }
                            }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error processing image", e)
                        synchronized(lock) {
                            isProcessing = false
                        }
                    } finally {
                        imageProxy.close()
                    }
                }

                val cameraSelector = CameraSelector.Builder()
                    .requireLensFacing(lensFacing)
                    .build()

                cameraProvider.unbindAll()

                val activity = reactContext.currentActivity
                if (activity is LifecycleOwner) {
                    Log.d(TAG, "Binding camera to lifecycle")
                    cameraProvider.bindToLifecycle(
                        activity,
                        cameraSelector,
                        preview,
                        imageAnalysis
                    )
                    Log.d(TAG, "Camera started successfully with pose detection")
                } else {
                    Log.e(TAG, "Activity is not a LifecycleOwner")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error starting camera", e)
                e.printStackTrace()
            }
        }, ContextCompat.getMainExecutor(reactContext))
    }

    override fun onDropViewInstance(view: ConstraintLayout) {
        super.onDropViewInstance(view)
        Log.d(TAG, "Dropping view instance")
        
        // Clear current view reference
        currentView = null
        
        // Cleanup TextToSpeech
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        
        val cameraProviderFuture = ProcessCameraProvider.getInstance(reactContext)
        cameraProviderFuture.addListener({
            try {
                val cameraProvider = cameraProviderFuture.get()
                cameraProvider.unbindAll()
                poseDetector.close()
                cameraExecutor.shutdown()
                Log.d(TAG, "Camera unbound successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Error unbinding camera", e)
                e.printStackTrace()
            }
        }, ContextCompat.getMainExecutor(reactContext))
    }

    private fun calculatePostureMetrics(pose: Pose): PostureMetrics {
        val leftShoulder = pose.getPoseLandmark(PoseLandmark.LEFT_SHOULDER)
        val rightShoulder = pose.getPoseLandmark(PoseLandmark.RIGHT_SHOULDER)
        val leftElbow = pose.getPoseLandmark(PoseLandmark.LEFT_ELBOW)
        val rightElbow = pose.getPoseLandmark(PoseLandmark.RIGHT_ELBOW)
        val leftWrist = pose.getPoseLandmark(PoseLandmark.LEFT_WRIST)
        val rightWrist = pose.getPoseLandmark(PoseLandmark.RIGHT_WRIST)
        val leftHip = pose.getPoseLandmark(PoseLandmark.LEFT_HIP)
        val rightHip = pose.getPoseLandmark(PoseLandmark.RIGHT_HIP)
        val leftKnee = pose.getPoseLandmark(PoseLandmark.LEFT_KNEE)
        val rightKnee = pose.getPoseLandmark(PoseLandmark.RIGHT_KNEE)

        val shoulderAngleLeft = if (leftShoulder != null && leftElbow != null && leftHip != null) {
            calculateAngle(leftHip, leftShoulder, leftElbow)
        } else 0.0

        val shoulderAngleRight = if (rightShoulder != null && rightElbow != null && rightHip != null) {
            calculateAngle(rightHip, rightShoulder, rightElbow)
        } else 0.0

        val elbowAngleLeft = if (leftShoulder != null && leftElbow != null && leftWrist != null) {
            calculateAngle(leftShoulder, leftElbow, leftWrist)
        } else 0.0

        val elbowAngleRight = if (rightShoulder != null && rightElbow != null && rightWrist != null) {
            calculateAngle(rightShoulder, rightElbow, rightWrist)
        } else 0.0

        val spineAngle = if (leftShoulder != null && rightShoulder != null && leftHip != null && rightHip != null) {
            val shoulderMidX = (leftShoulder.position.x + rightShoulder.position.x) / 2
            val shoulderMidY = (leftShoulder.position.y + rightShoulder.position.y) / 2
            val hipMidX = (leftHip.position.x + rightHip.position.x) / 2
            val hipMidY = (leftHip.position.y + rightHip.position.y) / 2

            val angle = atan2((shoulderMidX - hipMidX).toDouble(), (hipMidY - shoulderMidY).toDouble())
            abs(Math.toDegrees(angle))
        } else 0.0

        val hipAngleLeft = if (leftShoulder != null && leftHip != null && leftKnee != null) {
            calculateAngle(leftShoulder, leftHip, leftKnee)
        } else 0.0

        val hipAngleRight = if (rightShoulder != null && rightHip != null && rightKnee != null) {
            calculateAngle(rightShoulder, rightHip, rightKnee)
        } else 0.0

        val shoulderLevelDiff = if (leftShoulder != null && rightShoulder != null) {
            abs(leftShoulder.position.y - rightShoulder.position.y)
        } else 0f

        return PostureMetrics(
            shoulderAngleLeft = shoulderAngleLeft,
            shoulderAngleRight = shoulderAngleRight,
            elbowAngleLeft = elbowAngleLeft,
            elbowAngleRight = elbowAngleRight,
            spineAngle = spineAngle,
            hipAngleLeft = hipAngleLeft,
            hipAngleRight = hipAngleRight,
            shoulderLevelDiff = shoulderLevelDiff.toDouble()
        )
    }

    private fun calculateAngle(
        firstPoint: PoseLandmark,
        midPoint: PoseLandmark,
        lastPoint: PoseLandmark
    ): Double {
        val result = Math.toDegrees(
            atan2(
                (lastPoint.position.y - midPoint.position.y).toDouble(),
                (lastPoint.position.x - midPoint.position.x).toDouble()
            ) - atan2(
                (firstPoint.position.y - midPoint.position.y).toDouble(),
                (firstPoint.position.x - midPoint.position.x).toDouble()
            )
        )
        return abs(if (result > 180) 360 - result else result)
    }

    private fun compareWithReference(current: PostureMetrics, reference: ReferencePose): PostureAccuracy {
        val shoulderDiffL = abs(current.shoulderAngleLeft - reference.shoulderAngle)
        val shoulderDiffR = abs(current.shoulderAngleRight - reference.shoulderAngle)
        val elbowDiffL = abs(current.elbowAngleLeft - reference.elbowAngleLeft)
        val elbowDiffR = abs(current.elbowAngleRight - reference.elbowAngleRight)
        val spineDiff = current.spineAngle
        val hipDiffL = abs(current.hipAngleLeft - reference.hipAngleLeft)
        val hipDiffR = abs(current.hipAngleRight - reference.hipAngleRight)

        return PostureAccuracy(
            shoulderAccurateLeft = shoulderDiffL <= reference.shoulderAngleTolerance,
            shoulderAccurateRight = shoulderDiffR <= reference.shoulderAngleTolerance,
            elbowAccurateLeft = elbowDiffL <= reference.elbowAngleTolerance,
            elbowAccurateRight = elbowDiffR <= reference.elbowAngleTolerance,
            spineAccurate = spineDiff <= reference.spineAngleTolerance,
            hipAccurateLeft = hipDiffL <= reference.hipAngleTolerance,
            hipAccurateRight = hipDiffR <= reference.hipAngleTolerance,
            shoulderLevelAccurate = current.shoulderLevelDiff <= reference.shoulderLevelTolerance,
            shoulderDiffLeft = shoulderDiffL,
            shoulderDiffRight = shoulderDiffR,
            elbowDiffLeft = elbowDiffL,
            elbowDiffRight = elbowDiffR,
            spineDiff = spineDiff,
            hipDiffLeft = hipDiffL,
            hipDiffRight = hipDiffR
        )
    }

    private fun isPersonFullyDetected(pose: Pose): Boolean {
        // Check if all critical landmarks are detected
        val criticalLandmarks = listOf(
            PoseLandmark.NOSE,
            PoseLandmark.LEFT_SHOULDER,
            PoseLandmark.RIGHT_SHOULDER,
            PoseLandmark.LEFT_ELBOW,
            PoseLandmark.RIGHT_ELBOW,
            PoseLandmark.LEFT_WRIST,
            PoseLandmark.RIGHT_WRIST,
            PoseLandmark.LEFT_HIP,
            PoseLandmark.RIGHT_HIP,
            PoseLandmark.LEFT_KNEE,
            PoseLandmark.RIGHT_KNEE
        )
        
        return criticalLandmarks.all { landmarkType ->
            pose.getPoseLandmark(landmarkType) != null
        }
    }
    
    private fun provideVoiceFeedback(
        customMessage: String?,
        accuracy: PostureAccuracy?,
        positionCheck: PositionCheck?
    ) {
        val currentTime = System.currentTimeMillis()
        if (currentTime - lastSpokenTime < SPEECH_COOLDOWN) return

        val feedback = customMessage ?: run {
            // Check position first
            if (positionCheck != null && !positionCheck.inBox && positionCheck.issues.isNotEmpty()) {
                positionCheck.issues.first()
            } else if (accuracy != null) {
                // Check posture
                when {
                    !accuracy.shoulderAccurateLeft && accuracy.shoulderDiffLeft > 20 ->
                        "Raise your right arm higher"
                    !accuracy.shoulderAccurateRight && accuracy.shoulderDiffRight > 20 ->
                        "Raise your left arm higher"
                    !accuracy.elbowAccurateLeft ->
                        "Straighten your right arm"
                    !accuracy.elbowAccurateRight ->
                        "Straighten your left arm"
                    !accuracy.spineAccurate ->
                        "Stand up straight"
                    !accuracy.shoulderLevelAccurate ->
                        "Level your shoulders"
                    !accuracy.hipAccurateLeft || !accuracy.hipAccurateRight ->
                        "Keep your legs straight"
                    else -> null
                }
            } else {
                null
            }
        }

        feedback?.let {
            textToSpeech?.speak(it, TextToSpeech.QUEUE_FLUSH, null, null)
            lastSpokenTime = currentTime
            Log.d(TAG, "Voice feedback: $it")
        }
    }

    private fun checkBodyPosition(pose: Pose, width: Int, height: Int): PositionCheck {
        val issues = mutableListOf<String>()
        val targetBox = TargetBox(0.05f, 0.05f, 0.95f, 0.95f)

        // Check critical body landmarks to ensure entire body is in frame, especially feet
        val leftAnkle = pose.getPoseLandmark(PoseLandmark.LEFT_ANKLE)
        val rightAnkle = pose.getPoseLandmark(PoseLandmark.RIGHT_ANKLE)
        val leftHeel = pose.getPoseLandmark(PoseLandmark.LEFT_HEEL)
        val rightHeel = pose.getPoseLandmark(PoseLandmark.RIGHT_HEEL)
        val leftFootIndex = pose.getPoseLandmark(PoseLandmark.LEFT_FOOT_INDEX)
        val rightFootIndex = pose.getPoseLandmark(PoseLandmark.RIGHT_FOOT_INDEX)
        val leftWrist = pose.getPoseLandmark(PoseLandmark.LEFT_WRIST)
        val rightWrist = pose.getPoseLandmark(PoseLandmark.RIGHT_WRIST)
        val nose = pose.getPoseLandmark(PoseLandmark.NOSE)
        val leftShoulder = pose.getPoseLandmark(PoseLandmark.LEFT_SHOULDER)
        val rightShoulder = pose.getPoseLandmark(PoseLandmark.RIGHT_SHOULDER)

        // Include all foot landmarks to ensure complete foot is in box
        val landmarks = listOfNotNull(
            leftAnkle, rightAnkle, 
            leftHeel, rightHeel, 
            leftFootIndex, rightFootIndex,
            leftWrist, rightWrist, 
            nose, leftShoulder, rightShoulder
        )
        
        if (landmarks.isEmpty()) {
            return PositionCheck(false, listOf("Stand in front of camera"))
        }

        // No positional checks - accept all positions
        return PositionCheck(true, issues)
    }

    private fun isPoseAccurate(accuracy: PostureAccuracy, positionCheck: PositionCheck): Boolean {
        return positionCheck.inBox &&
                accuracy.shoulderAccurateLeft &&
                accuracy.shoulderAccurateRight &&
                accuracy.elbowAccurateLeft &&
                accuracy.elbowAccurateRight &&
                accuracy.spineAccurate &&
                accuracy.hipAccurateLeft &&
                accuracy.hipAccurateRight &&
                accuracy.shoulderLevelAccurate
    }

    private fun handlePoseCapture(isPerfectPose: Boolean) {
        if (isPerfectPose) {
            consecutiveGoodFrames++

            if (consecutiveGoodFrames >= REQUIRED_GOOD_FRAMES && !isCountingDown) {
                isCountingDown = true
                countdownValue = 5
                lastCountdownTime = System.currentTimeMillis()
                smileSaidTime = 0L
                textToSpeech?.speak("Perfect posture! Hold still", TextToSpeech.QUEUE_FLUSH, null, null)
                Log.d(TAG, "Perfect posture detected! Starting countdown")
            } else if (isCountingDown) {
                val currentTime = System.currentTimeMillis()
                
                // Check if we said "smile" and are waiting
                if (smileSaidTime > 0) {
                    if (currentTime - smileSaidTime >= SMILE_DELAY && !imageCaptured) {
                        // Capture the clean image
                        latestCleanBitmap?.let { bitmap ->
                            captureAndSaveImage(bitmap)
                            imageCaptured = true // Set flag to stop further captures
                            
                            // Clear the overlay to remove pose lines and box
                            val activity = reactContext.currentActivity
                            activity?.runOnUiThread {
                                val constraintLayout = currentView
                                val overlayView = constraintLayout?.getTag(R.id.pose_overlay_tag) as? PoseOverlayView
                                overlayView?.updatePose(null, null, false, 0, false)
                                overlayView?.updateBitmap(null)
                            }
                        }
                        isCountingDown = false
                        consecutiveGoodFrames = 0
                        countdownValue = 5
                        smileSaidTime = 0L
                    }
                } else if (currentTime - lastCountdownTime >= 1000) {
                    countdownValue--
                    lastCountdownTime = currentTime

                    if (countdownValue > 0) {
                        textToSpeech?.speak(countdownValue.toString(), TextToSpeech.QUEUE_FLUSH, null, null)
                    } else {
                        // Say "Smile!" and start the 2-second timer
                        textToSpeech?.speak("Smile!", TextToSpeech.QUEUE_FLUSH, null, null)
                        smileSaidTime = currentTime
                        Log.d(TAG, "Smile said, waiting 2 seconds before capture")
                    }
                }
            }
        } else {
            if (isCountingDown) {
                textToSpeech?.speak("Hold your position", TextToSpeech.QUEUE_FLUSH, null, null)
                Log.d(TAG, "Pose lost during countdown - resetting")
                isCountingDown = false
                countdownValue = 5
                smileSaidTime = 0L
            }
            consecutiveGoodFrames = 0
        }
    }
    
    private fun captureAndSaveImage(bitmap: Bitmap) {
        try {
            val fileName = "pose_${System.currentTimeMillis()}.jpg"
            val contentValues = android.content.ContentValues().apply {
                put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, fileName)
                put(android.provider.MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                put(android.provider.MediaStore.Images.Media.RELATIVE_PATH, "Pictures/PoseDetection")
            }

            val uri = reactContext.contentResolver.insert(
                android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                contentValues
            )

            uri?.let {
                reactContext.contentResolver.openOutputStream(it)?.use { outputStream ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 95, outputStream)
                }
                
                Log.d(TAG, "Image saved successfully: $uri")
                
                // Send event to React Native with the image URI
                val imageCaptureModule = reactContext.getNativeModule(ImageCaptureModule::class.java)
                imageCaptureModule?.sendCaptureEvent(uri.toString())
                
                textToSpeech?.speak("Photo captured successfully!", TextToSpeech.QUEUE_FLUSH, null, null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error saving image", e)
            textToSpeech?.speak("Failed to save photo", TextToSpeech.QUEUE_FLUSH, null, null)
        }
    }
}
