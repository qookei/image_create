#!/bin/bash

set -e

usage() {
	echo -e "usage: $0 [-o output] [-t partition type] [-p partition scheme] [-s size] [-l loader] [-a arch] [-b] [-e]\n"

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
	echo -e "\t -a arch                  create image for the requested architecture"
	echo -e "\t                          default: x86_64, supported: x86_64, aarch64, riscv64"
	echo -e "\t -b                       makes the image BIOS bootable"
	echo -e "\t -e                       makes the image EFI bootable"
	echo -e "\t -h                       shows this help message\n"

	echo -e "Note: installing GRUB requires that the image's partition are temporarily mounted, and as such requires root.\n"

	echo "When using GPT, you can specify the GUID of the root partition by setting the GPT_TYPE environment variable."
	echo -e "By default, the GUID for a Windows data partition is used.\n"

	echo "The default path for Limine binaries is '/usr/share/limine', you can specify a custom one by setting LIMINE_BIN_DIR."
	echo "The default command for the 'limine' tool is 'limine', you can specify a custom one by setting LIMINE_TOOL."
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
arch=
bios=
efi=

while getopts o:t:p:s:l:a:beh arg
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
		a) arch="$OPTARG"
			case "$arch" in
				x86_64|aarch64|riscv64);;
				*) echo "Architecture $arch is not supported"; exit 1;;
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

if [ -z "$arch" ]; then
	arch="x86_64"
fi

if [ "$efi" ] && [ "$partscheme" != "gpt" ]; then
	echo "EFI bootable images require GPT partition scheme."
	exit 1;
fi

if [ "$bios" ] && [ "$arch" != "x86_64" ]; then
	echo "BIOS boot is only valid on x86_64."
	exit 1;
fi

limine_bin_dir=${LIMINE_BIN_DIR:="/usr/share/limine/"}
limine_tool=${LIMINE_TOOL:="limine"}

if [ "$loader" = "limine" ]; then
	if [ ! -d "$limine_bin_dir" ]; then
		echo "Directory $limine_bin_dir doesn't exist!"
		exit 1
	fi

	if [ ! -x "$limine_tool" ]; then
		echo "Program $limine_tool doesn't exist or is not executable!"
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
mkfs_vfat_tool="$(whereis -b mkfs.vfat | cut -d':' -f2 | xargs)"
mke2fs_tool="$(whereis -b mke2fs | cut -d':' -f2 | xargs)"

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
start=- size=16MiB type=21686148-6449-6E6F-744E-656564454649
start=- size=256MiB type=uefi
start=- size=+ type=$gpt_type
END_SFDISK
		elif [ -z "$efi" ] && [ "$loader" = "limine" ]; then
			# Limine's boot code is embedded in GPT structures.
			cat << END_SFDISK | "$sfdisk_tool" --no-tell-kernel "$output"
label: gpt
start=- size=256MiB type=uefi
start=- size=+ type=$gpt_type
END_SFDISK
		elif [ -z "$bios" ] || [ "$loader" = "limine" ]; then
			# Create an EFI system partition for GRUB's/Limine's boot files.
			cat << END_SFDISK | "$sfdisk_tool" --no-tell-kernel "$output"
label: gpt
start=- size=256MiB type=uefi
start=- size=+ type=$gpt_type
END_SFDISK
		else
			# Combined GRUB EFI + GRUB legacy layout.
			cat << END_SFDISK | "$sfdisk_tool" --no-tell-kernel "$output"
label: gpt
start=- size=16MiB type=21686148-6449-6E6F-744E-656564454649
start=- size=256MiB type=uefi
start=- size=+ type=$gpt_type
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
"$mkfs_vfat_tool" -F 32 -n ESP -s 2 -S 512 --offset "$bootpart_start" "$output" "$((bootpart_size / 1024))"

# Format the root partition and create a /boot directory on it.
case "$parttype" in
	fat16)
		"$mkfs_vfat_tool" -F 16 -s 2 -S 512 --offset "$rootpart_start" "$output" "$((rootpart_size / 1024))"
		dosimg="${output}@@$((rootpart_start * 512))"
		mmd -i "$dosimg" "boot"
		;;
	fat32)
		"$mkfs_vfat_tool" -F 32 -s 2 -S 512 --offset "$rootpart_start" "$output" "$((rootpart_size / 1024))"
		dosimg="${output}@@$((rootpart_start * 512))"
		mmd -i "$dosimg" "boot"
		;;
	ext2|ext3|ext4)
		tmpdir=$(mktemp -d)
		mkdir -p "${tmpdir}/boot"
		"$mke2fs_tool" -Ft "$parttype" -d "$tmpdir" -E offset="$((rootpart_start * 512))" "$output" "$((rootpart_size / 1024))K"
		rmdir "${tmpdir}/boot" || echo "Did not delete temporary /boot at ${tmpdir}/boot (not empty?)"
		rmdir "${tmpdir}/" || echo "Did not delete temporary / at ${tmpdir} (not empty?)"
		;;
esac

# Install the bootloader
if [ "$loader" = "limine" ]; then
	# Install Limine files using mtools

	dosimg="${output}@@$((bootpart_start * 512))"

	if [ "$bios" ]; then
		"$limine_tool" bios-install "$output"
		mcopy -i "$dosimg" "$limine_bin_dir/limine-bios.sys" "::limine-bios.sys"
	fi

	if [ "$efi" ]; then
		mmd -i "$dosimg" "EFI"
		mmd -i "$dosimg" "EFI/BOOT"

		limine_efi_bin=
		case "$arch" in
			x86_64) limine_efi_bin="BOOTX64.EFI";;
			aarch64) limine_efi_bin="BOOTAA64.EFI";;
			riscv64) limine_efi_bin="BOOTRISCV64.EFI";;
		esac

		mcopy -i "$dosimg" "$limine_bin_dir/$limine_efi_bin" "::EFI/BOOT/BOOTX64.EFI"
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

		grub_target=
		case "$arch" in
			x86_64) grub_target="x86_64-efi";;
			aarch64) grub_target="arm64-efi";;
			riscv64) grub_target="riscv64-efi";;
		esac

		sudo grub-install --target="$grub_target" --removable --boot-directory="$mountpoint/boot" "$lodev"
	fi

	sudo umount "${lodev}p$bootpart"
	sudo umount "${lodev}p$rootpart"
	rmdir "$mountpoint"
	sudo losetup -d "$lodev"
fi
