package ProtocolBuffers::PP::Timestamp;
use strict;
use warnings;
use POSIX qw(floor);
use ProtocolBuffers::PP::Error;

use Exporter 'import';
our @EXPORT_OK = qw(timestamp_to_string string_to_timestamp);

# Convert {seconds, nanos} to RFC 3339 string
sub timestamp_to_string {
    my ($msg) = @_;
    my $seconds = $msg->{seconds} || 0;
    my $nanos = $msg->{nanos} || 0;

    # Validate range: 0001-01-01T00:00:00Z to 9999-12-31T23:59:59.999999999Z
    # Min: -62135596800, Max: 253402300799
    if ($seconds < -62135596800 || $seconds > 253402300799) {
        ProtocolBuffers::PP::Error->throw('json', "Timestamp out of range: $seconds");
    }

    my @t = gmtime($seconds);
    my $year = $t[5] + 1900;
    my $str = sprintf("%04d-%02d-%02dT%02d:%02d:%02d",
        $year, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);

    if ($nanos != 0) {
        # Add fractional seconds, trimming trailing zeros
        my $frac = sprintf("%09d", abs($nanos));
        $frac =~ s/0+$//;
        $str .= ".$frac";
    }

    $str .= "Z";
    return $str;
}

# Parse RFC 3339 string to {seconds, nanos}
sub string_to_timestamp {
    my ($str) = @_;

    unless ($str =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:\d{2})$/) {
        ProtocolBuffers::PP::Error->throw('json', "Invalid timestamp format: $str");
    }

    my ($year, $month, $day, $hour, $min, $sec, $frac, $tz) = ($1, $2, $3, $4, $5, $6, $7, $8);

    if ($year < 1 || $year > 9999) {
        ProtocolBuffers::PP::Error->throw('json', "Timestamp year out of range: $year");
    }

    # Convert to epoch using manual calculation (avoid timegm dependency)
    my $epoch = _timegm($sec, $min, $hour, $day, $month, $year);

    # Handle timezone offset
    if ($tz ne 'Z') {
        my ($sign, $tz_h, $tz_m) = ($tz =~ /^([+-])(\d{2}):(\d{2})$/);
        my $offset = ($tz_h * 3600 + $tz_m * 60) * ($sign eq '+' ? 1 : -1);
        $epoch -= $offset;
    }

    # Handle fractional seconds
    my $nanos = 0;
    if (defined $frac && $frac ne '') {
        # Pad to 9 digits
        $frac = substr($frac . '0' x 9, 0, 9);
        $nanos = int($frac);
    }

    return { seconds => $epoch, nanos => $nanos };
}

sub _timegm {
    my ($sec, $min, $hour, $day, $month, $year) = @_;
    # Days per month (non-leap)
    my @mdays = (0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);

    my $is_leap = ($year % 4 == 0 && ($year % 100 != 0 || $year % 400 == 0)) ? 1 : 0;

    # Days from year 1 to year-1
    my $y = $year - 1;
    my $days = $y * 365 + floor($y/4) - floor($y/100) + floor($y/400);

    # Add days for months
    for my $m (1 .. $month - 1) {
        $days += $mdays[$m];
        $days += 1 if $m == 2 && $is_leap;
    }
    $days += $day - 1;

    # Unix epoch is 1970-01-01 = day 719162 from year 1
    my $epoch_day = 719162;
    my $epoch = ($days - $epoch_day) * 86400 + $hour * 3600 + $min * 60 + $sec;

    return $epoch;
}

1;

__END__

=head1 NAME

ProtocolBuffers::PP::Timestamp - Conversion between protobuf Timestamp and RFC 3339 strings

=head1 SYNOPSIS

    use ProtocolBuffers::PP::Timestamp qw(timestamp_to_string string_to_timestamp);

    my $str = timestamp_to_string({ seconds => 1234567890, nanos => 0 });
    # "2009-02-13T23:31:30Z"

    my $msg = string_to_timestamp("2009-02-13T23:31:30Z");
    # { seconds => 1234567890, nanos => 0 }

=head1 DESCRIPTION

Converts between C<google.protobuf.Timestamp> message hashes (C<{seconds, nanos}>)
and RFC 3339 formatted strings as required by the ProtoJSON specification.

Supports nanosecond precision with trailing zero trimming, timezone offsets,
and validates the allowed timestamp range (0001-01-01 to 9999-12-31).

=head1 FUNCTIONS

=head2 timestamp_to_string($msg)

Converts a C<{seconds, nanos}> hash to an RFC 3339 string (always UTC with
"Z" suffix). Fractional seconds are included only when nanos is non-zero,
with trailing zeros trimmed.

=head2 string_to_timestamp($str)

Parses an RFC 3339 string into a C<{seconds, nanos}> hash. Handles timezone
offsets by converting to UTC. Throws a L<ProtocolBuffers::PP::Error> on
invalid format or out-of-range values.

=head1 SEE ALSO

L<ProtocolBuffers::PP::JSON::Print>, L<ProtocolBuffers::PP::JSON::Parse>

=cut
