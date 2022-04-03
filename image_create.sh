#!/bin/bash

set -e

usage() {
	echo -e "usage: $0 [-o output] [-t partition type] [-p partition scheme] [-s size] [-l loader] [-b] [-e] [-n] [-g] [-c path]\n"

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
	echo -e "\t -g                       use libguestfs instead of native mkfs and mount (allows for rootless image creation)"
	echo -e "\t                          note: only limine is supported with this option"
	echo -e "\t -c path                  copy files from the specified directory into the root of the image"
	echo -e "\t -h                       shows this help message\n"

	echo "When using GPT, you can specify the GUID of the root partition by setting the GPT_TYPE environment variable."
	echo -e "By default, the GUID for a Windows data partition is used.\n"

	echo "You can also specify the path to the directory with limine binaries (which automatically implies -n) by setting LIMINE_PATH."
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
use_guestfs=

while getopts o:t:p:s:l:bengc:h arg
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
		g) use_guestfs=1;;
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

limine_path="./limine"

if [ "$loader" = "limine" ]; then
	if [ "$LIMINE_PATH" ]; then
		no_fetch_limine=1
		limine_path="$LIMINE_PATH"
	fi

	if [ -z $no_fetch_limine ]; then
		rm -rf "$limine_path"
	fi

	if [ ! -d "$limine_path" ] && [ -z "$LIMINE_PATH" ]; then
		git clone https://github.com/limine-bootloader/limine --branch=v2.0-branch-binary --depth=1
	elif [ ! -d "$limine_path" ]; then
		echo "Directory specified by LIMINE_PATH doesn't exist."
		exit 1
	fi
fi

if [ "$use_guestfs" ] && [ "$loader" = "grub" ]; then
	echo "GRUB is not supported when using libguestfs"
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

rootpart=
case "$partscheme" in
	mbr)
		rootpart="1"
		;;
	gpt)
		if [ "$loader" = "limine" ] && [ "$bios" ] && [ -z "$efi" ]; then
			rootpart="1"
		elif [ "$loader" = "grub" ] && [ "$bios" ] && [ "$efi" ]; then
			rootpart="3"
		else
			rootpart="2"
		fi
		;;
esac

# UUID of Windows data partition. Choose something else depending on your needs.
gpt_type=${GPT_TYPE:="EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"}

sfdisk_tool="$(whereis -b sfdisk | cut -d':' -f2 | xargs)"

rm -f "$output"
fallocate -l "$size" "$output"

output_name=
auth_with=""

if [ "$use_guestfs" ]; then
	output_name="$output"
else
	lodev=$(sudo losetup -f --show "$output")
	output_name="$lodev"
	auth_with="sudo"
fi

case "$partscheme" in
	mbr)
		# For MBR layouts, reserve some space for the loader after the MBR.
		cat << END_SFDISK | $auth_with $sfdisk_tool --no-tell-kernel "$output_name"
label: dos
16MiB + $dos_parttype
END_SFDISK
		;;
	gpt)
		if [ -z "$efi" ] && [ "$loader" = "grub" ]; then
			# Create a BIOS boot partition for GRUB's boot code.
			# GRUB will use the entire partition in this case.
			cat << END_SFDISK | $auth_with $sfdisk_tool --no-tell-kernel "$output_name"
label: gpt
- 16MiB 21686148-6449-6E6F-744E-656564454649
- +     $gpt_type
END_SFDISK
		elif [ -z "$efi" ] && [ "$loader" = "limine" ]; then
			# Limine's boot code is embedded in GPT structures.
			cat << END_SFDISK | $auth_with $sfdisk_tool --no-tell-kernel "$output_name"
label: gpt
- +     $gpt_type
END_SFDISK
		elif [ -z "$bios" ] || [ "$loader" = "limine" ]; then
			# Create an EFI system partition for GRUB's/Limine's boot files.
			cat << END_SFDISK | $auth_with $sfdisk_tool --no-tell-kernel "$output_name"
label: gpt
- 16MiB C12A7328-F81F-11D2-BA4B-00A0C93EC93B
- +     $gpt_type
END_SFDISK
		else
			# Combined GRUB EFI + GRUB legacy layout.
			cat << END_SFDISK | $auth_with $sfdisk_tool --no-tell-kernel "$output_name"
label: gpt
- 16MiB C12A7328-F81F-11D2-BA4B-00A0C93EC93B
- 16MiB 21686148-6449-6E6F-744E-656564454649
- +     $gpt_type
END_SFDISK
		fi
		;;
esac

if [ ! "$use_guestfs" ]; then
	sudo losetup -d "$lodev"
	lodev=$(sudo losetup -Pf --show "$output")

	# Format root partition according to user-chosen type.
	case "$parttype" in
		fat16)
			sudo mkfs.vfat -F 16 "${lodev}p$rootpart";;
		fat32)
			sudo mkfs.vfat -F 32 "${lodev}p$rootpart";;
		ext2)
			sudo mkfs.ext2 "${lodev}p$rootpart";;
		ext3)
			sudo mkfs.ext3 "${lodev}p$rootpart";;
		ext4)
			sudo mkfs.ext4 "${lodev}p$rootpart";;
	esac

	mountpoint=$(mktemp -d)
	echo "Mountpoint is $mountpoint"
	sudo mount "${lodev}p$rootpart" "$mountpoint"

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
				sudo cp "$limine_path/limine.sys" "$mountpoint/boot"
				(cd "$limine_path"; sudo ./limine-deploy "$lodev")
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
				sudo cp "$limine_path/BOOTX64.EFI" "$mountpoint/boot/efi/efi/boot/BOOTX64.EFI"
				;;
		esac

		sudo umount "${lodev}p1"
	fi

	if [ "$copy_dir_path" ]; then
		sudo cp -avr "$copy_dir_path"/* "$mountpoint/"
	fi

	sudo umount "${lodev}p${rootpart}"
	rmdir "$mountpoint"
	sudo losetup -d "$lodev"
else
	if [ "$bios" ]; then
		(cd "$limine_path"; ./limine-deploy "$output")
	fi

	cmds="run
mkfs $parttype /dev/sda$rootpart"

	cmds="$cmds
mount /dev/sda$rootpart /
mkdir /boot"

	if [ "$bios" ]; then
		cmds="$cmds
copy-in '$limine_path/limine.sys' /boot/"
	fi

	if [ "$efi" ]; then
		cmds="$cmds
mkfs vfat /dev/sda1
mkdir /boot/efi
mount /dev/sda1 /boot/efi
mkdir /boot/efi/efi
mkdir /boot/efi/efi/boot
copy-in '$limine_path/BOOTX64.EFI' /boot/efi/efi/boot/"
	fi

	guestfish -a "$output" <<< "$cmds"
fi
