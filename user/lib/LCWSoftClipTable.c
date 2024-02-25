/*
Copyright 2024 Tomoaki Itoh
This software is released under the MIT License, see LICENSE.txt.
//*/

#include "LCWSoftClipTable.h"

#define LCW_SOFT_CLIP_TABLE_BITS (5)
#define LCW_SOFT_CLIP_TABLE_SIZE (1 << LCW_SOFT_CLIP_TABLE_BITS)
#define LCW_SOFT_CLIP_INDEX_MAX (LCW_SOFT_CLIP_TABLE_SIZE - 1)
#define LCW_SOFT_CLIP_BASE_BITS (LCW_SOFT_CLIP_TABLE_BITS - 1)

// q24
static SQ7_24 lcwSoftClipTable24[LCW_SOFT_CLIP_TABLE_SIZE] = {
    0x00000000, 0x000FFD63, 0x001FEB28, 0x002FB9EC,
    0x003F5AC5, 0x004EBF78, 0x005DDAA8, 0x006CA006,
    0x007B0471, 0x0088FE0D, 0x0096845D, 0x00A39046,
    0x00B01C11, 0x00BC2368, 0x00C7A345, 0x00D299E2,
    0x00DD06A3, 0x00E6E9FC, 0x00F04553, 0x00F91AE5,
    0x01016DA7, 0x0109412D, 0x01109989, 0x01177B33,
    0x011DEAF2, 0x0123EDC4, 0x012988CD, 0x012EC13F,
    0x01339C54, 0x01381F39, 0x013C4F07, 0x014030BA
};

// in/out: q16
SQ15_16 lcwSoftClip16(SQ15_16 x)
{
    const uint32_t t = (uint32_t)LCW_ABS(x);
    const uint32_t i = t >> (16 - LCW_SOFT_CLIP_BASE_BITS);
    const uint32_t frac = t & (0xFFFF >> LCW_SOFT_CLIP_BASE_BITS);

    if ( i < LCW_SOFT_CLIP_INDEX_MAX ) {
        const SQ15_16 val1 = (SQ15_16)(lcwSoftClipTable24[i] >> 8);
        const SQ15_16 val2 =  (SQ15_16)(lcwSoftClipTable24[i + 1] >> 8);
        const SQ15_16 y = val1 + (((val2 - val1) * frac) >> (16 - LCW_SOFT_CLIP_BASE_BITS));
        return (x < 0) ? -y : y;
    }
    else {
        const SQ15_16 y = (SQ15_16)(lcwSoftClipTable24[LCW_SOFT_CLIP_INDEX_MAX] >> 8);
        return (x < 0) ? -y : y;
    }
}
