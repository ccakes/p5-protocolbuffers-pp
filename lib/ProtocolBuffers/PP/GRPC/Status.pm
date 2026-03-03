package ProtocolBuffers::PP::GRPC::Status;
use strict;
use warnings;
use Exporter 'import';

use constant {
    OK                  => 0,
    CANCELLED           => 1,
    UNKNOWN             => 2,
    INVALID_ARGUMENT    => 3,
    DEADLINE_EXCEEDED   => 4,
    NOT_FOUND           => 5,
    ALREADY_EXISTS      => 6,
    PERMISSION_DENIED   => 7,
    RESOURCE_EXHAUSTED  => 8,
    FAILED_PRECONDITION => 9,
    ABORTED             => 10,
    OUT_OF_RANGE        => 11,
    UNIMPLEMENTED       => 12,
    INTERNAL            => 13,
    UNAVAILABLE         => 14,
    DATA_LOSS           => 15,
    UNAUTHENTICATED     => 16,
};

our @EXPORT_OK = qw(
    OK CANCELLED UNKNOWN INVALID_ARGUMENT DEADLINE_EXCEEDED
    NOT_FOUND ALREADY_EXISTS PERMISSION_DENIED RESOURCE_EXHAUSTED
    FAILED_PRECONDITION ABORTED OUT_OF_RANGE UNIMPLEMENTED
    INTERNAL UNAVAILABLE DATA_LOSS UNAUTHENTICATED
);
our %EXPORT_TAGS = (all => \@EXPORT_OK);

my %NAMES = (
    0  => 'OK',
    1  => 'CANCELLED',
    2  => 'UNKNOWN',
    3  => 'INVALID_ARGUMENT',
    4  => 'DEADLINE_EXCEEDED',
    5  => 'NOT_FOUND',
    6  => 'ALREADY_EXISTS',
    7  => 'PERMISSION_DENIED',
    8  => 'RESOURCE_EXHAUSTED',
    9  => 'FAILED_PRECONDITION',
    10 => 'ABORTED',
    11 => 'OUT_OF_RANGE',
    12 => 'UNIMPLEMENTED',
    13 => 'INTERNAL',
    14 => 'UNAVAILABLE',
    15 => 'DATA_LOSS',
    16 => 'UNAUTHENTICATED',
);

sub name_for {
    my ($code) = @_;
    return $NAMES{$code} // 'UNKNOWN';
}

1;

__END__

=head1 NAME

ProtocolBuffers::PP::GRPC::Status - gRPC status code constants

=head1 SYNOPSIS

    use ProtocolBuffers::PP::GRPC::Status qw(:all);

    if ($result->{grpc_status} == OK) { ... }
    if ($result->{grpc_status} == DEADLINE_EXCEEDED) { ... }

    my $name = ProtocolBuffers::PP::GRPC::Status::name_for(4);
    # "DEADLINE_EXCEEDED"

=head1 DESCRIPTION

Defines the standard gRPC status codes as constants and provides a name
lookup function. All constants can be imported individually or via the
C<:all> export tag.

=head1 CONSTANTS

    OK                  (0)     CANCELLED           (1)
    UNKNOWN             (2)     INVALID_ARGUMENT    (3)
    DEADLINE_EXCEEDED   (4)     NOT_FOUND           (5)
    ALREADY_EXISTS      (6)     PERMISSION_DENIED   (7)
    RESOURCE_EXHAUSTED  (8)     FAILED_PRECONDITION (9)
    ABORTED             (10)    OUT_OF_RANGE        (11)
    UNIMPLEMENTED       (12)    INTERNAL            (13)
    UNAVAILABLE         (14)    DATA_LOSS           (15)
    UNAUTHENTICATED     (16)

=head1 FUNCTIONS

=head2 name_for($code)

Returns the string name for a numeric gRPC status code. Returns C<'UNKNOWN'>
for unrecognized codes.

=head1 SEE ALSO

L<ProtocolBuffers::PP::GRPC::Client>

=cut
