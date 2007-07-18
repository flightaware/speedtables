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
    mapinfo *mapinfo = map_file("test.map", MAPADDR, 1024*1024*50);
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

    unmap_file(mapinfo);

    return 0;
}

