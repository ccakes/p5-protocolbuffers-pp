package ProtocolBuffers::PP::FieldMask;
use strict;
use warnings;
use ProtocolBuffers::PP::Error;

use Exporter 'import';
our @EXPORT_OK = qw(field_mask_to_string string_to_field_mask);

sub field_mask_to_string {
    my ($msg) = @_;
    my $paths = $msg->{paths} || [];
    # Convert snake_case paths to camelCase
    my @camel = map { _snake_to_camel($_) } @$paths;
    return join(',', @camel);
}

sub string_to_field_mask {
    my ($str) = @_;
    return { paths => [] } if !defined $str || $str eq '';
    my @parts = split /,/, $str;
    my @paths = map { _camel_to_snake($_) } @parts;
    return { paths => \@paths };
}

sub _snake_to_camel {
    my ($s) = @_;
    $s =~ s/_([a-z])/uc($1)/ge;
    return $s;
}

sub _camel_to_snake {
    my ($s) = @_;
    $s =~ s/([A-Z])/'_' . lc($1)/ge;
    return $s;
}

1;
