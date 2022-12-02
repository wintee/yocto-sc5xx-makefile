# Copyright David Gibson (Wintee@gmail.com) 2022 All Rights Reserved
# Makefile to assist in using Yocto Linux on Analog Devices ADSP-SC5xx processors
# All instructions are based on the offical ADI documentation which can be found at:
# https://wiki.analog.com/resources/tools-software/linuxdsp

# WARNING: This Makefile is tested using the recommended OS: Ubuntu 20.04 LTS
# Using other flavours of Linux might throw up gotchas. Especially around the correct version of Python

# Things that you may wish to configure
# It is assumed that this Makefile resides at the top level of your workspace

TARGET_PROC=sc598
TARGET_BOARD=som-ezkit
ADI_YOCTO_VERSION=2.1.0
REPO_URL=https://github.com/analogdevicesinc/lnxdsp-repo-manifest.git
SETUP_TARGET=adsp-$(TARGET_PROC)-$(TARGET_BOARD)
REPO_BRANCH=release/yocto-$(ADI_YOCTO_VERSION)
XML_FILE=release-yocto-$(ADI_YOCTO_VERSION).xml
# If you change the TFTP directory, update the .tftpd-hpa file and run configure_tftp (again)
TFTPDIR=/tftpboot
# If you change the NFS directory, update the .exports file and run configure_nfsboot (again)
NFSDIR=/romfs
DEFAULT_TTY=ttyUSB0
# ICE ICE BABY
ICE_DEVICE=ice2000

# Things that you probably want to leave as they are
# CCES Version is defined in the wiki documentation
CCES_VER=2.11.0
CCES_PACKAGE=adi-CrossCoreEmbeddedStudio-linux-x86-${CCES_VER}.deb
CCES_URL=https://download.analog.com/tools/CrossCoreEmbeddedStudio/Releases/Release_${CCES_VER}/${CCES_PACKAGE}
CCES_PATH=/opt/analog/cces/${CCES_VER}
YOCTO_PACKAGE_LIST=gawk wget git-core diffstat unzip texinfo gcc-multilib build-essential chrpath socat libsdl1.2-dev xterm u-boot-tools openssl curl tftpd-hpa python
MINICOM_PACKAGE_LIST=minicom
CCES_PACKAGE_LIST=lib32z1
NFS_PACKAGE_LIST=nfs-kernel-server
PACKAGE_LIST=${YOCTO_PACKAGE_LIST} ${MINICOM_PACKAGE_LIST} ${CCES_PACKAGE_LIST} ${NFS_PACKAGE_LIST}
SHELL=/bin/bash
TOPDIR=$(CWD)
DEPLOY_DIR=build/tmp/deploy/images/$(SETUP_TARGET)

default:
	@echo "I do nothing by default"
	@echo "You might want to try the following:"
	@echo "[run once] make setup_host_pc - set up a new development machine"
	@echo "[run once] make setup_dev_space - set up a new development environment"

# Commands to set up your development environment

install_packages:
	sudo apt-get update
	sudo apt install -y ${PACKAGE_LIST}

install_cces:
	rm -f ./${CCES_PACKAGE}
	wget $(CCES_URL)
	sudo dpkg -i ./${CCES_PACKAGE}

configure_tftp:
	@echo "WARNING: I am going to clobber your current TFTP configuration. Stop me now if you care about this."
	@echo "If you don't use TFTP for anything else then this is probably OK."
	sleep 5
	sudo cp .tftpd-hpa /etc/default/tftpd-hpa
	sudo mkdir -p $(TFTPDIR)
	sudo chmod 777 $(TFTPDIR)
	sudo service tftpd-hpa restart

configure_minicom:
	@echo "WARNING: I am going to clobber your current default minicom configuration. Stop me now if you care about this."
	@echo "If you don't use minicom for anything else then this is probably OK."
	@echo "Note: If minicom doesn't work for you, it might be that you need to choose a different /dev/ttyUSB port."
	sleep 5
	sudo chmod a+wx /etc/minicom/minirc.dfl
	sudo cat .minirc.dfl >> /etc/minicom/minirc.dfl
	
configure_nfsboot:
	@echo "WARNING: I am going to clobber your current default nfs configuration. Stop me now if you care about this."
	@echo "If you don't use nfs for anything else then this is probably OK."
	sleep 5
	sudo cat .exports >> /etc/exports
	sudo mkdir -p $(NFSDIR)
	sudo chmod 777 $(NFSDIR)
	sudo service nfs-kernel-server start

setup_host_pc: install_packages install_cces configure_tftp configure_minicom

# Rules to set up the development workspace on the host PC

install_repo:
	mkdir -p  bin
	curl http://commondatastorage.googleapis.com/git-repo-downloads/repo > ./bin/repo
	chmod a+x ./bin/repo

clobber_repo:
	rm -rf bin/repo .repo

init_repo:
	./bin/repo init -u $(REPO_URL) -b $(REPO_BRANCH) -m $(XML_FILE)

sync_repo:
	./bin/repo sync

setup_repo: install_repo init_repo sync_repo

clobber_yocto:
	rm -f setup-environment
	rm -rf downloads build sources

nuke_all: clobber_repo clobber_yocto

setup_dev_space: setup_repo

# Rules to build Linux
# There are three supported sets of binaries that can be built:
# minimal - A cut size image that is able to fit in OSPI
# ramdisk - A mid size image used for NFS boot or TFTP boot
# full - A full size image used for NFS boot or TFTP boot

build_common:
	source setup-environment -m $(SETUP_TARGET) && bitbake $(BITBAKE_TARGET)

build_minimal: BITBAKE_TARGET = adsp-sc5xx-minimal
build_minimal: build_common

build_ramdisk: BITBAKE_TARGET = adsp-sc5xx-ramdisk
build_ramdisk: build_common

build_full: BITBAKE_TARGET = adsp-sc5xx-full
build_full: build_common

install_common:
	cp $(DEPLOY_DIR)/u-boot-proper-$(TARGET_PROC)-$(TARGET_BOARD).elf $(TFTPDIR)

install_minimal: install_common
	cp $(DEPLOY_DIR)/stage1-boot.ldr $(TFTPDIR)
	cp $(DEPLOY_DIR)/stage2-boot.ldr $(TFTPDIR)
	cp $(DEPLOY_DIR)/fitImage $(TFTPDIR)
	cp $(DEPLOY_DIR)/adsp-sc5xx-minimal-adsp-$(TARGET_PROC)-$(TARGET_BOARD).jffs2 $(TFTPDIR)

install_ramdisk_full_common:
	cp $(DEPLOY_DIR)/Image $(TFTPDIR)
	cp $(DEPLOY_DIR)/$(TARGET_PROC)-$(TARGET_PROC).dtb $(TFTPDIR)

install_ramdisk: install_common
	cp $(DEPLOY_DIR)/adsp-sc5xx-ramdisk-adsp-$(TARGET_PROC)-$(TARGET_PROC).cpio.xz.u-boot $(TFTPDIR)/ramdisk.cpio.xz.u-boot

# Full is TBD
install_full: install_common
	cp $(DEPLOY_DIR)/adsp-sc5xx-ramdisk-adsp-$(TARGET_PROC)-$(TARGET_PROC).cpio.xz.u-boot $(TFTPDIR)/ramdisk.cpio.xz.u-boot

# install_nfs is only supported in this makefile after a full build
# this rule extracts the filesystem contents into the mountable romfs directory
# If you want to use it with ramboot, hack the command below.
install_nfs:
	sudo tar -xf $(DEPLOY_DIR)/adsp-sc5xx-full-adsp-$(TARGET_PROC)-$(TARGET_BOARD).tar.xz -C $(NFSDIR)

