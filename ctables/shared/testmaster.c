#include <stdlib.h>
#include <sys/types.h>
#include <stdio.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/ipc.h>

#include "shared.h"

#define MAPADDR ((char *) 0xA0000000)
#define MAPSIZE (1024*1024*50)

int main(int ac, char **av)
{
    mapinfo *mapinfo = map_file("test.map", MAPADDR, MAPSIZE);
    char *chunks[1024];
    int i;

    if(!mapinfo) {
	shared_perror("test.map");
	return -1;
    }
    fprintf(stderr,
	"Mapped 0x%lX .. 0x%lX\n",
	(long)(mapinfo->map),
	(long)(((char *)mapinfo->map) + mapinfo->size));
    shminitmap(mapinfo);
    add_symbol(mapinfo, "_base", shmalloc(mapinfo, 100), 0);
    fprintf(stderr, "Added symbol '_base'\n");
    fprintf(stderr, "Value is 0x%lX\n", (long)(get_symbol(mapinfo, "_base", 0)));

    fprintf(stderr, "Creating a pool for 10000 128 byte blocks.\n");
    shmaddpool(mapinfo, 128, 10000);
    srandom(123456789);

    fprintf(stderr, "Loading table.\n");
    for(i = 0; i < 1024; i++) {
	size_t size = random() % 256 + 64;
	fprintf(stderr, "chunk[%d] = shmalloc(%d);\n", i, size);
	chunks[i] = shmalloc(mapinfo, size);
    }

    fprintf(stderr, "Shuffling table.\n");
    for(i = 0; i < 1024; i++) {
	int j = random() % 1024;
	size_t size = random() % 256 + 64;
	fprintf(stderr, "shmfree(chunk[%d]);\n", j);
	shmfree(mapinfo, chunks[j]);
	fprintf(stderr, "chunk[%d] = shmalloc(%d);\n", j, size);
	chunks[j] = shmalloc(mapinfo, size);
    }

    fprintf(stderr, "Freeing table.\n");
    for(i = 0; i < 1024; i++) {
	fprintf(stderr, "shmfree(chunk[%d]);\n", i);
	shmfree(mapinfo, chunks[i]);
    }

    fprintf(stderr, "Collecting garbage.\n");
    garbage_collect(mapinfo);

    fprintf(stderr, "Unmapping file.\n");
    unmap_file(mapinfo);

    return 0;
}

