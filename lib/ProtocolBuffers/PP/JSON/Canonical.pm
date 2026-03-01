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
