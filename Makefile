B = sql

include pgxntool/base.mk

LT95		 = $(call test, $(MAJORVER), -lt, 95)
LT93		 = $(call test, $(MAJORVER), -lt, 93)

$B:
	@mkdir -p $@

installcheck: $B/cat_tools.sql
EXTRA_CLEAN += $B/cat_tools.sql
$B/cat_tools.sql: sql/cat_tools.in.sql pgxntool/safesed
	(echo @generated@ && cat $< && echo @generated@) | sed -e 's#@generated@#-- GENERATED FILE! DO NOT EDIT! See $<#' > $@
ifeq ($(LT95),yes)
	pgxntool/safesed $@ -E -e 's/(.*)-- SED: REQUIRES 9.5!/-- Requires 9.5: \1/'
endif
ifeq ($(LT93),yes)
	pgxntool/safesed $@ -E -e 's/(.*)-- SED: REQUIRES 9.3!/-- Requires 9.3: \1/'
endif

