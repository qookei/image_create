# image\_create

A simple tool to generate partitioned hard disk images.

## Requirements
 - losetup
 - sfdisk
 - mkfs for the corresponding file system
   - mkfs.vfat for fat16/32 (note: also required for EFI images, since they need a FAT32 ESP partition)
   - mkfs.ext2/3/4 for ext2/3/4 respectively
 - grub-install (when using `-l grub`)
 - libguestfs (when using `-g`)

## Usage
When you run image\_create without any arguments, or with `-h`, it'll print the following usage message:
```
usage: $0 [-o output] [-t partition type] [-p partition scheme] [-s size] [-l loader] [-b] [-e] [-g]

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
  -g                       use libguestfs instead of native mkfs and mount (allows for rootless image creation)
                           note: only limine is supported with this option
  -h                       shows this help message

When using GPT, you can specify the GUID of the root partition by setting the GPT_TYPE environment variable.
By default, the GUID for a Windows data partition is used.

The default path for Limine binaries is './limine/', you can specify a custom one by setting LIMINE_PATH.
```
