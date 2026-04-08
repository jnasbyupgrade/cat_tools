EXTENSION_cat_tools_VERSION := 0.2.2
$(EXTENSION_cat_tools_VERSION_FILE): sql/cat_tools.sql cat_tools.control
	@echo '/* DO NOT EDIT - AUTO-GENERATED FILE */' > $(EXTENSION_cat_tools_VERSION_FILE)
	@cat sql/cat_tools.sql >> $(EXTENSION_cat_tools_VERSION_FILE)

