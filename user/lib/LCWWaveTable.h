/*
Copyright 2024 Tomoaki Itoh
This software is released under the MIT License, see LICENSE.txt.
//*/

#include <stdint.h>

#define LCW_WAV_TABLE_BITS (10)
#define LCW_WAV_TABLE_SIZE (1 << LCW_WAV_TABLE_BITS)
#define LCW_WAV_TABLE_MASK (LCW_WAV_TABLE_SIZE - 1)
#define LCW_PULSE_TABLE_COUNT (4)

#ifdef __cplusplus
extern "C" {
#endif

// s3.12
typedef const int16_t LCWOscWaveTable[LCW_WAV_TABLE_SIZE];

// s3.12
extern LCWOscWaveTable lcwWaveTables[LCW_PULSE_TABLE_COUNT];

#ifdef __cplusplus
}
#endif
