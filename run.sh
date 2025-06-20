#!/bin/bash
qemu-system-i386 -drive format=raw,if=floppy,file=build/main_floppy.img -boot a
