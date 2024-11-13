# image\_create

A simple tool to generate partitioned hard disk images.

## Requirements
 - losetup
 - sfdisk, partx
 - mkfs for the corresponding file system
   - mkfs.vfat for fat16/32 (note: also required for EFI images, since they need a FAT32 ESP partition)
   - mkfs.ext2/3/4 for ext2/3/4 respectively
 - mtools (when using `-l limine`)
 - grub-install (when using `-l grub`)

## Usage
When you run image\_create without any arguments, or with `-h`, it'll print the following usage message:
```
usage: $0 [-o output] [-t partition type] [-p partition scheme] [-s size] [-l loader] [-a arch] [-b] [-e]

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
  -a arch                  create image for the requested architecture
                           default: x86_64, supported: x86_64, aarch64, riscv64
  -b                       makes the image BIOS bootable
  -e                       makes the image EFI bootable
  -h                       shows this help message

Note: installing GRUB requires that the image's partition are temporarily mounted, and as such requires root.

When using GPT, you can specify the GUID of the root partition by setting the GPT_TYPE environment variable.
By default, the GUID for a Windows data partition is used.

The default path for Limine binaries is '/usr/share/limine', you can specify a custom one by setting LIMINE_BIN_DIR.
The default command for the 'limine' tool is 'limine', you can specify a custom one by setting LIMINE_TOOL.
```
