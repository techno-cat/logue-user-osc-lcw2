/*
Copyright 2023 Tomoaki Itoh
This software is released under the MIT License, see LICENSE.txt.
//*/

#include "userosc.h"
#include "LCWCommon.h"
#include "LCWPitchTable.h"
#include "LCWWaveTable.h"
#include "LCWSoftClipTable.h"

#define LCW_OSC_TIMER_BITS (LCW_PITCH_DELTA_VALUE_BITS)
#define LCW_OSC_TIMER_MAX (1 << LCW_OSC_TIMER_BITS)
#define LCW_OSC_TIMER_MASK (LCW_OSC_TIMER_MAX - 1)

#define LCW_DELTA_TABLE_SIZE (48)
#define LCW_DELTA_TABLE_INDEX_MAX (LCW_DELTA_TABLE_SIZE - 1)
static const uint32_t lfoDeltaTable[LCW_DELTA_TABLE_SIZE] = {
    0x00022F, 0x000273, 0x0002C0, 0x000316, 0x000377, 0x0003E4,
    0x00045E, 0x0004E7, 0x000581, 0x00062D, 0x0006EF, 0x0007C8,
    0x0008BC, 0x0009CE, 0x000B02, 0x000C5B, 0x000DDE, 0x000F91,
    0x001179, 0x00139D, 0x001604, 0x0018B7, 0x001BBD, 0x001F23,
    0x0022F3, 0x00273B, 0x002C09, 0x00316E, 0x00377B, 0x003E47,
    0x0045E7, 0x004E77, 0x005813, 0x0062DC, 0x006EF7, 0x007C8E,
    0x008BCF, 0x009CEE, 0x00B026, 0x00C5B8, 0x00DDEF, 0x00F91D,
    0x01179E, 0x0139DC, 0x01604C, 0x018B71, 0x01BBDE, 0x01F23A
};

typedef struct
{
    uint32_t t1;
    uint32_t t2;
    uint32_t dt1;
    LCWOscWaveTable *table;
} LCWOscState;

typedef struct
{
    uint32_t t;
    uint32_t dt;
} LCWLfoState;

static struct
{
    float shape = 0;
    float shiftshape = 0;
    int32_t tableIndex = 0;
} s_param;

static struct
{
    LCWOscState osc[1];
    LCWLfoState lfo;
    int32_t pitch1 = 0; // s7.24
    int32_t shape_lfo = 0;
} s_state;

#define LCW_WAV_FRAC_BITS (LCW_OSC_TIMER_BITS - LCW_WAV_TABLE_BITS)
SQ3_12 lookupWaveTable(const LCWOscWaveTable *table, uint32_t t)
{
    const uint32_t i = t >> (LCW_OSC_TIMER_BITS - LCW_WAV_TABLE_BITS);
    const uint32_t frac =
        (t & (LCW_OSC_TIMER_MASK >> LCW_WAV_TABLE_BITS)) >> (LCW_WAV_FRAC_BITS - 8);
    const int32_t val1 = (int32_t)(*table)[i & LCW_WAV_TABLE_MASK];
    const int32_t val2 = (int32_t)(*table)[(i + 1) & LCW_WAV_TABLE_MASK];
    return (SQ3_12)(val1 + (((val2 - val1) * (int32_t)frac) >> 8));
}

SQ3_12 lookupSawWave(uint32_t t)
{
    if ( t < (LCW_OSC_TIMER_MAX >> 1) ) {
        // +0.25 -> -0.25 (x4)
        return LCW_SQ3_12(1.0) - (SQ3_12)((t * 4) >> (28 - 12));
    }
    else {
        // -0.25 -> +0.25 (x4)
        const uint32_t t2 = t - (LCW_OSC_TIMER_MAX >> 1);
        return LCW_SQ3_12(-1.0) + (SQ3_12)((t2 * 4) >> (28 - 12));
    }
}

void OSC_INIT(uint32_t platform, uint32_t api)
{
    s_param.shape = 0.f;
    s_param.shiftshape = 0.f;
    s_param.tableIndex = 0;

    s_state.osc[0].t1 = 0;
    s_state.osc[0].t2 = 0;
    s_state.osc[0].dt1 = 0;
    s_state.osc[0].table = &(lcwWaveTables[0]);
    s_state.lfo.t = 0;
    s_state.lfo.dt = 0;
    s_state.pitch1 = (LCW_NOTE_NO_A4 << 24) / 12;
    s_state.shape_lfo = 0;
}

#define LCW_PULSE_TABLE_INDEX_MAX (LCW_PULSE_TABLE_COUNT - 1)
void OSC_CYCLE(const user_osc_param_t *const params,
               int32_t *yn,
               const uint32_t frames)
{
    // s11.20に拡張してから、整数部がoctaveになるように加工
    int32_t pitch1 = (int32_t)params->pitch << 12;
    pitch1 = (pitch1 - (LCW_NOTE_NO_A4 << 20)) / 12;

    int32_t lfo_delta = (params->shape_lfo - s_state.shape_lfo) / (int32_t)frames;

    // s11.20 -> s7.24
    pitch1 <<= 4;

    // Temporaries.
    int32_t shape_lfo = s_state.shape_lfo;

    q31_t *__restrict y = (q31_t *)yn;
    const q31_t *y_e = y + frames;

    LCWOscState *osc = &(s_state.osc[0]);
    osc[0].table = &(lcwWaveTables[LCW_CLIP(s_param.tableIndex, 0, LCW_PULSE_TABLE_INDEX_MAX)]);

    const LCWOscWaveTable *modTable = &(lcwWaveTables[LCW_PULSE_TABLE_INDEX_MAX]);

    const uint32_t lfoDeltaParam = (uint32_t)((s_param.shiftshape * LCW_DELTA_TABLE_INDEX_MAX) + .5);
    const uint32_t lfoDeltaIndex = LCW_CLIP(lfoDeltaParam, 0, LCW_DELTA_TABLE_INDEX_MAX);
    LCWLfoState *lfo = &(s_state.lfo);
    lfo->dt = lfoDeltaTable[lfoDeltaIndex];

    // shiftshapeが0の場合は揺らさない
    const SQ15_16 modParam = LCW_SQ15_16((s_param.shape - .5f) * 2.f);
    const SQ15_16 modOrigin = lfoDeltaIndex == 0 ? modParam : 0;
    const SQ15_16 modDepth = lfoDeltaIndex == 0 ? 0 : modParam;

    for (; y != y_e;)
    {
        const int32_t out = (int32_t)lookupWaveTable(osc[0].table, osc[0].t2);
        *(y++) = (q31_t)(LCW_CLIP(out, -0x01000000, 0x00FFFFFF) << (31 - 12));

        osc[0].dt1 = pitch_to_timer_delta(pitch1 >> 8);
        osc[0].t1 = (osc[0].t1 + osc[0].dt1) & LCW_OSC_TIMER_MASK;

        // const SQ15_16 lfoOut = ((int32_t)lookupWaveTable(modTable, lfo->t) * modDepth) >> 12;
        const SQ15_16 lfoOut = ((int32_t)lookupSawWave(lfo->t) * modDepth) >> 12;
        lfo->t = (lfo->t + lfo->dt) & LCW_OSC_TIMER_MASK;

        const SQ3_12 modOut = lookupWaveTable(modTable, osc[0].t1);
        int32_t modValue = (int32_t)modOut * (modOrigin + lfoOut); // q28

        // -1.0 .. +1.0 になるようにソフトリミット
        modValue = lcwSoftClip16( modValue >> 12 ); // q28 -> q16

        const int32_t dt2 = (int32_t)osc[0].dt1 + (int32_t)( ((int64_t)osc[0].dt1 * modValue) >> 16 );
        osc[0].t2 = (osc[0].t2 + (uint32_t)dt2) & LCW_OSC_TIMER_MASK;

        shape_lfo += lfo_delta;
    }

    s_state.shape_lfo = params->shape_lfo;
    s_state.pitch1 = pitch1;
}

void OSC_NOTEON(const user_osc_param_t *const params)
{
    // memo: 誤差を吸収する仕組みがないので、ここで揃える
    LCWOscState *osc = &(s_state.osc[0]);
    osc[0].t1 =
    osc[0].t2 = 0;
}

void OSC_NOTEOFF(const user_osc_param_t *const params)
{
    return;
}

void OSC_PARAM(uint16_t index, uint16_t value)
{
    switch (index)
    {
    case k_user_osc_param_shape:
        s_param.shape = clip01f(param_val_to_f32(value));
        break;
    case k_user_osc_param_shiftshape:
        s_param.shiftshape = clip01f(param_val_to_f32(value));
        break;
    case k_user_osc_param_id1:
        s_param.tableIndex = (int32_t)value;
        break;
    default:
        break;
    }
}
