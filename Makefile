TESTS_DIR := tests
MINIMAL_INIT := tests/minimal_init.lua

.PHONY: test test-diff test-store test-viewer test-panel test-actions test-init test-inline-diff test-scalability

# Run all tests
test:
	nvim --headless -u $(MINIMAL_INIT) \
		-c "PlenaryBustedDirectory $(TESTS_DIR)/ {minimal_init = '$(MINIMAL_INIT)'}"

# Run only diff tests
test-diff:
	nvim --headless -u $(MINIMAL_INIT) \
		-c "PlenaryBustedFile $(TESTS_DIR)/diff_spec.lua"

# Run only store tests
test-store:
	nvim --headless -u $(MINIMAL_INIT) \
		-c "PlenaryBustedFile $(TESTS_DIR)/store_spec.lua"

# Run only viewer tests
test-viewer:
	nvim --headless -u $(MINIMAL_INIT) \
		-c "PlenaryBustedFile $(TESTS_DIR)/viewer_spec.lua"

# Run only panel tests
test-panel:
	nvim --headless -u $(MINIMAL_INIT) \
		-c "PlenaryBustedFile $(TESTS_DIR)/panel_spec.lua"

# Run only actions tests
test-actions:
	nvim --headless -u $(MINIMAL_INIT) \
		-c "PlenaryBustedFile $(TESTS_DIR)/actions_spec.lua"

# Run only init tests
test-init:
	nvim --headless -u $(MINIMAL_INIT) \
		-c "PlenaryBustedFile $(TESTS_DIR)/init_spec.lua"

# Run only inline diff tests
test-inline-diff:
	nvim --headless -u $(MINIMAL_INIT) \
		-c "PlenaryBustedFile $(TESTS_DIR)/inline_diff_spec.lua"

# Run only scalability tests
test-scalability:
	nvim --headless -u $(MINIMAL_INIT) \
		-c "PlenaryBustedFile $(TESTS_DIR)/scalability_spec.lua"
