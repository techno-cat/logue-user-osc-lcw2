use v5.16;
use strict;
use warnings;

use constant FREQ_BASE => 440.0;
use constant TIMER_BITS => 28;

use constant FS => 48000;
use Math::Trig qw/pi tanh/;

use constant A4 => 69; # Note No. @ 440.0(Hz)
use constant PRE_RSHIFT => 8;

# NTS-1における、(pitch / 12)の結果における端数 * 16のこと
my $base_freq = 440.0 * (2 ** PRE_RSHIFT);
my $cnt = (12 * 16) + 1;
for (my $i=0; $i<$cnt; $i++) {
    my $tmp = 2 ** ($i / (16 * 12));
    my $f = ($base_freq * $tmp) / FS;
    my $fixed = int( ($f * (2 ** TIMER_BITS)) + .5 );
    printf("    0x%08X, // [%3d] %.6f, %7.4f\n",
        $fixed, $i, $tmp, $f);
}
