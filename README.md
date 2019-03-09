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
<output file name> <image size> <partition type> <dos or gpt> [files]
```
Here's the explanation of the arguments:
 - `output file name` - file name for the final image file
 - `image size` - size of the image, this option can also take units(16MiB, 1GiB, etc)
 - `partition type` - partiton type, currently supported are `fat16`, `fat32`, `ext2`, `ext3`, `ext4`
 - `dos or gpt` - should the image contain a MBR or a GPT
 - `files` - optional argument, path to directory containing files that should be copied to the image
