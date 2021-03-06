#!/bin/bash

set -e

if (($# != 4 && $# != 5)); then
	echo "usage: <output file name> <image size> <partition type> <layout> [files]"
	echo "Supported partition types:"
	echo -e "\t- fat16"
	echo -e "\t- fat32"
	echo -e "\t- ext2"
	echo -e "\t- ext3"
	echo -e "\t- ext4\n"
	echo "Supported layouts:"
	echo -e "\t- dos - MBR image with GRUB 2 for legacy BIOS"
	echo -e "\t- gpt - GPT image with GRUB 2 for legacy BIOS"
	echo -e "\t- x86_64-efi - GPT image with GRUB 2 for UEFI"
	echo -e "\t- x86_64-efi-hybrid - GPT image with GRUB 2 for both UEFI and legacy BIOS"
	echo -e "\t- gpt-limine - GPT image with limine for legacy BIOS"
	echo -e "\t- gpt-tomatboot - GPT image with TomatBoot for UEFI"
	echo -e "\t- gpt-stivale-hybrid - GPT image with limine for legacy BIOS and TomatBoot for UEFI\n"
	exit -1
fi

dos_parttype=""
case "$3" in
	"fat16" )
		dos_parttype="0e";;
	"fat32" )
		dos_parttype="0c";;
	"ext2" )
		dos_parttype="83";;
	"ext3" )
		dos_parttype="83";;
	"ext4" )
		dos_parttype="83";;
	* )
		echo "unsupported partition type";
		exit -2;;
esac

rootpart=""
case "$4" in
	"dos" | "gpt-limine" )
		rootpart="p1"
		;;
	"gpt" | "x86_64-efi" | "gpt-tomatboot" | "gpt-stivale-hybrid" )
		rootpart="p2"
		;;
	"x86_64-efi-hybrid" )
		rootpart="p3"
		;;
	* )
		echo "unexpected partition table layout";
		exit -2;;
esac

# UUID of Windows data partition. Choose something else depending on your needs.
gpt_type=${GPT_TYPE:="EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"}

rm -f $1
fallocate -l $2 $1

lodev=$(sudo losetup -f --show $1)

case "$4" in
	"dos" )
		# For DOS layouts, install GRUB's boot code after the MBR.
		cat << END_SFDISK | sudo sfdisk --no-tell-kernel $lodev
label: dos
16MiB + $dos_parttype
END_SFDISK
		;;
	"gpt" )
		# For GPT layouts, install GRUB's boot code to a "BIOS boot partition".
		# GRUB will use the entire partition in this case.
		cat << END_SFDISK | sudo sfdisk --no-tell-kernel $lodev
label: gpt
- 16MiB 21686148-6449-6E6F-744E-656564454649
- +     $gpt_type
END_SFDISK
		;;
	"gpt-limine" )
		# For GPT layouts, limine's boot code is embedded in GPT structures.
		cat << END_SFDISK | sudo sfdisk --no-tell-kernel $lodev
label: gpt
- +     $gpt_type
END_SFDISK
		;;
	"x86_64-efi" | "gpt-tomatboot" | "gpt-stivale-hybrid" )
		# For GPT layouts, install GRUB's/tomatboot's boot code to the EFI system partition.
		# GRUB will create a file on that partition.
		cat << END_SFDISK | sudo sfdisk --no-tell-kernel $lodev
label: gpt
- 512MiB C12A7328-F81F-11D2-BA4B-00A0C93EC93B
- +      $gpt_type
END_SFDISK
		;;
	"x86_64-efi-hybrid" )
		# Combined GRUB EFI + GRUB legacy layout
		cat << END_SFDISK | sudo sfdisk --no-tell-kernel $lodev
label: gpt
- 16MiB C12A7328-F81F-11D2-BA4B-00A0C93EC93B
- 16MiB 21686148-6449-6E6F-744E-656564454649
- +     $gpt_type
END_SFDISK
		;;
	* )
		echo "unexpected partition table layout, how did we get here?";
		exit -2;;
esac

sudo losetup -d $lodev
lodev=$(sudo losetup -Pf --show $1)

# Format root partition according to user-chosen type.
case "$3" in
	"fat16" )
		sudo mkfs.vfat -F 16 $lodev$rootpart;;
	"fat32" )
		sudo mkfs.vfat -F 32 $lodev$rootpart;;
	"ext2" )
		sudo mkfs.ext2 $lodev$rootpart;;
	"ext3" )
		sudo mkfs.ext3 $lodev$rootpart;;
	"ext4" )
		sudo mkfs.ext4 $lodev$rootpart;;
	* )
		echo "unsupported partition type, how did we get here?";
		exit -3;;
esac

mountpoint=$(mktemp -d)
echo "tmp mountpoint is $mountpoint"
sudo mount $lodev$rootpart $mountpoint

sudo mkdir $mountpoint/boot

case "$4" in
	"dos" | "gpt" | "x86_64-efi-hybrid" )
		# i386-pc makes GRUB use the MBR or BIOS boot partition for its boot code,
		# depending on the partition table type.
		# Note that we do not have to partition the BIOS boot partition.
		sudo grub-install --target=i386-pc --boot-directory=$mountpoint/boot $lodev
		;;&
	"gpt-limine" | "gpt-stivale-hybrid" )
		# Use installed limine-install if available
		LIMINE_INSTALL="limine-install"
		if ! command -v "$LIMINE_INSTALL" &> /dev/null
		then
			if [ -d limine ]; then
				rm -rf limine
			fi

			git clone https://github.com/limine-bootloader/limine.git --branch=v1.0-branch --depth=1
			make -C limine limine-install

			LIMINE_INSTALL="./limine/limine-install"
		fi
		sudo "$LIMINE_INSTALL" ${lodev}
		;;&
	"gpt-tomatboot" | "gpt-stivale-hybrid" )
		# EFI installations require the EFI system partition to be mounted.
		if ! [ -f tomatboot.efi ];
		then
			wget https://raw.githubusercontent.com/qookei/image_create/master/tomatboot.efi
		fi

		sudo mkfs.vfat ${lodev}p1
		sudo mkdir $mountpoint/boot/efi
		sudo mount ${lodev}p1 $mountpoint/boot/efi
		sudo mkdir -p $mountpoint/boot/efi/efi/boot
		sudo cp tomatboot.efi $mountpoint/boot/efi/efi/boot/BOOTX64.EFI
		sudo umount ${lodev}p1
		;;
	"x86_64-efi" | "x86_64-efi-hybrid" )
		# EFI installations require the EFI system partition to be mounted.
		sudo mkfs.vfat ${lodev}p1
		sudo mkdir $mountpoint/boot/efi
		sudo mount ${lodev}p1 $mountpoint/boot/efi
		sudo grub-install --target=x86_64-efi --removable --boot-directory=$mountpoint/boot --no-uefi-secure-boot $lodev
		sudo umount ${lodev}p1
		;;
esac

if (($# == 5)); then
	sudo cp -avr $5/* $mountpoint/
fi

sudo umount $lodev$rootpart
rmdir $mountpoint

sudo losetup -d $lodev
