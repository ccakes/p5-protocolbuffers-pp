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

__END__

=head1 NAME

ProtocolBuffers::PP::FieldMask - Conversion between protobuf FieldMask and string format

=head1 SYNOPSIS

    use ProtocolBuffers::PP::FieldMask qw(field_mask_to_string string_to_field_mask);

    my $str = field_mask_to_string({ paths => ['foo_bar', 'baz_qux'] });
    # "fooBar,bazQux"

    my $msg = string_to_field_mask("fooBar,bazQux");
    # { paths => ['foo_bar', 'baz_qux'] }

=head1 DESCRIPTION

Converts between C<google.protobuf.FieldMask> message hashes
(C<{paths =E<gt> [...]}>) and the ProtoJSON string format (comma-separated
camelCase paths).

=head1 FUNCTIONS

=head2 field_mask_to_string($msg)

Converts a FieldMask hash to a comma-separated string of camelCase paths.

=head2 string_to_field_mask($str)

Parses a comma-separated camelCase string into a FieldMask hash with
snake_case paths. Returns C<{paths =E<gt> []}> for empty or undefined input.

=head1 SEE ALSO

L<ProtocolBuffers::PP::JSON::Print>, L<ProtocolBuffers::PP::JSON::Parse>

=cut
