# image\_create

A simple tool to generate partitioned hard disk images.

## Requirements
 - losetup
 - sfdisk
 - mkfs for the corresponding file system
   - mkfs.vfat for fat16/32 (note: also required for EFI images, since they need a FAT32 ESP partition)
   - mkfs.ext2/3/4 for ext2/3/4 respectively
 - grub-install or git (for cloning limine, can omit cloning by specifying `-n`)

## Usage
When you run image\_create without any arguments, or with `-h`, it'll print the following usage message:
```
usage: image_create.sh [-o output] [-t partition type] [-p partition scheme] [-s size] [-l loader] [-b] [-e] [-n] [-c path]

Supported arguments:
	 -o output                specifies path to output image
	 -t partition type        specifies the partition type for the root fs
	                          supported types: ext2/3/4, fat16/32
	 -p partition scheme      specifies the partition scheme to use
	                          supported schemes: mbr, gpt
	                          note: EFI requires gpt
	 -s size                  specifies the image size, eg: 1G, 512M
	 -l loader                specifies the loader to use
	                          supported loaders: grub, limine
	 -b                       makes the image BIOS bootable
	 -e                       makes the image EFI bootable
	 -n                       don't fetch Limine (reuses existing './limine/' directory)
	 -c path                  copy files from the specified directory into the root of the image
	 -h                       show this help message

When using GPT, you can specify the GUID of the root partition by setting the GPT_TYPE environment variable.
By default, the GUID for a Windows data partition is used.
```
