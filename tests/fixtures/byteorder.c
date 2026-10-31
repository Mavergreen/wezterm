#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "libssh/priv.h"

int main(void) {
    static const struct {
        uint64_t host;
        unsigned char network[8];
    } cases[] = {
        {UINT64_C(0), {0, 0, 0, 0, 0, 0, 0, 0}},
        {UINT64_C(0x0123456789abcdef), {0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef}},
        {UINT64_C(0xffffffffffffffff), {255, 255, 255, 255, 255, 255, 255, 255}}
    };
    unsigned int i;
    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        uint64_t wire = htonll(cases[i].host);
        uint64_t input;
        if (memcmp(&wire, cases[i].network, 8) != 0) {
            fprintf(stderr, "htonll does not produce network-order bytes: case %u\n", i);
            return 1;
        }
        memcpy(&input, cases[i].network, 8);
        if (ntohll(input) != cases[i].host) {
            fprintf(stderr, "ntohll does not decode network-order bytes: case %u\n", i);
            return 1;
        }
    }
    puts("PASS: libssh's real 64-bit fallbacks preserve SSH wire order");
    return 0;
}
