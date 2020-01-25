#!/bin/bash

set -e

if (($# != 4 && $# != 5)); then
	echo "usage: <output file name> <image size> <partition type> <dos or gpt> [files]"
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
	"dos" )
		rootpart="p1"
		;;
	"gpt" | "x86_64-efi" )
		rootpart="p2"
		;;
	* )
		echo "unexpected partition table layout";
		exit -2;;
esac

# UUID of Windows data partition. Choose something else depending on your needs.
gpt_type="EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"

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
	"x86_64-efi" )
		# For GPT layouts, install GRUB's boot code to the EFI system partition.
		# GRUB will create a file on that partition.
		cat << END_SFDISK | sudo sfdisk --no-tell-kernel $lodev
label: gpt
- 16MiB C12A7328-F81F-11D2-BA4B-00A0C93EC93B
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
	"dos" | "gpt" )
		# i386-pc makes GRUB use the MBR or BIOS boot partition for its boot code,
		# depending on the partition table type.
		# Note that we do not have to partition the BIOS boot partition.
		sudo grub-install --target=i386-pc --boot-directory=$mountpoint/boot $lodev
		;;
	"x86_64-efi" )
		# EFI installations require the EFI system partition to be mounted.
		sudo mkfs.vfat ${lodev}p1
		sudo mkdir $mountpoint/boot/efi
		sudo mount ${lodev}p1 $mountpoint/boot/efi
		sudo grub-install --target=x86_64-efi --removable --boot-directory=$mountpoint/boot --no-uefi-secure-boot $lodev
		sudo umount ${lodev}p1
		;;
	* )
		echo "unexpected partition table layout";
		exit -2;;
esac

if (($# == 5)); then
	sudo cp -avr $5/* $mountpoint/
fi

sudo umount $lodev$rootpart
rmdir $mountpoint

sudo losetup -d $lodev
