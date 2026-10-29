extends GutTest


func test_defaults_off_android() -> void:
	assert_eq(A11y.font_scale(), 1.0)
	assert_false(A11y.system_reduce_motion())
	assert_false(A11y.screen_reader_on())
