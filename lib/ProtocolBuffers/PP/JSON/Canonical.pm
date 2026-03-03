package ProtocolBuffers::PP::JSON::Canonical;
use strict;
use warnings;
use JSON::PP;

use Exporter 'import';
our @EXPORT_OK = qw(canonical_json_encode);

my $json_pp = JSON::PP->new->canonical(1)->allow_nonref(1)->allow_bignum(1);

sub canonical_json_encode {
    my ($data) = @_;
    return $json_pp->encode($data);
}

1;

__END__

=head1 NAME

ProtocolBuffers::PP::JSON::Canonical - Canonical JSON encoding

=head1 SYNOPSIS

    use ProtocolBuffers::PP::JSON::Canonical qw(canonical_json_encode);

    my $json = canonical_json_encode($data);

=head1 DESCRIPTION

Provides deterministic JSON encoding with sorted keys and big number support.
Used internally for producing canonical JSON output independent of the
ProtoJSON format.

=head1 FUNCTIONS

=head2 canonical_json_encode($data)

Encodes a Perl data structure to a canonical JSON string with sorted keys.
Supports L<Math::BigInt>/L<Math::BigFloat> values via L<JSON::PP>'s
C<allow_bignum> option.

=head1 SEE ALSO

L<ProtocolBuffers::PP::JSON::Print>

=cut
