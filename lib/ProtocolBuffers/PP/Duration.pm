package ProtocolBuffers::PP::Duration;
use strict;
use warnings;
use ProtocolBuffers::PP::Error;

use Exporter 'import';
our @EXPORT_OK = qw(duration_to_string string_to_duration);

sub duration_to_string {
    my ($msg) = @_;
    my $seconds = $msg->{seconds} || 0;
    my $nanos = $msg->{nanos} || 0;

    # Validate: seconds and nanos must have same sign or be zero
    if ($seconds != 0 && $nanos != 0 && (($seconds > 0) != ($nanos > 0))) {
        ProtocolBuffers::PP::Error->throw('json', 'Duration seconds and nanos have different signs');
    }

    # Range: -315576000000 to +315576000000 seconds
    if ($seconds < -315576000000 || $seconds > 315576000000) {
        ProtocolBuffers::PP::Error->throw('json', "Duration seconds out of range: $seconds");
    }

    my $neg = ($seconds < 0 || $nanos < 0) ? 1 : 0;
    $seconds = abs($seconds);
    $nanos = abs($nanos);

    my $str = '';
    $str .= '-' if $neg;
    $str .= "${seconds}";

    if ($nanos != 0) {
        my $frac = sprintf("%09d", $nanos);
        $frac =~ s/0+$//;
        $str .= ".$frac";
    }

    $str .= 's';
    return $str;
}

sub string_to_duration {
    my ($str) = @_;

    unless ($str =~ /^(-?)(\d+)(?:\.(\d{1,9}))?s$/) {
        ProtocolBuffers::PP::Error->throw('json', "Invalid duration format: $str");
    }

    my ($neg, $sec_str, $frac) = ($1, $2, $3);
    my $seconds = int($sec_str);
    my $nanos = 0;

    if (defined $frac && $frac ne '') {
        $frac = substr($frac . '0' x 9, 0, 9);
        $nanos = int($frac);
    }

    if ($neg eq '-') {
        $seconds = -$seconds;
        $nanos = -$nanos if $nanos != 0;
    }

    # Range check: -315576000000 to +315576000000 seconds
    if ($seconds < -315576000000 || $seconds > 315576000000) {
        ProtocolBuffers::PP::Error->throw('json', "Duration seconds out of range: $seconds");
    }

    return { seconds => $seconds, nanos => $nanos };
}

1;
