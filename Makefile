ASM=nasm
CC=gcc

SRC_DIR =src
TOOLS_DIR=tools
BUILD_DIR=build


.PHONY: all floppy_image kernel bootloader clean always tools_fat

all: floppy_image tools_fat

#Floppy image

floppy_image: $(BUILD_DIR)/main_floppy.img

$(BUILD_DIR)/main_floppy.img: bootloader kernel
	dd if=/dev/zero of=$(BUILD_DIR)/main_floppy.img bs=512 count=2880
	mkfs.fat -F 12 $(BUILD_DIR)/main_floppy.img
	dd if=$(BUILD_DIR)/stage1.bin of=$(BUILD_DIR)/main_floppy.img conv=notrunc
	mcopy -i $(BUILD_DIR)/main_floppy.img $(BUILD_DIR)/stage2.bin ::STAGE2.BIN
	mcopy -i $(BUILD_DIR)/main_floppy.img $(BUILD_DIR)/kernel.bin ::KERNEL.BIN


#Bootloader (stage 1 + stage 2)
bootloader: $(BUILD_DIR)/bootloader.bin

$(BUILD_DIR)/bootloader.bin: $(SRC_DIR)/bootloader/stage1.asm $(SRC_DIR)/bootloader/stage2.asm | always
	$(ASM) $(SRC_DIR)/bootloader/stage1.asm -f bin -o $(BUILD_DIR)/stage1.bin
	$(ASM) $(SRC_DIR)/bootloader/stage2.asm -f bin -o $(BUILD_DIR)/stage2.bin
	cat $(BUILD_DIR)/stage1.bin $(BUILD_DIR)/stage2.bin > $(BUILD_DIR)/bootloader.bin


#Kernel
kernel: $(BUILD_DIR)/kernel.bin

$(BUILD_DIR)/kernel.bin: always
	$(ASM) $(SRC_DIR)/kernel/main.asm -f bin -o $(BUILD_DIR)/kernel.bin 


#Tools 
tools_fat: $(BUILD_DIR)/tools/fat
$(BUILD_DIR)/tools/fat: always $(TOOLS_DIR)/fat/fat.c
	mkdir -p $(BUILD_DIR)/tools
	$(CC) -g -o $(BUILD_DIR)/tools/fat $(TOOLS_DIR)/fat/fat.c


#always
always:
	mkdir -p $(BUILD_DIR)

#Clean
clean:
	rm -rf $(BUILD_DIR)/*
