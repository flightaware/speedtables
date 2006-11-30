
#include <string.h>
#include <limits.h>

/* This helper function checks, whether the last "portion" bytes
 * of "needle" (which is "nlen" bytes long) exist within the "needle"
 * at offset "offset" (counted from the end of the string),
 * and whether the character preceding "offset" is not a match.
 * Notice that the range being checked may reach beyond the
 * beginning of the string. Such range is ignored.
 */
static int boyermoore_needlematch
    (const unsigned char* needle, int nlen, int portion, int offset)
{
    int virtual_begin = nlen-offset-portion;
    int ignore = 0;
    if(virtual_begin < 0) { ignore = -virtual_begin; virtual_begin = 0; }
    
    if(virtual_begin > 0 && needle[virtual_begin-1] == needle[nlen-portion-1])
        return 0;

    return
        memcmp(needle + nlen - portion + ignore,
               needle + virtual_begin,
               portion - ignore) == 0;
}   

static int max(int a, int b) { return a > b ? a : b; }

struct boyerMooreSearchStruct {
    int *skip;
    int occ[UCHAR_MAX+1];
    int a, hpos;
    int nlen;
    unsigned char *needle;
};

void
boyer_moore_setup (struct boyerMooreSearchStruct *bm, const unsigned char *needle, int nlen, int nocase) {
    int a;

    bm->skip = (int *)ckalloc ((nlen + 1) * sizeof (int));
    bm->needle = (unsigned char *)ckalloc (nlen * sizeof (unsigned char));
    bm->nlen = nlen;

    // initialize the occ table to a default value
    for (a = 0; a < UCHAR_MAX + 1; ++a) {
	bm->occ[a] = -1;
    }

    // squirrel off a copy of the needle; map to lowercase if case-insensitive.
    // simultaneously populate occ with the analysis of the needle, ignoring
    // the last character

    for (a = 0; a < nlen; ++a) {
	unsigned char c = needle[a];

	if (nocase) {
	    c = tolower(c);
	}

	bm->needle[a] = c;

	if (a < nlen - 1) {
	    bm->occ[c] = a;
	}
    }

    // preprocess step 2, init skip[]
    for (a = 0; a < nlen; ++a) {
	int value = 0;

	while (value < nlen && !boyermoore_needlematch (bm->needle, nlen, a, value)) {
	    ++value;
	}
	bm->skip[nlen - a - 1] = value;
    }
}

void
boyer_moore_teardown (struct boyerMooreSearchStruct *bm) {
    ckfree (bm->skip);
    ckfree (bm->needle);
}

const unsigned char *
boyer_moore_search (struct boyerMooreSearchStruct *bm, const unsigned char *haystack, int hlen) {
    int hpos;

    for (hpos = 0; hpos <= hlen - bm->nlen; )
    {
        int npos = bm->nlen - 1;

        while (bm->needle[npos] == haystack[npos + hpos])
        {
            if (npos == 0) {
		return haystack + hpos;
	    }
            --npos;
        }

        hpos += max(bm->skip[npos], npos - bm->occ[haystack[npos + hpos]]);
    }
    return NULL;
}

#if 0
/* Returns a pointer to the first occurrence of "needle"
 * within "haystack", or NULL if not found.
 */
const unsigned char* memmem_boyermoore
    (const unsigned char* haystack, int hlen,
     const unsigned char* needle,   int nlen)
{
    int skip[nlen]; /* Array of shifts with self-substring match check */
    int occ[UCHAR_MAX+1]; /* Array of last occurrence of each character */
    int a, hpos;
    
    if(nlen > hlen || nlen <= 0 || !haystack || !needle) return NULL;

    /* Preprocess #1: init occ[]*/
    
    /* Initialize the table to default value */
    for(a=0; a<UCHAR_MAX+1; ++a) occ[a] = -1;
    
    /* Then populate it with the analysis of the needle */
    /* But ignoring the last letter */
    for(a=0; a<nlen-1; ++a) occ[needle[a]] = a;
    
    /* Preprocess #2: init skip[] */  
    /* Note: This step could be made a lot faster.
     * A simple implementation is shown here. */
    for(a=0; a<nlen; ++a)
    {
        int value = 0;
        while(value < nlen && !boyermoore_needlematch(needle, nlen, a, value))
            ++value;
        skip[nlen-a-1] = value;
    }
    
    /* Search: */
    for(hpos=0; hpos <= hlen-nlen; )
    {
        int npos=nlen-1;
        while(needle[npos] == haystack[npos+hpos])
        {
            if(npos == 0) return haystack + hpos;
            --npos;
        }
        hpos += max(skip[npos], npos - occ[haystack[npos+hpos]]);
    }
    return NULL;
}
#endif
