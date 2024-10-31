#!/bin/bash

set -e

usage() {
	echo -e "usage: $0 [-o output] [-t partition type] [-p partition scheme] [-s size] [-l loader] [-b] [-e]\n"

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
	echo -e "\t -h                       shows this help message\n"

	echo -e "Note: installing GRUB requires that the image's partition are temporarily mounted, and as such requires root.\n"

	echo "When using GPT, you can specify the GUID of the root partition by setting the GPT_TYPE environment variable."
	echo -e "By default, the GUID for a Windows data partition is used.\n"

	echo "The default path for Limine binaries is './limine/', you can specify a custom one by setting LIMINE_PATH."
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

while getopts o:t:p:s:l:beh arg
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
		limine_path="$LIMINE_PATH"
	fi

	if [ ! -d "$limine_path" ]; then
		echo "Directory ${limine_path} doesn't exist!"
		exit 1
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

bootpart=
rootpart=
case "$partscheme" in
	mbr)
		bootpart="1"
		rootpart="2"
		;;
	gpt)
		if [ "$loader" = "grub" ] && [ "$bios" ]; then
			# Partition 1 is the GRUB BIOS boot partition.
			bootpart="2"
			rootpart="3"
		else
			bootpart="1"
			rootpart="2"
		fi
		;;
esac

# UUID of Windows data partition. Choose something else depending on your needs.
gpt_type=${GPT_TYPE:="EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"}

sfdisk_tool="$(whereis -b sfdisk | cut -d':' -f2 | xargs)"

rm -f "$output"
fallocate -l "$size" "$output"

# Every one of these layouts includes a FAT32 /boot/ partition,
# optionally a partition for GRUB's boot code, and the rootfs partition.

# The /boot/ partition doubles as the ESP for EFI images, and is otherwise
# necessary since Limine >= 6.0 drops support for Ext2/3/4. For images using
# GRUB it is kept for consistency and to simplify the script logic.

case "$partscheme" in
	mbr)
		# For MBR layouts, reserve some space before the first partition.
		cat << END_SFDISK | "$sfdisk_tool" --no-tell-kernel "$output"
label: dos
16MiB 256MiB 0c
272MiB +     $dos_parttype
END_SFDISK
		;;
	gpt)
		if [ -z "$efi" ] && [ "$loader" = "grub" ]; then
			# Create a BIOS boot partition for GRUB's boot code.
			# GRUB will use the entire partition in this case.
			cat << END_SFDISK | "$sfdisk_tool" --no-tell-kernel "$output"
label: gpt
- 16MiB  21686148-6449-6E6F-744E-656564454649
- 256MiB C12A7328-F81F-11D2-BA4B-00A0C93EC93B
- +      $gpt_type
END_SFDISK
		elif [ -z "$efi" ] && [ "$loader" = "limine" ]; then
			# Limine's boot code is embedded in GPT structures.
			cat << END_SFDISK | "$sfdisk_tool" --no-tell-kernel "$output"
label: gpt
- 256MiB C12A7328-F81F-11D2-BA4B-00A0C93EC93B
- +      $gpt_type
END_SFDISK
		elif [ -z "$bios" ] || [ "$loader" = "limine" ]; then
			# Create an EFI system partition for GRUB's/Limine's boot files.
			cat << END_SFDISK | "$sfdisk_tool" --no-tell-kernel "$output"
label: gpt
- 256MiB C12A7328-F81F-11D2-BA4B-00A0C93EC93B
- +      $gpt_type
END_SFDISK
		else
			# Combined GRUB EFI + GRUB legacy layout.
			cat << END_SFDISK | "$sfdisk_tool" --no-tell-kernel "$output"
label: gpt
- 16MiB  21686148-6449-6E6F-744E-656564454649
- 256MiB C12A7328-F81F-11D2-BA4B-00A0C93EC93B
- +      $gpt_type
END_SFDISK
		fi
		;;
esac

partition_offsets=$(partx -gbr --output nr,start,size "$output")

bootpart_info=$(echo "$partition_offsets" | grep "^${bootpart} ")
bootpart_start=$(echo "$bootpart_info" | cut -f2 -d' ')
bootpart_size=$(echo "$bootpart_info" | cut -f3 -d' ')

rootpart_info=$(echo "$partition_offsets" | grep "^${rootpart} ")
rootpart_start=$(echo "$rootpart_info" | cut -f2 -d' ')
rootpart_size=$(echo "$rootpart_info" | cut -f3 -d' ')

# Format the boot partition
mkfs.vfat -F 32 -n ESP -s 2 -S 512 --offset "$bootpart_start" "$output" "$((bootpart_size / 1024))"

# Format the root partition
case "$parttype" in
	fat16)
		mkfs.vfat -F 16 -s 2 -S 512 --offset "$rootpart_start" "$output" "$((rootpart_size / 1024))";;
	fat32)
		mkfs.vfat -F 32 -s 2 -S 512 --offset "$rootpart_start" "$output" "$((rootpart_size / 1024))";;
	ext2|ext3|ext4)
		mke2fs -Ft $parttype -E offset="$((rootpart_start * 512))" "$output" "$((rootpart_size / 1024))K";;
esac

# Install the bootloader
if [ "$loader" = "limine" ]; then
	# Install Limine files using mtools

	dosimg="${output}@@$((bootpart_start * 512))"

	if [ "$bios" ]; then
		"$limine_path/limine" bios-install "$output"
		mcopy -i "$dosimg" "$limine_path/limine-bios.sys" "::limine-bios.sys"
	fi

	if [ "$efi" ]; then
		mmd -i "$dosimg" "EFI"
		mmd -i "$dosimg" "EFI/BOOT"
		mcopy -i "$dosimg" "$limine_path/BOOTX64.EFI" "::EFI/BOOT/BOOTX64.EFI"
	fi
else
	# Install GRUB by mounting the partitions and invoking grub-install

	lodev=$(sudo losetup -Pf --show "$output")

	mountpoint=$(mktemp -d)
	echo "Mountpoint is $mountpoint"
	sudo mount "${lodev}p$rootpart" "$mountpoint"

	sudo mkdir "$mountpoint/boot"
	sudo mount "${lodev}p$bootpart" "$mountpoint/boot"

	if [ "$bios" ]; then
		# i386-pc makes GRUB use the MBR or BIOS boot partition for its boot code,
		# depending on the partition table type.
		# Note that we do not have to partition the BIOS boot partition.
		sudo grub-install --target=i386-pc --boot-directory="$mountpoint/boot" "$lodev"
	fi

	if [ "$efi" ]; then
		sudo mkdir -p "$mountpoint/boot/EFI/BOOT"

		sudo grub-install --target=x86_64-efi --removable --boot-directory="$mountpoint/boot" "$lodev"
	fi

	sudo umount "${lodev}p$bootpart"
	sudo umount "${lodev}p$rootpart"
	rmdir "$mountpoint"
	sudo losetup -d "$lodev"
fi
