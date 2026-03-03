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

__END__

=head1 NAME

ProtocolBuffers::PP::Duration - Conversion between protobuf Duration and string format

=head1 SYNOPSIS

    use ProtocolBuffers::PP::Duration qw(duration_to_string string_to_duration);

    my $str = duration_to_string({ seconds => 90, nanos => 500000000 });
    # "90.5s"

    my $msg = string_to_duration("90.5s");
    # { seconds => 90, nanos => 500000000 }

=head1 DESCRIPTION

Converts between C<google.protobuf.Duration> message hashes (C<{seconds, nanos}>)
and the ProtoJSON string format (e.g., C<"1.5s">, C<"-30s">).

Validates that seconds and nanos have consistent signs, and that seconds
are within the allowed range (E<plusmn>315,576,000,000).

=head1 FUNCTIONS

=head2 duration_to_string($msg)

Converts a C<{seconds, nanos}> hash to a duration string (e.g., C<"1.5s">).
Fractional seconds are included only when nanos is non-zero, with trailing
zeros trimmed.

=head2 string_to_duration($str)

Parses a duration string (e.g., C<"-30.5s">) into a C<{seconds, nanos}> hash.
Throws a L<ProtocolBuffers::PP::Error> on invalid format or out-of-range
values.

=head1 SEE ALSO

L<ProtocolBuffers::PP::JSON::Print>, L<ProtocolBuffers::PP::JSON::Parse>

=cut
