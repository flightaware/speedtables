#include <stdlib.h>
#include <sys/types.h>
#include <stdio.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/ipc.h>

#include "shared.h"

#include "dumper.h"

// 32 bit OSX
//#define MAPADDR ((char *) 0xA000000)
// 32 bit FreeBSD
//#define MAPADDR ((char *) 0xA0000000)
//64 bit
#define MAPADDR ((char *) 0xA0000000000)

char *magic2string(int magic)
{
	static char string[256];
	int i;

	for(i = 0; i < 256; i++) {
		if(magic == 0) break;
		string[i] = magic & 0xFF;
		magic >>= 8;
	}
	string[i] = 0;
	return string;
}
void usage (char *av0)
{
    fprintf(stderr, "Usage: %s filename\n", av0);
}

int main(int ac, char **av)
{
	shm_t          *share;
	char           *filename = NULL;
	char           *av0 = *av;
	int expand_speedtables = 0;

	while (*++av) {
		if(**av == '-') {
			if (strcmp(*av, "-speed") == 0) {
				expand_speedtables = 1;
			} else {
				usage(av0);
				exit(-1);
			}
		} else if (filename == NULL) {
			filename = *av;
		} else {
			usage(av0);
			exit(-1);
		}
	}

	if (filename == NULL) {
		usage(av0);
		exit(-1);
	}
	share = map_file(filename, MAPADDR, 0, 0, 0);

	if (!share) {
		fprintf(stderr, "map_file('%s', %08x, 0, 0, 0) failed\n", filename, MAPADDR);
		exit(2);
	}
	printf("FILE %s\n", share->filename);
	printf("SHARE %s\n", share->name);
	printf("MAP magic = %s (%x) headersize = %d cycle = %d\n",
	       magic2string(share->map->magic), share->map->magic,
	       share->map->headersize, share->map->cycle);

	int i;
	int live = 0;

	for(i = 0; i < MAX_SHMEM_READERS; i++) {
		if(share->map->readers[i].pid) {
			if(live == 0)
				printf("READERS:");
			if(live % 4 == 0)
				printf("\n    ");
			else
				putchar(' ');

				
			printf("%d: %5d %8x;", i,
				share->map->readers[i].pid, 
				share->map->readers[i].cycle);

			live++;
		}
	}

	if(live) putchar('\n');

	printf("NREADERS %d\n", live);

	if(share->map->namelist) {
		printf("SYMBOLS:\n");
		volatile struct symbol_t *sym;

		for(sym = share->map->namelist; sym; sym = sym->next) {
			printf("  %s", sym->name);
			switch (sym->type) {
				case SYM_TYPE_DATA:
					if(expand_speedtables) {
						dump_speedtable_info((struct CTable *)sym->addr);
					}
					break;
				case SYM_TYPE_STRING:
					printf(" '%s'", sym->addr);
					break;
				default:
					printf(" UNKNOWN");
					break;
			}
			putchar('\n');
		}
	}

	if(share->objects) {
		printf("OBJECTS:\n");
		struct object_t *obj;

		for(obj = share->objects; obj; obj = obj->next) {
			printf("  %s\n", obj->name);
		}
	}

	return	0;
}

void dump_speedtable_info (struct CTable *t)
{
	// TODO
}
