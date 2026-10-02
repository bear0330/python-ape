# crc32c 2.7.1 (LGPL-2.1-or-later).
#
# scripts/build-extension.sh links this directory into a superconfigure
# checkout at extensions/crc32c and runs the stock Makefile, so
# DOWNLOAD_SOURCE performs the download, sha256 check, extract, and
# patch -p0. The link exists only while make runs.
#
# The extracted tree is o/extensions/crc32c/crc32c-2.7.1.
# minimal.diff points the package at the builtin _crc32c module.
# This recipe then copies the C sources to native/ and the package to
# python/crc32c, and compiles one static archive per architecture.
# There is no configure step and nothing is installed into cosmos.

CRC32C_SRC := https://files.pythonhosted.org/packages/7f/4c/4e40cc26347ac8254d3f25b9f94710b8e8df24ee4dddc1ba41907a88a94d/crc32c-2.7.1.tar.gz

PKG := extensions/crc32c
TREE := crc32c-2.7.1

ifeq ($(SDK),)
$(error Set SDK to the python-ape SDK directory)
endif

$(eval $(call DOWNLOAD_SOURCE,$(PKG),$(CRC32C_SRC)))

o/$(PKG)/configured.x86_64: CONFIG_COMMAND = $(DUMMYLINK0)
o/$(PKG)/configured.aarch64: CONFIG_COMMAND = $(DUMMYLINK0)

CRC32C_BUILD = \
	set -e && \
	src="$(BASELOC)/o/$(PKG)/$(TREE)/src/crc32c" && \
	dest="$(BASELOC)/$(PKG)" && \
	rm -rf "$$dest/python" "$$dest/native/$$ARCH" && \
	mkdir -p "$$dest/native/$$ARCH" "$$dest/python/crc32c" && \
	cp "$$src/ext/"*.c "$$src/ext/"*.h "$$dest/native/" && \
	cp "$$src/__init__.py" "$$dest/python/crc32c/__init__.py" && \
	cp "$$src/_crc32hash.py" "$$dest/python/crc32c/_crc32hash.py" && \
	cp "$$src/_crc32c.pyi" "$$dest/python/crc32c/_crc32c.pyi" && \
	cp "$$src/py.typed" "$$dest/python/crc32c/py.typed" && \
	for file in _crc32c.c checkarm.c checksse42.c crc32c_adler.c crc32c_arm64.c crc32c_sw.c; do \
		$$CC -c -Os -DPy_BUILD_CORE_BUILTIN \
			-I "$(SDK)/$$ARCH" -I "$(SDK)/include" -I "$$dest/native" \
			-o "$$dest/native/$$ARCH/$${file%.c}.o" "$$dest/native/$$file"; \
	done && \
	/bin/sh $$AR rcs "$$dest/native/$$ARCH/lib_crc32c.a" \
		"$$dest/native/$$ARCH/_crc32c.o" \
		"$$dest/native/$$ARCH/checkarm.o" \
		"$$dest/native/$$ARCH/checksse42.o" \
		"$$dest/native/$$ARCH/crc32c_adler.o" \
		"$$dest/native/$$ARCH/crc32c_arm64.o" \
		"$$dest/native/$$ARCH/crc32c_sw.o"

o/$(PKG)/built.x86_64: BUILD_COMMAND = $(CRC32C_BUILD)
o/$(PKG)/built.aarch64: BUILD_COMMAND = $(CRC32C_BUILD)
