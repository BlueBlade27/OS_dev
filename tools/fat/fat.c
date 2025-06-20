#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>  // Add this at the top of your file


typedef uint8_t bool;
#define true 1
#define false 0

typedef struct{

    uint8_t BootJumpInstruction[3]; // 3 bytes
    uint8_t OemIdentifier[8]; // 8 bytes
    uint16_t BytesPerSector; // 2 bytes
    uint8_t SectorsPerCluster; // 1 byte
    uint16_t ReservedSectors; // 2 bytes
    uint8_t FatCount; // 1 byte
    uint16_t DirEntryCount; // 2 bytes
    uint16_t TotalSectors; // 2 bytes
    uint8_t MediaDescriptorType; // 1 byte
    uint16_t SectorsPerFat; // 2 bytes
    uint16_t SectorsPerTrack; // 2 bytes
    uint16_t Heads; // 2 bytes
    uint32_t HiddenSectors; // 4 bytes
    uint32_t LargeSectorCount; // 4 bytes

    // extended Boot Record
    uint8_t DriveNumber; // 1 byte
    uint8_t Reserved; // 1 byte
    uint8_t Signature; // 1 byte
    uint32_t VolumeId; // 4 bytes
    uint8_t VolumeLabel[11]; // 11 bytes
    uint8_t SystemId[8]; // 8 bytes
    

} __attribute__((packed)) BootSector;

typedef struct{
    uint8_t Name[11]; // 11 bytes
    uint8_t Attributes; // 1 byte
    uint8_t Reserved; // 1 byte
    uint8_t CreatedTimeTenths; // 1 byte
    uint16_t CreatedTime; // 2 bytes
    uint16_t CreatedDate; // 2 bytes
    uint16_t AccessedDate; // 2 bytes
    uint16_t FirstClusterHigh; // 2 bytes
    uint16_t ModifiedTime; // 2 bytes
    uint16_t ModifiedDate; // 2 bytes
    uint16_t FirstClusterLow; // 2 bytes
    uint32_t Size; // 4 bytes
} __attribute__((packed)) DirectoryEntry;

DirectoryEntry* g_RootDirectory = NULL;
BootSector g_BootSector;
uint8_t* g_Fat = NULL;
uint32_t g_RootDirectoryEnd;

bool readBootSector(FILE* disk){
    return fread(&g_BootSector, sizeof(g_BootSector), 1, disk) > 0;
}

bool readSectors(FILE* disk, uint32_t lba, uint32_t count, void* bufferOut){
    bool ok = true;
    ok = ok && (fseek(disk, lba * g_BootSector.BytesPerSector, SEEK_SET) == 0);
    ok = ok && (fread(bufferOut, g_BootSector.BytesPerSector, count, disk) == count);
    return ok;
}

bool readFat(FILE* disk){
    g_Fat = (uint8_t*) malloc(g_BootSector.SectorsPerFat * g_BootSector.BytesPerSector);
    return readSectors(disk, g_BootSector.ReservedSectors, g_BootSector.SectorsPerFat, g_Fat);
}

bool readRootDirectory(FILE* disk){
    uint32_t lba = g_BootSector.ReservedSectors + (g_BootSector.FatCount * g_BootSector.SectorsPerFat);
    uint32_t size = g_BootSector.DirEntryCount * sizeof(DirectoryEntry);
    uint32_t sectors = (size / g_BootSector.BytesPerSector);
    if (size % g_BootSector.BytesPerSector > 0) {
        sectors++;
    }

    g_RootDirectoryEnd = sectors + lba;
    g_RootDirectory = (DirectoryEntry*) malloc(sectors * g_BootSector.BytesPerSector);
    return readSectors(disk, lba, sectors, g_RootDirectory);
}


DirectoryEntry* findFile(const char* name){
    for (uint32_t i = 0; i < g_BootSector.DirEntryCount; i++) {
        // End of directory marker
        if (g_RootDirectory[i].Name[0] == 0x00) {
            break;
        }

        // Deleted entry
        if (g_RootDirectory[i].Name[0] == 0xE5) {
            continue;
        }

        // Match 11-byte FAT filename
        if (memcmp(name, g_RootDirectory[i].Name, 11) == 0) {
            return &g_RootDirectory[i];
        }
    }
    return NULL;
}


bool formatToFatName(const char* input, char* output) {
    memset(output, ' ', 11); // Fill with spaces
    int i = 0, j = 0;
    bool sawDot = false;

    while (input[i] != '\0') {
        if (input[i] == '.') {
            if (sawDot) return false; // multiple dots, invalid
            sawDot = true;
            j = 8; // switch to extension
            i++;
            continue;
        }

        if (j >= 11) {
            return false; // too long
        }

        output[j++] = toupper((unsigned char)input[i++]);
    }

    return true;
}

uint16_t getFatEntry(uint16_t cluster) {
    uint32_t index = cluster + (cluster / 2);  // cluster * 1.5


    uint16_t entry = g_Fat[index] | (g_Fat[index + 1] << 8);

    if (cluster & 1)
        return entry >> 4;
    else
      return entry & 0x0FFF;
}

bool readFile(DirectoryEntry* fileEntry, FILE* disk, uint8_t* outputBuffer){
    
    bool ok = true;
    uint16_t currentCluster = fileEntry->FirstClusterLow;

    currentCluster = fileEntry->FirstClusterLow;

    do {
        uint32_t lba = g_RootDirectoryEnd + (currentCluster - 2) * g_BootSector.SectorsPerCluster;
        ok = ok && readSectors(disk, lba, g_BootSector.SectorsPerCluster, outputBuffer);
        outputBuffer += g_BootSector.SectorsPerCluster * g_BootSector.BytesPerSector;

        currentCluster = getFatEntry(currentCluster);

    } while (ok && currentCluster < 0xFF8); // FAT12 end marker is 0xFF8+

    return ok;

}


int main(int argc, char** argv){
    if (argc < 3){
        printf("Syntax: %s <disk image> <file name>\n", argv[0]);
        return 1;
    }

    FILE* disk = fopen(argv[1], "rb");
    if (!disk){
        fprintf(stderr, "can't open disk image. smthn went wrong ig.'%s'\n", argv[1]);
        return -1;
    }

    if (!readBootSector(disk)){
        fprintf(stderr, "couldn't read boot sector. sorry man.\n");
        return -2;
    }

    if (!readFat(disk)){
        fprintf(stderr, "couldn't read FAT bro\n");
        free(g_Fat);
        return -3;
    }

    if (!readRootDirectory(disk)){
        fprintf(stderr, "couldn't read root directory. sorry TT.\n");
        free(g_Fat);
        free(g_RootDirectory);
        return -4;
    }

    char formattedName[11];
    if (!formatToFatName(argv[2], formattedName)) {
        fprintf(stderr, "Invalid file name: '%s'.\n", argv[2]);
        free(g_Fat);
        free(g_RootDirectory);
        return -6;
    }

    DirectoryEntry* fileEntry = findFile(formattedName);
    //DirectoryEntry* fileEntry = findFile(argv[2]);
    if (!fileEntry){
        fprintf(stderr, "file '%s' not found in root directory.\n", argv[2]);
        free(g_Fat);
        free(g_RootDirectory);
        return -5;
    } else {
        printf("Found file '%s'!\n", argv[2]);
        fflush(stdout);
    }

    uint8_t* buffer = (uint8_t*) malloc(fileEntry->Size + g_BootSector.BytesPerSector );
    if (!readFile(fileEntry, disk, buffer)){
        fprintf(stderr, "couldn't read file honey '%s'.\n", argv[2]);
        free(g_Fat);
        free(g_RootDirectory);
        free(buffer);
        return -7;
    }

    for (size_t i = 0; i < fileEntry->Size; i++) {
        if (isprint(buffer[i])) fputc(buffer[i], stdout);
        else printf("<%02X>", buffer[i]);
    }
    printf("\n");

    free(buffer);
    free(g_Fat);
    free(g_RootDirectory);
    return 0;
}