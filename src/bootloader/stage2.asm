org 0x0600
bits 16

%define ENDL 0x0D, 0x0A

jmp short start
nop

; BIOS Parameter Block (BPB)
bdb_oem:                    db 'MSWIN4.1'           ; 8 bytes
bdb_bytes_per_sector:       dw 512                 ; Changed from db to dw
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 224
bdb_total_sectors:          dw 2880
bdb_media_descriptor_type:  db 0F0h
bdb_sectors_per_fat:        dw 9
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_sector_count:     dd 0

; Extended Boot Record
ebr_drive_number:           db 0
                            db 0                    ; Reserved
ebr_signature:              db 29h
ebr_volume_id:              db 12h, 34h, 56h, 78h  ; Serial number
ebr_volume_label:           db 'NBOS       '       ; 11 bytes, padded with spaces
ebr_system_id:              db 'FAT12   '          ; 8 bytes

puts:
    pusha
.next_char:
    lodsb           ; Load byte at DS:SI into AL, increment SI
    cmp al, 0
    je .done        ; If null terminator, stop
    mov ah, 0x0E
    int 0x10
    jmp .next_char
.done:
    popa
    ret



start:    
    ; Initialize segment registers
    xor ax, ax
    mov ds, ax
    mov es, ax

    ; Set up stack
    mov ss, ax
    mov sp, 0x7C00  ; Stack grows downward from 0x7C00

    ; some BIOS calls require the ES segment to be set
    push es
    push word .after
    retf

.after:
    ; Save drive number
    mov [ebr_drive_number], dl   

    ; show loading message
    mov si, msg_loading
    call puts  

    mov ah, 08h
    int 13h
    jc floppy_error

    and cl, 0x3F  ; Mask to 6 bits (LBA)
    xor ch, ch
    mov [bdb_sectors_per_track], cx

    inc dh
    mov [bdb_heads], dh

    mov ax, [bdb_sectors_per_fat]
    mov bl, [bdb_fat_count]
    xor bh, bh
    mul bx
    add ax, [bdb_reserved_sectors]
    push ax
    
    mov ax, [bdb_sectors_per_fat]
    shl ax, 5
    xor dx, dx
    div word [bdb_bytes_per_sector] ; Calculate total sectors

    test dx, dx
    jz .root_dir_after
    inc ax

.root_dir_after:

    mov cl, al
    pop ax
    mov dl, [ebr_drive_number]
    mov bx, buffer
    call disk_read

    xor bx, bx
    mov di, buffer

.search_kernel:

    mov si, file_kernel_bin
    mov cx, 11
    push di
    repe cmpsb                         ; cmpsb: compares bytes at DS:SI and ES:DI. repe: repeats a string instruction while the operands are equal or until cx reaches 0
    pop di
    je .found_kernel

    add di, 32
    inc bx
    cmp bx, [bdb_dir_entries_count]
    jl .search_kernel

    jmp kernel_not_found_error

.found_kernel
    mov ax, [di + 26]                ; Get the first cluster of the kernel file
    mov [kernel_cluster], ax

    ;load FAT from disk into memory
    mov ax, [bdb_reserved_sectors]
    mov bx, buffer
    mov cl, [bdb_sectors_per_fat]
    mov dl, [ebr_drive_number]
    call disk_read

    ;read kernel and process FAT chain
    mov bx, KERNEL_LOAD_SEGMENT
    mov es, bx
    mov bx, KERNEL_LOAD_OFFSET

.load_kernel_loop:
    mov ax, [kernel_cluster]
    cmp ax, 0xFF8
    jae .read_finish

    ; LBA = 31 + (cluster - 2)
    mov cx, ax
    sub cx, 2
    mov ax, 31
    add ax, cx

    mov cl, 1
    mov dl, [ebr_drive_number]
    call disk_read

    add bx, [bdb_bytes_per_sector]

    ; get next cluster from FAT
    mov ax, [kernel_cluster]
    mov cx, 3
    mul cx
    mov cx, 2
    div cx

    mov si, fat_buffer
    add si, ax
    mov ax, [ds:si]

    or dx, dx
    jz .even
.odd:
    shr ax, 4
    jmp .next
.even:
    and ax, 0x0FFF
.next:
    mov [kernel_cluster], ax
    jmp .load_kernel_loop


.read_finish:

    ;boot device in dl
    mov dl, [ebr_drive_number]

    mov ax, KERNEL_LOAD_SEGMENT
    mov ds, ax
    mov es, ax

    jmp KERNEL_LOAD_SEGMENT:KERNEL_LOAD_OFFSET

    jmp wait_key_and_reboot

    cli
    hlt

floppy_error:

    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

kernel_not_found_error:
    mov si, msg_kernel_not_found
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    int 16h
    jmp 0FFFFh:0

lba_to_chs:

    push ax
    push dx

    xor dx, dx
    div word [bdb_sectors_per_track] ; Divide LBA by sectors per track

    inc dx
    mov cx, dx

    xor dx, dx
    div word [bdb_heads]             ; Divide LBA by heads


    mov dh, dl
    mov ch, al
    shl ah, 6
    or cl, ah

    pop ax
    mov dl, al
    pop ax
    ret


disk_read:

    push ax
    push bx
    push cx
    push dx
    push di

    push cx
    call lba_to_chs
    pop ax
    mov ah, 02h
    mov di, 3

.retry:
    pusha
    stc
    int 13h
    jnc .done
    popa
    call disk_reset

    dec di
    test di, di
    jnz .retry

.fail:
    jmp floppy_error

.done:
    popa

    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

disk_reset:
    pusha
    mov ah, 0
    stc
    int 13h
    jc floppy_error
    popa
    ret
    

msg_read_failed: db 'Read failed', 0
msg_kernel_not_found: db 'No kernel', 0
msg_loading: db 'Load', 0
file_kernel_bin: db 'KERNEL  BIN'
kernel_cluster: dw 0 

fat_buffer:     times 512*9 db 0   ; enough for 9 sectors of FAT
dir_buffer:     times 512 db 0     ; for directory


KERNEL_LOAD_SEGMENT equ 0x2000
KERNEL_LOAD_OFFSET equ 0


buffer: times 512 db 0  ; 1 sector of temp buffer


