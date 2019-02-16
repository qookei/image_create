#!/bin/bash

if (($# != 4 && $# != 5)); then
	echo "usage: <output file name> <image size> <partition type> <bootable> [files]"
	exit -1
fi

bootable=""
if (($4 == "y" || $4 == "yes")); then
	bootable="*"
fi

part_type=""
case "$3" in
	"fat16" )
		part_type="0e";;
	"fat32" )
		part_type="0c";;
	"ext2" )
		part_type="83";;
	"ext3" )
		part_type="83";;
	"ext4" )
		part_type="83";;
	* )
		echo "unsupported partition type";
		exit -2;;
esac

dd if=/dev/zero of=$1 bs=$2 count=1

sudo losetup /dev/loop0 $1
echo "256,$2,$part_type,$bootable write" | sudo sfdisk /dev/loop0

sudo losetup -d /dev/loop0
sudo losetup -P /dev/loop0 $1

case "$3" in
	"fat16" )
		sudo mkfs.vfat -F 16 /dev/loop0p1;;
	"fat32" )
		sudo mkfs.vfat -F 32 /dev/loop0p1;;
	"ext2" )
		sudo mkfs.ext2 /dev/loop0p1;;
	"ext3" )
		sudo mkfs.ext3 /dev/loop0p1;;
	"ext4" )
		sudo mkfs.ext4 /dev/loop0p1;;
	* )
		echo "unsupported partition type, how did we get here?";
		exit -3;;
esac

mountpoint=$(mktemp -d)

echo "tmp mountpoint is $mountpoint"

sudo mount /dev/loop0p1 $mountpoint
sudo grub-install --root-directory=$mountpoint /dev/loop0

if (($# == 5)); then
	sudo cp -avr $5/* $mountpoint/
fi

sudo umount /dev/loop0p1
rmdir $mountpoint

sudo losetup -d /dev/loop0
