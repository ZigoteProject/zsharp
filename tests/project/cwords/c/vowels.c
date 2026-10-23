#include <math.h>
#include "vowels.h"

#ifndef CWORDS_SCALE
#define CWORDS_SCALE 1
#endif

int count_vowels(const char *s) {
  int n = 0;
  for (; *s; s++)
    switch (*s) {
    case 'a': case 'e': case 'i': case 'o': case 'u': n++;
    }
  return n;
}

double scaled_root(double x) { return sqrt(x) * CWORDS_SCALE; }
