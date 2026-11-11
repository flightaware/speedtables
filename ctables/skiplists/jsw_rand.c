// $Id$

#include <limits.h>
#include <time.h>
#include "jsw_rand.h"

#define N 624
#define M 397
#define A 0x9908b0dfUL
#define U 0x80000000UL
#define L 0x7fffffffUL

/* Internal state */
static unsigned long jsw_x[N];
static int jsw_next = 0;

/* Initialize internal state */
void jsw_seed ( unsigned long s )
{
  int i;

  jsw_x[0] = s & 0xffffffffUL;

  for ( i = 1; i < N; i++ ) {
    jsw_x[i] = ( 1812433253UL 
      * ( jsw_x[i - 1] ^ ( jsw_x[i - 1] >> 30 ) ) + i );
    jsw_x[i] &= 0xffffffffUL;
  }
}

/* Mersenne Twister */
static inline
unsigned long jsw_rand ( void )
{
  unsigned long y, a;
  int i;

  /* Refill x if exhausted */
  if ( jsw_next == N ) {
    jsw_next = 0;

    for ( i = 0; i < N - 1; i++ ) {
      y = ( jsw_x[i] & U ) | (jsw_x[i + 1] & L);
      a = ( y & 0x1UL ) ? A : 0x0UL;
      jsw_x[i] = jsw_x[( i + M ) % N] ^ ( y >> 1 ) ^ a;
    }

    y = ( jsw_x[N - 1] & U ) | (jsw_x[0] & L);
    a = ( y & 0x1UL ) ? A : 0x0UL;
    jsw_x[N - 1] = jsw_x[M - 1] ^ ( y >> 1 ) ^ a;
  }

  y = jsw_x[jsw_next++];

  /* Improve distribution */
  y ^= (y >> 11);
  y ^= (y << 7) & 0x9d2c5680UL;
  y ^= (y << 15) & 0xefc60000UL;
  y ^= (y >> 18);

  return y;
}

/* Portable time seed */
unsigned jsw_time_seed()
{
  time_t now = time ( 0 );
  unsigned char *p = (unsigned char *)&now;
  unsigned seed = 0;
  size_t i;

  for ( i = 0; i < sizeof now; i++ )
    seed = seed * ( UCHAR_MAX + 2U ) + p[i];

  return seed;
}

// vim: set ts=8 sw=4 sts=4 noet :
