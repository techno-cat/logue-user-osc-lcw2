use v5.16;
use strict;
use warnings;

use constant TIMER_BITS => 28;
use constant FS => 48000;

# 10秒設定
my $delta_max = FS * 10;
my $n = 48;

my @lfo_delta_params = map {
    my $interval = $delta_max / (2 ** ($_ / 6));
    my $dt = int( (2 ** TIMER_BITS) / $interval );
    printf("    %6d, // [%2d] %7.2f(Hz)\n",
        $dt, $_, FS / $interval);
    $dt;
} 0..($n - 1);

say "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=";
say "LFO delta params";
dump_as_csv( \@lfo_delta_params );

sub dump_as_csv {
    my @tmp = @{$_[0]};

    while ( @tmp ) {
        my @items = map {
            #my $str = sprintf( '%08X', $_ );
            my $str = sprintf( '%06X', $_ );
            $str = substr($str, -8) if 8 < length($str);
            "0x${str}";
        } splice( @tmp, 0, 6 );

        printf( "    %s", join(', ', @items) );
        print(",") if @tmp;
        print("\n");
    }
}

sub my_round {
    my $val = shift;
    if ( $val < 0 ) {
        return -1 * int(-$val + 0.5);
    }
    else {
        return int($val + 0.5);
    }
}
