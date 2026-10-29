package com.brewingbytes.haystack.helpers

import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import java.io.FileOutputStream

/**
 * Reads the Android accessibility settings Godot does not apply on its own (design D14), and
 * hosts the Test Lab Game Loop hooks for the G2 frame harness (res://game/game_loop.gd).
 */
class HaystackHelpers(godot: Godot) : GodotPlugin(godot) {

    override fun getPluginName() = "HaystackHelpers"

    /** System font scale (1.0 = default, 2.0 = 200%). */
    @UsedByGodot
    fun getFontScale(): Float = activity?.resources?.configuration?.fontScale ?: 1f

    /** Animator duration scale; 0 means "Remove animations" is on. */
    @UsedByGodot
    fun getAnimatorDurationScale(): Float {
        val resolver = activity?.contentResolver ?: return 1f
        return Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
    }

    /** True while a screen reader such as TalkBack is exploring by touch. */
    @UsedByGodot
    fun isScreenReaderOn(): Boolean {
        val manager = activity?.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
        return manager?.isTouchExplorationEnabled ?: false
    }

    /** Autoplay scenario from a Game Loop launch (Test Lab or `adb ... --ei scenario N`); 0 otherwise. */
    @UsedByGodot
    fun getLaunchScenario(): Int {
        val intent = activity?.intent ?: return 0
        return if (intent.action == TEST_LOOP) intent.getIntExtra("scenario", 0) else 0
    }

    /** Writes the results file Test Lab passes as the intent's data URI. False if there is none. */
    @UsedByGodot
    fun writeLoopResults(json: String): Boolean {
        val activity = activity ?: return false
        val uri = activity.intent?.takeIf { it.action == TEST_LOOP }?.data ?: return false
        return runCatching {
            activity.contentResolver.openAssetFileDescriptor(uri, "w")?.use { descriptor ->
                FileOutputStream(descriptor.fileDescriptor).use { it.write(json.toByteArray()) }
            } != null
        }.getOrDefault(false)
    }

    /** Ends a Game Loop run: Test Lab waits for the activity to finish. */
    @UsedByGodot
    fun finishLoop() {
        activity?.runOnUiThread { activity?.finish() }
    }

    /** PowerManager thermal status (0 none … 6 shutdown); -1 before Android 10. */
    @UsedByGodot
    fun getThermalStatus(): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return -1
        val power = activity?.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return -1
        return power.currentThermalStatus
    }

    private companion object {
        const val TEST_LOOP = "com.google.intent.action.TEST_LOOP"
    }
}
