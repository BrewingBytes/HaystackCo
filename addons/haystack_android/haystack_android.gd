@tool
extends EditorPlugin

var _export_plugin: AndroidExportPlugin


func _enter_tree() -> void:
	_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	const PLUGIN_NAME := "HaystackHelpers"
	const TEMPLATE_MANIFEST := "res://android/build/src/main/AndroidManifest.xml"
	## Godot's template leaves these out, so changing the system font size or bold text
	## recreates the activity and Godot force-quits. Handled in place, a11y.gd re-reads on resume.
	const EXTRA_CONFIG_CHANGES := ["fontScale", "fontWeightAdjustment"]
	## Back up the save (eng D10). The rule files ship in the helper AAR's res/xml; allowBackup
	## itself comes from the preset's user_data_backup/allow (Godot writes the release manifest).
	const BACKUP_ATTRIBUTES := {
		"android:dataExtractionRules": "@xml/haystack_data_extraction_rules",
		"android:fullBackupContent": "@xml/haystack_backup_rules",
	}

	const NATIVE_LIBRARY := "res://addons/haystack_native/bin/libhaystack_native.android.arm64.so"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		if not get_export_platform() is EditorExportPlatformAndroid:
			return
		_patch_config_changes()
		_patch_backup_rules()
		# Godot packs an empty file when a GDExtension library is missing, and the app then falls
		# back to GDScript at runtime. Say so here; tools/check_16kb.sh fails the AAB on it.
		if not FileAccess.file_exists(NATIVE_LIBRARY) or FileAccess.get_file_as_bytes(NATIVE_LIBRARY).is_empty():
			push_error("haystack_android: %s is missing or empty; build native/ for Android first (README)" % NATIVE_LIBRARY)

	## The /android/ build template is regenerated on install, so patch it on every export.
	func _patch_config_changes() -> void:
		if not FileAccess.file_exists(TEMPLATE_MANIFEST):
			push_error("haystack_android: %s missing; install the Android build template" % TEMPLATE_MANIFEST)
			return
		var xml := FileAccess.get_file_as_string(TEMPLATE_MANIFEST)
		var regex := RegEx.create_from_string('android:configChanges="([^"]*)"')
		var found := regex.search(xml)
		if found == null:
			push_error("haystack_android: no android:configChanges in %s" % TEMPLATE_MANIFEST)
			return
		var changes := found.get_string(1).split("|")
		var missing := EXTRA_CONFIG_CHANGES.filter(func(c: String) -> bool: return not changes.has(c))
		if missing.is_empty():
			return
		changes.append_array(PackedStringArray(missing))
		xml = xml.substr(0, found.get_start(1)) + "|".join(changes) + xml.substr(found.get_end(1))
		var file := FileAccess.open(TEMPLATE_MANIFEST, FileAccess.WRITE)
		file.store_string(xml)
		file.close()

	func _patch_backup_rules() -> void:
		if not FileAccess.file_exists(TEMPLATE_MANIFEST):
			return  # _patch_config_changes reported it
		var xml := FileAccess.get_file_as_string(TEMPLATE_MANIFEST)
		var at := xml.find("<application")
		if at < 0:
			push_error("haystack_android: no <application> in %s" % TEMPLATE_MANIFEST)
			return
		var added := ""
		for attribute: String in BACKUP_ATTRIBUTES:
			if not xml.contains(attribute + "="):
				added += '\n        %s="%s"' % [attribute, BACKUP_ATTRIBUTES[attribute]]
		if added.is_empty():
			return
		at += "<application".length()
		xml = xml.substr(0, at) + added + xml.substr(at)
		var file := FileAccess.open(TEMPLATE_MANIFEST, FileAccess.WRITE)
		file.store_string(xml)
		file.close()

	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var variant := "debug" if debug else "release"
		return PackedStringArray(["haystack_android/bin/haystack-helpers-%s.aar" % variant])

	func _get_name() -> String:
		return PLUGIN_NAME
