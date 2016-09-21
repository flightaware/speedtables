#ifndef HAVE_ETHERS

// from the Freebsd ethers man page:

struct ether_addr *ether_aton(const char *s);
char *ether_ntoa(const struct ether_addr *n);
/*
 * The number of bytes in an ethernet (MAC) address.
 */
#define ETHER_ADDR_LEN          6

/*
 * Structure of a 48-bit Ethernet address.
 */
struct  ether_addr {
   unsigned char octet[ETHER_ADDR_LEN];
};

// From Wikipedia:
// Notational conventions
//
// The standard (IEEE 802) format for printing MAC-48 addresses in human-friendly form is six groups of two hexadecimal
// digits, separated by hyphens (-) in transmission order (e.g. 01-23-45-67-89-ab). This form is also commonly used for
// EUI-64 (e.g. 01-23-45-67-89-ab-cd-ef). Other conventions include six groups of two hexadecimal digits separated by
// colons (:) (e.g. 01:23:45:67:89:ab), and three groups of four hexadecimal digits separated by dots (.)
// (e.g. 0123.4567.89ab); again in transmission order.

// Implementation

struct ether_addr *ether_aton(const char *s)
{
	static struct ether_addr a;
	int group, i, c, twobyte;

	for(i = 0; i < ETHER_ADDR_LEN; i++)
		a.octet[i] = 0;

	twobyte = 0;
	group = 0;
	i = 0;
	while(i < ETHER_ADDR_LEN) {
		c = *s++;
		switch (c) {
			case 'a': case 'b': case 'c':
			case 'd': case 'e': case 'f':
				group = group * 16 + c - 'a' + 10;
				break;
			case 'A': case 'B': case 'C':
			case 'D': case 'E': case 'F':
				group = group * 16 + c - 'A' + 10;
				break;
			case '0': case '1': case '2': case '3': case '4':
			case '5': case '6': case '7': case '8': case '9':
				group = group * 16 + c - '0';
				break;
			case '.':
				twobyte = 1;
			case ':': case '-': case 0:
				if(twobyte) {
					if(group & ~0xFFFF) {
						return NULL;
					}
					a.octet[i++] = (group & 0xFF00) >> 8;
					a.octet[i++] = (group & 0x00FF);
				} else {
					if(group & ~0xFF) {
						return NULL;
					}
					a.octet[i++] = group & 0xFF;
				}
				group = 0;
				break;
			default:
				return NULL;
		}
	}

	if(c) {
		return NULL;
	}

	return &a;
}

char *ether_ntoa(const struct ether_addr *a)
{
	static char hex[] = "0123456789ABCDEF";
	//            2 digits per octet + 1 separator between + nil
	static char s[ETHER_ADDR_LEN * 2 + (ETHER_ADDR_LEN - 1) + 1];
	int i;

	for(i = 0; i < ETHER_ADDR_LEN; i++) {
		s[3 * i    ] = hex[(a->octet[i] & 0xF0) >> 4];
		s[3 * i + 1] = hex[(a->octet[i] & 0x0F)     ];
	        s[3 * i + 2] = (i < ETHER_ADDR_LEN - 1) ? ':' : 0;
	}
	return s;
}

#endif
