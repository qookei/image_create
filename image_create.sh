#!/bin/bash

set -e

usage() {
	echo -e "usage: $0 [-o output] [-t partition type] [-p partition scheme] [-s size] [-l loader] [-b] [-e] [-n] [-c path]\n"

	echo -e "Supported arguments:"
	echo -e "\t -o output                specifies path to output image"
	echo -e "\t -t partition type        specifies the partition type for the root fs"
	echo -e "\t                          supported types: ext2/3/4, fat16/32"
	echo -e "\t -p partition scheme      specifies the partition scheme to use"
	echo -e "\t                          supported schemes: mbr, gpt"
	echo -e "\t                          note: EFI requires gpt"
	echo -e "\t -s size                  specifies the image size, eg: 1G, 512M"
	echo -e "\t -l loader                specifies the loader to use"
	echo -e "\t                          supported loaders: grub, limine"
	echo -e "\t -b                       makes the image BIOS bootable"
	echo -e "\t -e                       makes the image EFI bootable"
	echo -e "\t -n                       don't fetch Limine (reuses existing './limine/' directory)"
	echo -e "\t -c path                  copy files from the specified directory into the root of the image"
	echo -e "\t -h                       shows this help message\n"

	echo "When using GPT, you can specify the GUID of the root partition by setting the GPT_TYPE environment variable."
	echo "By default, the GUID for a Windows data partition is used."

}

if [ $# -eq 0 ]; then
	usage
	exit 0
fi

output=
parttype=
partscheme=
size=
loader=
bios=
efi=
no_fetch_limine=
copy_dir_path=

while getopts o:t:p:s:l:benc:h arg
do
	case $arg in
		o) output="$OPTARG";;
		t) parttype="$OPTARG"
			case "$parttype" in
				ext2|ext3|ext4|fat16|fat32);;
				*) echo "Partition type $parttype is not supported"; exit 1;;
			esac
			;;
		p) partscheme="$OPTARG"
			case "$partscheme" in
				mbr|gpt);;
				*) echo "Partition scheme $partscheme is not supported"; exit 1;;
			esac
			;;
		s) size="$OPTARG";;
		l) loader="$OPTARG"
			case "$loader" in
				grub|limine);;
				*) echo "Loader $loader is not supported"; exit 1;;
			esac
			;;
		b) bios=1;;
		e) efi=1;;
		n) no_fetch_limine=1;;
		c) copy_dir_path="$OPTARG";;
		h) usage; exit 0;;
		?) echo "See -h for help."; exit 1;;
	esac
done

if [ -z "$output" ]; then
	echo "Output image is required but wasn't specified."
	echo "See -h for help."
	exit 1;
fi

if [ -z "$parttype" ]; then
	echo "Partition type is required but wasn't specified."
	echo "See -h for help."
	exit 1;
fi

if [ -z "$partscheme" ]; then
	echo "Partition scheme is required but wasn't specified."
	echo "See -h for help."
	exit 1;
fi

if [ -z "$size" ]; then
	echo "Size is required but wasn't specified."
	echo "See -h for help."
	exit 1;
fi

if [ -z "$loader" ]; then
	echo "Loader is required but wasn't specified."
	echo "See -h for help."
	exit 1;
fi

if [ -z "$bios" ] && [ -z "$efi" ]; then
	echo "Either BIOS or EFI (or both) support needs to be specified but wasn't."
	echo "See -h for help."
	exit 1;
fi

if [ "$efi" ] && [ "$partscheme" != "gpt" ]; then
	echo "EFI bootable images require GPT partition scheme."
	exit 1;
fi

if [ "$loader" = "limine" ]; then
	if [ -z $no_fetch_limine ]; then
		rm -rf limine
	fi

	if [ ! -d limine ]; then
		git clone https://github.com/limine-bootloader/limine --branch=v2.0-branch-binary --depth=1
	fi
fi

dos_parttype=""
case "$parttype" in
	fat16)
		dos_parttype="0e";;
	fat32)
		dos_parttype="0c";;
	ext2)
		dos_parttype="83";;
	ext3)
		dos_parttype="83";;
	ext4)
		dos_parttype="83";;
esac

rootpart=""
case "$partscheme" in
	mbr)
		rootpart="p1"
		;;
	gpt)
		if [ "$loader" = "grub" ] && [ "$bios" ] && [ "$efi" ]; then
			rootpart="p3"
		else
			rootpart="p2"
		fi
		;;
esac

# UUID of Windows data partition. Choose something else depending on your needs.
gpt_type=${GPT_TYPE:="EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"}

rm -f "$output"
fallocate -l "$size" "$output"

lodev=$(sudo losetup -f --show "$output")

case "$partscheme" in
	mbr)
		# For MBR layouts, reserve some space for the loader after the MBR.
		cat << END_SFDISK | sudo sfdisk --no-tell-kernel "$lodev"
label: dos
16MiB + $dos_parttype
END_SFDISK
		;;
	gpt)
		if [ -z "$efi" ] && [ "$loader" = "grub" ]; then
			# Create a BIOS boot partition for GRUB's boot code.
			# GRUB will use the entire partition in this case.
			cat << END_SFDISK | sudo sfdisk --no-tell-kernel "$lodev"
label: gpt
- 16MiB 21686148-6449-6E6F-744E-656564454649
- +     $gpt_type
END_SFDISK
		elif [ -z "$efi" ] && [ "$loader" = "limine" ]; then
			# Limine's boot code is embedded in GPT structures.
			cat << END_SFDISK | sudo sfdisk --no-tell-kernel "$lodev"
label: gpt
- +     $gpt_type
END_SFDISK
		elif [ -z "$bios" ] || [ "$loader" = "limine" ]; then
			# Create an EFI system partition for GRUB's/Limine's boot files.
			cat << END_SFDISK | sudo sfdisk --no-tell-kernel "$lodev"
label: gpt
- 16MiB C12A7328-F81F-11D2-BA4B-00A0C93EC93B
- +      $gpt_type
END_SFDISK
		else
			# Combined GRUB EFI + GRUB legacy layout.
			cat << END_SFDISK | sudo sfdisk --no-tell-kernel "$lodev"
label: gpt
- 16MiB C12A7328-F81F-11D2-BA4B-00A0C93EC93B
- 16MiB 21686148-6449-6E6F-744E-656564454649
- +     $gpt_type
END_SFDISK
		fi
		;;
esac

sudo losetup -d "$lodev"
lodev=$(sudo losetup -Pf --show "$output")

# Format root partition according to user-chosen type.
case "$parttype" in
	fat16)
		sudo mkfs.vfat -F 16 "$lodev$rootpart";;
	fat32)
		sudo mkfs.vfat -F 32 "$lodev$rootpart";;
	ext2)
		sudo mkfs.ext2 "$lodev$rootpart";;
	ext3)
		sudo mkfs.ext3 "$lodev$rootpart";;
	ext4)
		sudo mkfs.ext4 "$lodev$rootpart";;
esac

mountpoint=$(mktemp -d)
echo "Mountpoint is $mountpoint"
sudo mount "$lodev$rootpart" "$mountpoint"

sudo mkdir "$mountpoint/boot"

if [ "$bios" ]; then
	case "$loader" in
		grub)
			# i386-pc makes GRUB use the MBR or BIOS boot partition for its boot code,
			# depending on the partition table type.
			# Note that we do not have to partition the BIOS boot partition.
			sudo grub-install --target=i386-pc --boot-directory="$mountpoint/boot" "$lodev"
			;;
		limine)
			(cd limine; sudo ./limine-install-linux-x86_64 "$lodev")
			;;
	esac
fi

if [ "$efi" ]; then
	sudo mkfs.vfat "${lodev}p1"
	sudo mkdir "$mountpoint/boot/efi"
	sudo mount "${lodev}p1" "$mountpoint/boot/efi"
	sudo mkdir -p "$mountpoint/boot/efi/efi/boot"

	case "$loader" in
		grub)
			sudo grub-install --target=x86_64-efi --removable --boot-directory="$mountpoint/boot" "$lodev"
			;;
		limine)
			sudo cp limine/BOOTX64.EFI "$mountpoint/boot/efi/efi/boot/BOOTX64.EFI"
			;;
	esac

	sudo umount "${lodev}p1"
fi

if [ "$copy_dir_path" ]; then
	sudo cp -avr "$copy_dir_path"/* "$mountpoint/"
fi

sudo umount "$lodev$rootpart"
rmdir "$mountpoint"
sudo losetup -d "$lodev"
