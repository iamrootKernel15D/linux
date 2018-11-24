#!/bin/bash

IMAGE_FILEPATH=arch/x86/boot/bzImage 
ROOT_FILEPATH=rootfs.cpio.gz 

#if [ -z "$1" ];then
#	echo 'usage > '"$0" '<<LABEL>>'
#	exit 1
#fi

if [ ! -f "$IMAGE_FILEPATH" ];then
    echo not exist image file. check path.
    exit 2
fi

if [ ! -f "$ROOT_FILEPATH" ];then
    echo not exist root file image. check path.
    exit 3
fi

qemu-system-x86_64 -kernel "$IMAGE_FILEPATH"      \
                   -initrd "$ROOT_FILEPATH" -S -s \
                   -append nokaslr &

gdb \
    -ex "add-auto-load-safe-path $(pwd)" \
    -ex "file vmlinux" \
    -ex 'set arch i386:x86-64:intel' \
    -ex 'target remote localhost:1234' \
    -ex 'break '"$1" \
    -ex 'continue' \
    -ex 'disconnect' \
    -ex 'set arch i386:x86-64' \
    -ex 'target remote localhost:1234'
