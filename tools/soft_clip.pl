use v5.14;
use strict;
use warnings;
use constant X_MAX => 1024;
use constant Y_MAX =>  256;
use constant Y_MIN => -256;

use constant TABLE_SIZE_BITS => 5;
use constant X_LIMIT => 2;
use constant VALUE_MAX =>  0x100_0000; # q24
use constant VALUE_MIN => -VALUE_MAX;

use constant X_STEP => 4;

use Imager;
use Math::Trig qw/pi tanh/;
use List::Util qw/min max sum/;
use Data::Section::Simple qw/get_data_section/;
use Text::MicroTemplate qw(:all);

my $margin = 64;
my $width = $margin + (X_MAX + 1) + $margin;
my $height = $margin + (Y_MAX - Y_MIN + 1) + $margin;
my ( $x0, $y0 ) = ( $margin, $margin + (Y_MAX + 1) );

my @tables = (
    gen_soft_clip_table(0.7),
    gen_soft_clip_table()
);
draw_graph( 'soft_clip.png', \@tables );
# dump_table( $tables[0] );
write_as_c_header( 'LCWSoftClipTable.h' );
write_as_c_source( 'LCWSoftClipTable.c', $tables[0] );

sub write_as_c_header {
    my $dst_file = $_[0];

    my $template = get_data_section( 'header.tt' );
    chop $template if ( $template =~ /\n$/m );

    my $header = build_mt($template)->(TABLE_SIZE_BITS);
    open(my $fh, '>', $dst_file) or die;
    print $fh $header;
    close( $fh );
}

sub write_as_c_source {
    my $dst_file = $_[0];
    my $table = $_[1];

    my $template = get_data_section( 'table.tt' );
    chop $template if ( $template =~ /\n$/m );

    my $str = "";
    {
        my @tmp = @{$table};
        while ( @tmp ) {
            my @items = map {
                my $str = sprintf( '%08X', $_ );
                $str = substr($str, -8) if 8 < length($str);
                "0x${str}";
            } splice( @tmp, 0, 4 );

            $str .= "    ";
            $str .= join(', ', @items);
            $str .= ",\n" if @tmp;
        }
    }

    my $c_source = build_mt($template)->(TABLE_SIZE_BITS, $str);
    open(my $fh, '>', $dst_file) or die;
    print $fh $c_source;
    close( $fh );
}

sub dump_table {
    my $table = $_[0];

    my $n = 2 ** TABLE_SIZE_BITS;
    for (my $i=0; $i<$n; $i++) {
        my $val = $table->[$i] / VALUE_MAX;
        my $ratio = $i == 0 ? 1 : ($val / (($i / $n) * X_LIMIT));
        printf( "[%2d] %.4f -> %.4f (x%.6f)\n", $i, ($i / $n) * X_LIMIT, $val, $ratio );
    }
}

sub sinc {
    my $t = shift;
    return 1.0 if ( $t == 0.0 );
    return sin( $t * pi() ) / ( $t * pi() );
}

sub gen_soft_clip_table {
    my $step = $_[0] // 1.0;
    my $n = 2 ** TABLE_SIZE_BITS;
    my @tmp = map {
        tanh( $step * ($_ / $n) * X_LIMIT ) / $step;
    } 0..($n - 1);

    @tmp = map my_round($_ * VALUE_MAX), @tmp;

    return \@tmp;
}

sub draw_graph {
    my ( $dst_file, $sources ) = @_;

    my $img = Imager->new(
        xsize => $width, ysize => $height );
    $img->box( filled => 1, color => 'white' );
    draw_graduation( $img, Imager::Color->new(192, 192, 192) );

    my @hsva = Imager::Color->new('red')->hsv();
    my $dh = int( 270 / scalar(@{$sources}) );

    my $hue = $hsva[0] - $dh;
    foreach my $src ( @{$sources} ) {
        $hue += $dh;
        my $color = Imager::Color->new(
            hue => $hue, v => $hsva[1], s => $hsva[2] );

        my $table_size = 2 ** TABLE_SIZE_BITS;
        {
            my @tmp = ();
            my $t = 0;
            my $dt = X_STEP / X_MAX;
            for (my $x=0; $x<=X_MAX; $x+=X_STEP) {
                my $tt = $t * $table_size;
                my $i = int($tt);
                my $frac = int(($tt - $i) * 0x100);

                my $y1 = $src->[min($i, $table_size - 1)];
                my $y2 = $src->[min(($i + 1), $table_size - 1)];

                my $y = $y1 + int((($y2 - $y1) * $frac) / 0x100);

                push @tmp, [ $x, $y ];
                $t += $dt;
            }

            draw_polyline( $img, \@tmp, $color, 0.6 );
            plot_points( $img, \@tmp, $color, 0.4, 0 );
        }
    }

    $img->write( file => $dst_file ) or die $img->errstr;
}

sub draw_graduation {
    my ( $img, $color ) = @_;

    {
        my $gray = Imager::Color->new( 192, 192, 192 );

        my $x = 128;#($w / 4);
        while ( $x <= X_MAX ) {
            $img->line( color => $gray,
                x1 => $x0 + $x, y1 => $y0 + Y_MIN,
                x2 => $x0 + $x, y2 => $y0 + Y_MAX );
            $x += 128;#($w / 4);
        }

        my $y = 128;#($h / 4);
        while ( $y <= Y_MAX ) {
            $img->line( color => $gray,
                x1 => $x0 + 0,     y1 => $y0 - $y,
                x2 => $x0 + X_MAX, y2 => $y0 - $y );
            $img->line( color => $gray,
                x1 => $x0 + 0,     y1 => $y0 + $y,
                x2 => $x0 + X_MAX, y2 => $y0 + $y );
            $y += 128;#($h / 4);
        }
    }

    {
        $img->line( color => 'black',
            x1 => $x0, y1 => $y0 + Y_MIN,
            x2 => $x0, y2 => $y0 + Y_MAX );

        $img->line( color => 'black',
            x1 => $x0 + 0,     y1 => $y0,
            x2 => $x0 + X_MAX, y2 => $y0 );
    }
}

sub plot_points {
    my ( $img, $data, $color, $opacity, $filled ) = @_;
    $filled //= 0;
    my $n = 1;

    my $img_dst = $img;
    if ( defined($opacity) and $opacity < 1.0 ) {
        $img_dst = Imager->new(
            xsize => $img->getwidth(), ysize => $img->getheight(), channels => 4 );
    }

    foreach my $pt ( @{$data} ) {
        my ( $x, $y ) = ( $pt->[0], $pt->[1] );
        $y /= (VALUE_MAX / Y_MAX);
        $y = ( $y < .0 ) ? int($y - .5) : int($y + .5);
        #printf( "%6.3f, %6.3f\n", $x, $y );

        $img_dst->box(
            xmin => $x0 + $x - $n, ymin => $y0 - $y - $n,
            xmax => $x0 + $x + $n, ymax => $y0 - $y + $n,
            color => $color, filled => $filled );
    }

    if ( $img != $img_dst ) {
        $img->compose(
            src => $img_dst, opacity => $opacity );
    }
}

sub draw_polyline {
    my ( $img, $data, $color, $opacity ) = @_;

    my $img_dst = $img;
    if ( defined($opacity) and $opacity < 1.0 ) {
        $img_dst = Imager->new(
            xsize => $img->getwidth(), ysize => $img->getheight(), channels => 4 );
    }

    my @points = map {
        my ( $x, $y ) = ( $_->[0], $_->[1] );
        $y /= (VALUE_MAX / Y_MAX);
        $y = ( $y < .0 ) ? int($y - .5) : int($y + .5);
        [ $x0 + $x, $y0 - $y ];
    } @{$data};

    $img_dst->polyline( points => \@points, color => $color );

    if ( $img != $img_dst ) {
        $img->compose(
            src => $img_dst, opacity => $opacity );
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

__DATA__

@@ header.tt
/*
Copyright 2024 Tomoaki Itoh
This software is released under the MIT License, see LICENSE.txt.
//*/

#include "LCWCommon.h"

#ifdef __cplusplus
extern "C" {
#endif

// q16
extern SQ15_16 lcwSoftClip16(SQ15_16 x);

#ifdef __cplusplus
}
#endif

@@ table.tt
/*
Copyright 2024 Tomoaki Itoh
This software is released under the MIT License, see LICENSE.txt.
//*/

#include "LCWSoftClipTable.h"

#define LCW_SOFT_CLIP_TABLE_BITS (<?= $_[0] ?>)
#define LCW_SOFT_CLIP_TABLE_SIZE (1 << LCW_SOFT_CLIP_TABLE_BITS)
#define LCW_SOFT_CLIP_INDEX_MAX (LCW_SOFT_CLIP_TABLE_SIZE - 1)
#define LCW_SOFT_CLIP_BASE_BITS (LCW_SOFT_CLIP_TABLE_BITS - 1)

// q24
static SQ7_24 lcwSoftClipTable24[LCW_SOFT_CLIP_TABLE_SIZE] = {
<?= $_[1] ?>
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

@@ end_of_line.tt
