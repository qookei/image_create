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
usage: <output file name> <image size> <partition type> <bootable> [files]
```
Here's the explanation of some of the arguments:
 - `image size` - size of the image, this option can also take units(16M, 1G, etc)
 - `partition type` - partiton type, currently supported are `fat16`, `fat32`, `ext2`, `ext3`, `ext4`
 - `bootable` - should the partition be bootable(`y` or `yes` to enable, anything else to disable)
 - `files` - optional argument, path to directory containing files that should be copied to the image
