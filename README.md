# image\_create

A simple tool to generate partitioned hard disk images.

## Requirements
 - sfdisk
 - mkfs for the corresponding file system
 - losetup
 - grub-install

## Usage
When you run image\_create without all required arguments, it'll print the following usage message:
```
<output file name> <image size> <partition type> <layout> [files]
```
Here's the explanation of the arguments:
 - `output file name` - file name for the final image file
 - `image size` - size of the image, this option can also take units(16MiB, 1GiB, etc)
 - `partition type` - partiton type, currently supported are `fat16`, `fat32`, `ext2`, `ext3`, `ext4`
 - `layout` - which partition table scheme and bootloader to use
 - `files` - optional argument, path to directory containing files that should be copied to the image

Supported layouts:
 - `dos` - MBR image with GRUB 2 for legacy BIOS
 - `gpt` - GPT image with GRUB 2 for legacy BIOS
 - `x86_64-efi` - GPT image with GRUB 2 for UEFI
 - `x86_64-efi-hybrid` - GPT image with GRUB 2 for both UEFI and legacy BIOS
 - `gpt-limine` - GPT image with limine for legacy BIOS
 - `gpt-tomatboot` - GPT image with TomatBoot for UEFI
 - `gpt-stivale-hybrid` - GPT image with limine for legacy BIOS and TomatBoot for UEFI

