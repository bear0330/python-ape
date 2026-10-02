# MarkupSafe 3.0.3.
#
# scripts/build-extension.sh links this directory into a superconfigure
# checkout at extensions/markupsafe and runs the stock Makefile, so
# DOWNLOAD_SOURCE performs the download, sha256 check, extract, and
# patch -p0. The link exists only while make runs.
#
# The extracted tree is o/extensions/markupsafe/markupsafe-3.0.3.
# minimal.diff renames the C module to the builtin _markupsafe__speedups.
# This recipe then copies the C file to native/ and the package to
# python/markupsafe, and compiles one static archive per architecture.
# There is no configure step and nothing is installed into cosmos.

MARKUPSAFE_SRC := https://files.pythonhosted.org/packages/7e/99/7690b6d4034fffd95959cbe0c02de8deb3098cc577c67bb6a24fe5d7caa7/markupsafe-3.0.3.tar.gz

PKG := extensions/markupsafe
TREE := markupsafe-3.0.3

ifeq ($(SDK),)
$(error Set SDK to the python-ape SDK directory)
endif

$(eval $(call DOWNLOAD_SOURCE,$(PKG),$(MARKUPSAFE_SRC)))

o/$(PKG)/configured.x86_64: CONFIG_COMMAND = $(DUMMYLINK0)
o/$(PKG)/configured.aarch64: CONFIG_COMMAND = $(DUMMYLINK0)

MARKUPSAFE_BUILD = \
	src="$(BASELOC)/o/$(PKG)/$(TREE)/src/markupsafe" && \
	dest="$(BASELOC)/$(PKG)" && \
	rm -rf "$$dest/python" "$$dest/native/$$ARCH" && \
	mkdir -p "$$dest/native/$$ARCH" "$$dest/python/markupsafe" && \
	cp "$$src/_speedups.c" "$$dest/native/_speedups.c" && \
	cp "$$src/__init__.py" "$$dest/python/markupsafe/__init__.py" && \
	cp "$$src/_native.py" "$$dest/python/markupsafe/_native.py" && \
	cp "$$src/_speedups.pyi" "$$dest/python/markupsafe/_speedups.pyi" && \
	cp "$$src/py.typed" "$$dest/python/markupsafe/py.typed" && \
	$$CC -c -Os -DPy_BUILD_CORE_BUILTIN \
		-I "$(SDK)/$$ARCH" -I "$(SDK)/include" \
		-o "$$dest/native/$$ARCH/_speedups.o" "$$dest/native/_speedups.c" && \
	/bin/sh $$AR rcs "$$dest/native/$$ARCH/lib_markupsafe__speedups.a" \
		"$$dest/native/$$ARCH/_speedups.o"

o/$(PKG)/built.x86_64: BUILD_COMMAND = $(MARKUPSAFE_BUILD)
o/$(PKG)/built.aarch64: BUILD_COMMAND = $(MARKUPSAFE_BUILD)
