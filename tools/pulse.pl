use v5.14;
use strict;
use warnings;
use constant X_MAX => 1024;
use constant Y_MAX =>  256;
use constant Y_MIN => -256;

use constant TABLE_SIZE_BITS => 10;
use constant VALUE_MAX =>  0x1000; # s3.12
use constant VALUE_MIN => -VALUE_MAX;

use constant X_STEP => 1;

use Imager;
use Math::Trig qw/pi tanh/;
use List::Util qw/min max sum/;
use Data::Section::Simple qw/get_data_section/;
use Text::MicroTemplate qw(:all);

my $margin = 8;
my $width = $margin + (X_MAX + 1) + $margin;
my $height = $margin + (Y_MAX - Y_MIN + 1) + $margin;
my ( $x0, $y0 ) = ( $margin, $margin + (Y_MAX + 1) );

my @pulse_tables = (
    gen_pulse_table(),
    gen_saw_table(),
    gen_tri_table(),
    gen_sin_table()
);

my @graph_sources = (
    gen_pulse_table(),
    gen_saw_table(),
    gen_tri_table(),
    gen_sin_table()
);

draw_graph_mod( 'pulse.png', \@graph_sources, 1.0 );
write_as_c_header( 'LCWWaveTable.h', \@pulse_tables );
write_as_c_source( 'LCWWaveTable.c', \@pulse_tables );

sub write_as_c_header {
    my $dst_file = $_[0];
    my $table_count = scalar(@{$_[1]});

    my $template = get_data_section( 'header.tt' );
    chop $template if ( $template =~ /\n$/m );

    my $header = build_mt($template)->(TABLE_SIZE_BITS, $table_count);
    open(my $fh, '>', $dst_file) or die;
    print $fh $header;
    close( $fh );
}

sub write_as_c_source {
    my $dst_file = $_[0];
    my @tables = @{$_[1]};

    my $template = get_data_section( 'table.tt' );
    chop $template if ( $template =~ /\n$/m );

    my $str = "";
    while ( my $table = shift @tables ) {
        my @tmp = @{$table};
        $str .= "    {\n";
        while ( @tmp ) {
            my @items = map {
                my $str = sprintf( '%04X', $_ );
                $str = substr($str, -4) if 4 < length($str);
                "0x${str}";
            } splice( @tmp, 0, 8 );

            $str .= "        ";
            $str .= join(', ', @items);
            $str .= "," if @tmp;
            $str .= "\n";
        }
        $str .= "    }";
        $str .= ",\n" if @tables;
    }

    my $c_source = build_mt($template)->($str);
    open(my $fh, '>', $dst_file) or die;
    print $fh $c_source;
    close( $fh );
}

sub dump_as_csv {
    my @tables = @{$_[0]};

    while ( my $table = shift @tables ) {
        my @tmp = @{$table};
        print("    {\n");
        while ( @tmp ) {
            my @items = map {
                my $str = sprintf( '%04X', $_ );
                $str = substr($str, -4) if 4 < length($str);
                "0x${str}";
            } splice( @tmp, 0, 8 );

            printf( "        %s", join(', ', @items) );
            print(",") if @tmp;
            print("\n");
        }
        print("    }");
        print(",") if @tables;
        print("\n");
    }
}

sub gen_sin_table {
    my $n = 2 ** TABLE_SIZE_BITS;
    my @tmp = map {
        my $i = $_;
        my $val = sin( ($i / $n) * 2 * pi );
        ( $val * VALUE_MAX );
    } 0..($n - 1);

    return \@tmp;
}

sub gen_pulse_table {
    my $n = 2 ** TABLE_SIZE_BITS;
    my @tmp = map 0, 0..($n - 1);

    for ( 0..63 ) {
        my $fn = ($_ * 2) + 1;
        my $gain = 1 / $fn;

        for (my $i=0; $i<$n; $i++) {
            $tmp[$i] += $gain * sin( $fn * ($i / $n) * 2 * pi );
        }
    }

    @tmp = map $_ * (pi / 3), @tmp;
    @tmp = map my_round($_ * VALUE_MAX), @tmp;

    return \@tmp;
}

sub gen_saw_table {
    my $n = 2 ** TABLE_SIZE_BITS;
    my @tmp = map 0, 0..($n - 1);

    for ( 0..127 ) {
        my $fn = $_ + 1;
        my $gain = (($_ & 0x1) ? -1 : 1) / $fn;

        for (my $i=0; $i<$n; $i++) {
            $tmp[$i] += $gain * sin( $fn * ($i / $n) * 2 * pi );
        }
    }

    @tmp = map $_ * 0.5, @tmp;
    @tmp = map my_round($_ * VALUE_MAX), @tmp;

    return \@tmp;
}

sub gen_tri_table {
    my $n = 2 ** TABLE_SIZE_BITS;
    my @tmp = map 0, 0..($n - 1);

    for ( 0..63 ) {
        my $fn = ($_ * 2) + 1;
        my $gain = (($_ & 0x1) ? -1 : 1) / ($fn ** 2);

        for (my $i=0; $i<$n; $i++) {
            $tmp[$i] += $gain * sin( $fn * ($i / $n) * 2 * pi );
        }
    }

    @tmp = map $_ * (pi / 4), @tmp;
    @tmp = map my_round($_ * VALUE_MAX), @tmp;

    return \@tmp;
}

sub sinc {
    my $t = shift;
    return 1.0 if ( $t == 0.0 );
    return sin( $t * pi() ) / ( $t * pi() );
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
        my $table_mask = $table_size - 1;
        {
            my @tmp = ();
            my $t = 0;
            my $dt = X_STEP / X_MAX;
            for (my $x=0; $x<=X_MAX; $x+=X_STEP) {
                my $tt = $t * $table_size;
                my $i = int($tt);
                my $frac = int(($tt - $i) * 0x100);

                my $y1 = $src->[$i & $table_mask];
                my $y2 = $src->[($i + 1) & $table_mask];

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

sub draw_graph_mod {
    my ( $dst_file, $sources, $depth ) = @_;
    $depth //= 0;

    my $img = Imager->new(
        xsize => $width, ysize => $height );
    $img->box( filled => 1, color => 'white' );
    draw_graduation( $img, Imager::Color->new(192, 192, 192) );

    my @hsva = Imager::Color->new('red')->hsv();
    my $dh = int( 270 / scalar(@{$sources}) );

    my $hue = $hsva[0] - $dh;
    {
        my $color = Imager::Color->new(
            hue => $hue, v => $hsva[1], s => $hsva[2] );

        my @tmp1 = ();
        my @tmp2 = ();
        my $t1 = 0;
        my $t2 = 0;
        my $dt = X_STEP / X_MAX;
        for (my $x=0; $x<=X_MAX; $x+=X_STEP) {
            my $mod_value = sin( $t1 * 2 * pi ) * $dt;

            push @tmp1, [ $x, my_round($t1 * VALUE_MAX) ];
            push @tmp2, [ $x, my_round($t2 * VALUE_MAX) ];
            $t1 += $dt;
            $t2 += ($dt + ($mod_value * $depth));
        }

        draw_polyline( $img, \@tmp1, $color, 0.4 );
        draw_polyline( $img, \@tmp2, $color, 0.4 );
        plot_points( $img, \@tmp2, $color, 0.4, 0 );
    }

    foreach my $src ( @{$sources} ) {
        $hue += $dh;
        my $color = Imager::Color->new(
            hue => $hue, v => $hsva[1], s => $hsva[2] );

        my $table_size = 2 ** TABLE_SIZE_BITS;
        my $table_mask = $table_size - 1;
        {
            my @tmp = ();
            my $t1 = 0;
            my $t2 = 0;
            my $dt = X_STEP / X_MAX;
            for (my $x=0; $x<=X_MAX; $x+=X_STEP) {
                my $mod_value = sin( $t1 * 2 * pi ) * $dt;

                my $tt = $t2 * $table_size;
                my $i = int($tt);
                my $frac = int(($tt - $i) * 0x100);

                my $y1 = $src->[$i & $table_mask];
                my $y2 = $src->[($i + 1) & $table_mask];

                my $y = $y1 + int((($y2 - $y1) * $frac) / 0x100);

                push @tmp, [ $x, $y ];
                $t1 += $dt;
                $t2 += ($dt + ($mod_value * $depth));
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

#include <stdint.h>

#define LCW_WAV_TABLE_BITS (<?= $_[0] ?>)
#define LCW_WAV_TABLE_SIZE (1 << LCW_WAV_TABLE_BITS)
#define LCW_WAV_TABLE_MASK (LCW_WAV_TABLE_SIZE - 1)
#define LCW_PULSE_TABLE_COUNT (<?= $_[1] ?>)

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

@@ table.tt
/*
Copyright 2024 Tomoaki Itoh
This software is released under the MIT License, see LICENSE.txt.
//*/

#include "LCWWaveTable.h"

LCWOscWaveTable lcwWaveTables[LCW_PULSE_TABLE_COUNT] = {
<?= $_[0] ?>
};

@@ end_of_line.tt
