#include <sys/types.h>
#include <stdio.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/ipc.h>

#include "shared.h"

#define MAPADDR ((char *) 0x88150000)
#define MAPSIZE (1024*1024*50)

main()
{
    mapinfo *mapinfo = map_file("test.map", MAPADDR, 1024*1024*50);
    if(!mapinfo) {
	shared_perror("test.map");
	return;
    }
    fprintf(stderr,
	"Mapped 0x%lX .. 0x%lX\n",
	mapinfo->map,
	((char *)mapinfo->map) + mapinfo->size);
    unmap_file(mapinfo);
}

