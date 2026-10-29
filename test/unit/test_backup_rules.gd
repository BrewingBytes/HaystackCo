extends GutTest
## G6 / eng D10: Android backs up the save (primary + backup copy) and leaves quarantined files
## behind. Ties the rule files in the helper AAR to SaveStore's real paths, and checks both
## presets let Android back up at all.

const RULES_DIR := "res://plugins/android/haystack_helpers/src/main/res/xml/"
const EXTRACTION := RULES_DIR + "haystack_data_extraction_rules.xml"
const FULL_BACKUP := RULES_DIR + "haystack_backup_rules.xml"


## Section tag → [[include|exclude, domain, path], ...] in file order.
func _rules(path: String) -> Dictionary:
	var parser := XMLParser.new()
	assert_eq(parser.open(path), OK, path)
	var sections := {}
	var section := ""
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		var tag := parser.get_node_name()
		if tag in ["cloud-backup", "device-transfer", "full-backup-content"]:
			section = tag
			sections[section] = []
		elif tag in ["include", "exclude"]:
			sections[section].append([tag, parser.get_named_attribute_value_safe("domain"), parser.get_named_attribute_value_safe("path")])
	return sections


## Godot's user:// is the app's files dir on Android, so user://save/x is file-domain save/x.
func _android_path(user_path: String) -> String:
	return user_path.trim_prefix("user://") + "/"


func test_every_section_backs_up_the_save_and_skips_quarantine() -> void:
	var store := SaveStore.new()
	var save_dir := _android_path(store.dir)
	var quarantine := _android_path(store.dir.path_join(SaveStore.QUARANTINE))
	var expected := [["include", "file", save_dir], ["exclude", "file", quarantine]]
	var extraction := _rules(EXTRACTION)
	assert_eq(extraction.keys(), ["cloud-backup", "device-transfer"])
	for section: String in extraction:
		assert_eq(extraction[section], expected, section)
	assert_eq(_rules(FULL_BACKUP), {"full-backup-content": expected})


func test_both_presets_allow_backup() -> void:
	var presets := ConfigFile.new()
	assert_eq(presets.load("res://export_presets.cfg"), OK)
	for section in presets.get_sections():
		if section.ends_with(".options"):
			assert_eq(presets.get_value(section, "user_data_backup/allow", false), true, section)
