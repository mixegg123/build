#
# Common definition to all platforms
#

BASH ?= bash
ROOT ?= $(shell pwd)/..

BUILD_PATH			?= $(ROOT)/build
LINUX_PATH			?= $(ROOT)/linux
OPTEE_GENDRV_MODULE		?= $(LINUX_PATH)/drivers/tee/optee/optee.ko
GEN_ROOTFS_PATH			?= $(ROOT)/gen_rootfs
GEN_ROOTFS_FILELIST		?= $(GEN_ROOTFS_PATH)/filelist-tee.txt
OPTEE_OS_PATH			?= $(ROOT)/optee_os
OPTEE_CLIENT_PATH		?= $(ROOT)/optee_client
OPTEE_CLIENT_EXPORT		?= $(OPTEE_CLIENT_PATH)/out/export
OPTEE_TEST_PATH			?= $(ROOT)/optee_test
OPTEE_TEST_OUT_PATH 		?= $(ROOT)/optee_test/out
HELLOWORLD_PATH			?= $(ROOT)/hello_world

# default high verbosity. slow uarts shall specify lower if prefered
CFG_TEE_CORE_LOG_LEVEL		?= 3

CCACHE ?= $(shell which ccache) # Don't remove this comment (space is needed)


################################################################################
# Check coherency of compilation mode
################################################################################

ifneq ($(COMPILE_NS_USER),)
ifeq ($(COMPILE_NS_KERNEL),)
$(error COMPILE_NS_KERNEL must be defined as COMPILE_NS_USER=$(COMPILE_NS_USER) is defined)
endif
ifeq (,$(filter $(COMPILE_NS_USER),32 64))
$(error COMPILE_NS_USER=$(COMPILE_NS_USER) - Should be 32 or 64)
endif
endif

ifneq ($(COMPILE_NS_KERNEL),)
ifeq ($(COMPILE_NS_USER),)
$(error COMPILE_NS_USER must be defined as COMPILE_NS_KERNEL=$(COMPILE_NS_KERNEL) is defined)
endif
ifeq (,$(filter $(COMPILE_NS_KERNEL),32 64))
$(error COMPILE_NS_KERNEL=$(COMPILE_NS_KERNEL) - Should be 32 or 64)
endif
endif

ifeq ($(COMPILE_NS_KERNEL),32)
ifneq ($(COMPILE_NS_USER),32)
$(error COMPILE_NS_USER=$(COMPILE_NS_USER) - Should be 32 as COMPILE_NS_KERNEL=$(COMPILE_NS_KERNEL))
endif
endif

ifneq ($(COMPILE_S_USER),)
ifeq ($(COMPILE_S_KERNEL),)
$(error COMPILE_S_KERNEL must be defined as COMPILE_S_USER=$(COMPILE_S_USER) is defined)
endif
ifeq (,$(filter $(COMPILE_S_USER),32 64))
$(error COMPILE_S_USER=$(COMPILE_S_USER) - Should be 32 or 64)
endif
endif

ifneq ($(COMPILE_S_KERNEL),)
OPTEE_OS_COMMON_EXTRA_FLAGS ?= O=out/arm
OPTEE_OS_BIN		    ?= $(OPTEE_OS_PATH)/out/arm/core/tee.bin
ifeq ($(COMPILE_S_USER),)
$(error COMPILE_S_USER must be defined as COMPILE_S_KERNEL=$(COMPILE_S_KERNEL) is defined)
endif
ifeq (,$(filter $(COMPILE_S_KERNEL),32 64))
$(error COMPILE_S_KERNEL=$(COMPILE_S_KERNEL) - Should be 32 or 64)
endif
endif

ifeq ($(COMPILE_S_KERNEL),32)
ifneq ($(COMPILE_S_USER),32)
$(error COMPILE_S_USER=$(COMPILE_S_USER) - Should be 32 as COMPILE_S_KERNEL=$(COMPILE_S_KERNEL))
endif
endif


################################################################################
# set the compiler when COMPILE_xxx are defined
################################################################################
CROSS_COMPILE_NS_USER   ?= "$(CCACHE)$(AARCH$(COMPILE_NS_USER)_CROSS_COMPILE)"
CROSS_COMPILE_NS_KERNEL ?= "$(CCACHE)$(AARCH$(COMPILE_NS_KERNEL)_CROSS_COMPILE)"
CROSS_COMPILE_S_USER    ?= "$(CCACHE)$(AARCH$(COMPILE_S_USER)_CROSS_COMPILE)"
CROSS_COMPILE_S_KERNEL  ?= "$(CCACHE)$(AARCH$(COMPILE_S_KERNEL)_CROSS_COMPILE)"

ifeq ($(COMPILE_S_USER),32)
OPTEE_OS_TA_DEV_KIT_DIR	?= $(OPTEE_OS_PATH)/out/arm/export-ta_arm32
endif
ifeq ($(COMPILE_S_USER),64)
OPTEE_OS_TA_DEV_KIT_DIR	?= $(OPTEE_OS_PATH)/out/arm/export-ta_arm64
endif

ifeq ($(COMPILE_S_KERNEL),64)
OPTEE_OS_COMMON_EXTRA_FLAGS	+= CFG_ARM64_core=y
endif


################################################################################
# defines, macros, configuration etc
################################################################################
define KERNEL_VERSION
$(shell cd $(LINUX_PATH) && $(MAKE) --no-print-directory kernelversion)
endef
DEBUG ?= 0

################################################################################
# default target is all
################################################################################
all:

################################################################################
# Busybox
################################################################################
BUSYBOX_COMMON_TARGET		?= TOBEDEFINED
BUSYBOX_CLEAN_COMMON_TARGET	?= TOBEDEFINED

busybox-common: linux
	cd $(GEN_ROOTFS_PATH) &&  \
		CROSS_COMPILE=$(CROSS_COMPILE_NS_USER) \
		PATH=${PATH}:$(LINUX_PATH)/usr \
		$(GEN_ROOTFS_PATH)/generate-cpio-rootfs.sh \
			$(BUSYBOX_COMMON_TARGET)

busybox-clean-common:
	cd $(GEN_ROOTFS_PATH) && \
	$(GEN_ROOTFS_PATH)/generate-cpio-rootfs.sh  \
		$(BUSYBOX_CLEAN_COMMON_TARGET)

busybox-cleaner-common:
	rm -rf $(GEN_ROOTFS_PATH)/build
	rm -rf $(GEN_ROOTFS_PATH)/filelist-final.txt

################################################################################
# Linux
################################################################################
LINUX_COMMON_FLAGS ?= LOCALVERSION= CROSS_COMPILE=$(CROSS_COMPILE_NS_KERNEL)

linux-common: linux-defconfig
	$(MAKE) -C $(LINUX_PATH) $(LINUX_COMMON_FLAGS)

$(LINUX_PATH)/.config: $(LINUX_DEFCONFIG_COMMON_FILES)
	cd $(LINUX_PATH) && \
		ARCH=$(LINUX_DEFCONFIG_COMMON_ARCH) \
		scripts/kconfig/merge_config.sh $(LINUX_DEFCONFIG_COMMON_FILES)

linux-defconfig-clean-common:
	rm -f $(LINUX_PATH)/.config

# LINUX_CLEAN_COMMON_FLAGS can be defined in specific makefiles (hikey.mk,...)
# if necessary

linux-clean-common: linux-defconfig-clean
	$(MAKE) -C $(LINUX_PATH) $(LINUX_CLEAN_COMMON_FLAGS) clean

# LINUX_CLEANER_COMMON_FLAGS can be defined in specific makefiles (hikey.mk,...)
# if necessary

linux-cleaner-common: linux-defconfig-clean
	$(MAKE) -C $(LINUX_PATH) $(LINUX_CLEANER_COMMON_FLAGS) distclean

################################################################################
# EDK2 / Tianocore
################################################################################
# Make sure edksetup.sh only will be called once and that we don't rebuild
# BaseTools again and again.
$(EDK2_PATH)/Conf/target.txt:
	set -e && cd $(EDK2_PATH) && $(BASH) edksetup.sh && \
	$(MAKE) -j1 -C $(EDK2_PATH)/BaseTools

edk2-common: $(EDK2_PATH)/Conf/target.txt
	set -e && cd $(EDK2_PATH) && $(BASH) edksetup.sh && \
	$(call edk2-call)

edk2-clean-common:
	set -e && cd $(EDK2_PATH) && $(BASH) edksetup.sh && \
	$(call edk2-call) clean && \
	$(MAKE) -j1 -C $(EDK2_PATH)/BaseTools clean && \
	rm -f $(EDK2_PATH)/Conf/target.txt

################################################################################
# OP-TEE
################################################################################
OPTEE_OS_COMMON_FLAGS ?= \
	$(OPTEE_OS_COMMON_EXTRA_FLAGS) \
	CROSS_COMPILE=$(CROSS_COMPILE_S_USER) \
	CROSS_COMPILE_core=$(CROSS_COMPILE_S_KERNEL) \
	CROSS_COMPILE_ta_arm64=$(AARCH64_CROSS_COMPILE) \
	CROSS_COMPILE_ta_arm32=$(AARCH32_CROSS_COMPILE) \
	CFG_TEE_CORE_LOG_LEVEL=$(CFG_TEE_CORE_LOG_LEVEL) \
	DEBUG=$(DEBUG)

optee-os-common:
	$(MAKE) -C $(OPTEE_OS_PATH) $(OPTEE_OS_COMMON_FLAGS)

OPTEE_OS_CLEAN_COMMON_FLAGS ?= $(OPTEE_OS_COMMON_EXTRA_FLAGS)

optee-os-clean-common: xtest-clean helloworld-clean
	$(MAKE) -C $(OPTEE_OS_PATH) $(OPTEE_OS_CLEAN_COMMON_FLAGS) clean

OPTEE_CLIENT_COMMON_FLAGS ?= CROSS_COMPILE=$(CROSS_COMPILE_NS_USER)

optee-client-common:
	$(MAKE) -C $(OPTEE_CLIENT_PATH) $(OPTEE_CLIENT_COMMON_FLAGS)

# OPTEE_CLIENT_CLEAN_COMMON_FLAGS can be defined in specific makefiles
# (hikey.mk,...) if necessary

optee-client-clean-common:
	$(MAKE) -C $(OPTEE_CLIENT_PATH) $(OPTEE_CLIENT_CLEAN_COMMON_FLAGS) \
		clean

################################################################################
# xtest / optee_test
################################################################################
XTEST_COMMON_FLAGS ?= CROSS_COMPILE_HOST=$(CROSS_COMPILE_NS_USER)\
	CROSS_COMPILE_TA=$(CROSS_COMPILE_S_USER) \
	TA_DEV_KIT_DIR=$(OPTEE_OS_TA_DEV_KIT_DIR) \
	OPTEE_CLIENT_EXPORT=$(OPTEE_CLIENT_EXPORT) \
	COMPILE_NS_USER=$(COMPILE_NS_USER) \
	O=$(OPTEE_TEST_OUT_PATH)

xtest-common: optee-os optee-client
	$(MAKE) -C $(OPTEE_TEST_PATH) $(XTEST_COMMON_FLAGS)

XTEST_CLEAN_COMMON_FLAGS ?= TA_DEV_KIT_DIR=$(OPTEE_OS_TA_DEV_KIT_DIR)

xtest-clean-common:
	$(MAKE) -C $(OPTEE_TEST_PATH) $(XTEST_CLEAN_COMMON_FLAGS) clean

XTEST_PATCH_COMMON_FLAGS ?= $(XTEST_COMMON_FLAGS)

xtest-patch-common:
	$(MAKE) -C $(OPTEE_TEST_PATH) $(XTEST_PATCH_COMMON_FLAGS) patch

################################################################################
# hello_world
################################################################################
HELLOWORLD_COMMON_FLAGS ?= HOST_CROSS_COMPILE=$(CROSS_COMPILE_NS_USER)\
	TA_CROSS_COMPILE=$(CROSS_COMPILE_S_USER) \
	TA_DEV_KIT_DIR=$(OPTEE_OS_TA_DEV_KIT_DIR) \
	TEEC_EXPORT=$(OPTEE_CLIENT_EXPORT)

helloworld-common: optee-os optee-client
	$(MAKE) -C $(HELLOWORLD_PATH) $(HELLOWORLD_COMMON_FLAGS)

HELLOWORLD_CLEAN_COMMON_FLAGS ?= TA_DEV_KIT_DIR=$(OPTEE_OS_TA_DEV_KIT_DIR)

helloworld-clean-common:
	$(MAKE) -C $(HELLOWORLD_PATH) $(HELLOWORLD_CLEAN_COMMON_FLAGS) clean

################################################################################
# rootfs
################################################################################
update_rootfs-common: busybox filelist-tee
	cat $(GEN_ROOTFS_PATH)/filelist-final.txt > $(GEN_ROOTFS_PATH)/filelist.tmp
	cat $(GEN_ROOTFS_FILELIST) >> $(GEN_ROOTFS_PATH)/filelist.tmp
	cd $(GEN_ROOTFS_PATH) && \
	        $(LINUX_PATH)/usr/gen_init_cpio $(GEN_ROOTFS_PATH)/filelist.tmp | \
			gzip > $(GEN_ROOTFS_PATH)/filesystem.cpio.gz

update_rootfs-clean-common:
	rm -f $(GEN_ROOTFS_PATH)/filesystem.cpio.gz
	rm -f $(GEN_ROOTFS_PATH)/filelist-all.txt
	rm -f $(GEN_ROOTFS_PATH)/filelist-tmp.txt
	rm -f $(GEN_ROOTFS_FILELIST)

filelist-tee-common: fl:=$(GEN_ROOTFS_FILELIST)
filelist-tee-common: optee-client xtest helloworld
	@echo "# filelist-tee-common /start" 				> $(fl)
	@echo "dir /lib/optee_armtz 755 0 0" 				>> $(fl)
	@echo "# xtest / optee_test" 					>> $(fl)
	@find $(OPTEE_TEST_OUT_PATH) -type f -name "xtest" | \
		sed 's/\(.*\)/file \/bin\/xtest \1 755 0 0/g' 		>> $(fl)
	@find $(OPTEE_TEST_OUT_PATH) -name "*.ta" | \
		sed 's/\(.*\)\/\(.*\)/file \/lib\/optee_armtz\/\2 \1\/\2 444 0 0/g' \
									>> $(fl)
	@if [ -e $(HELLOWORLD_PATH)/host/hello_world ]; then \
		echo "file /bin/hello_world" \
			"$(HELLOWORLD_PATH)/host/hello_world 755 0 0"	>> $(fl); \
		echo "file /lib/optee_armtz/8aaaf200-2450-11e4-abe20002a5d5c51b.ta" \
			"$(HELLOWORLD_PATH)/ta/8aaaf200-2450-11e4-abe20002a5d5c51b.ta" \
			"444 0 0" 					>> $(fl); \
	fi
	@echo "# Secure storage dir" 					>> $(fl)
	@echo "dir /data 755 0 0" 					>> $(fl)
	@echo "dir /data/tee 755 0 0" 					>> $(fl)
	@if [ -e $(OPTEE_GENDRV_MODULE) ]; then \
		echo "# OP-TEE device" 					>> $(fl); \
		echo "dir /lib/modules 755 0 0" 			>> $(fl); \
		echo "dir /lib/modules/$(call KERNEL_VERSION) 755 0 0" \
									>> $(fl); \
		echo "file /lib/modules/$(call KERNEL_VERSION)/optee.ko" \
			"$(OPTEE_GENDRV_MODULE) 755 0 0" \
									>> $(fl); \
	fi
	@echo "# OP-TEE Client" 					>> $(fl)
	@echo "file /bin/tee-supplicant $(OPTEE_CLIENT_EXPORT)/bin/tee-supplicant 755 0 0" \
									>> $(fl)
	@echo "file /lib/libteec.so.1.0 $(OPTEE_CLIENT_EXPORT)/lib/libteec.so.1.0 755 0 0" \
									>> $(fl)
	@echo "slink /lib/libteec.so.1 libteec.so.1.0 755 0 0"			>> $(fl)
	@echo "slink /lib/libteec.so libteec.so.1 755 0 0" 			>> $(fl)
	@if [ -e $(OPTEE_CLIENT_EXPORT)/lib/libsqlfs.so.1.0 ]; then \
		echo "file /lib/libsqlfs.so.1.0" \
			"$(OPTEE_CLIENT_EXPORT)/lib/libsqlfs.so.1.0 755 0 0" \
									>> $(fl); \
		echo "slink /lib/libsqlfs.so.1 libsqlfs.so.1.0 755 0 0" >> $(fl); \
		echo "slink /lib/libsqlfs.so libsqlfs.so.1 755 0 0" 	>> $(fl); \
	fi
	@echo "# filelist-tee-common /end"				>> $(fl)
