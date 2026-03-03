package ProtocolBuffers::Generated::Base;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless {%args}, $class;
}

1;

__END__

=head1 NAME

ProtocolBuffers::Generated::Base - Base class for generated protobuf types

=head1 SYNOPSIS

    package My::Message;
    use parent 'ProtocolBuffers::Generated::Base';

=head1 DESCRIPTION

Provides a minimal constructor for generated protobuf classes. Both
L<ProtocolBuffers::Generated::Message> and L<ProtocolBuffers::Generated::Enum>
inherit from this class.

=head1 METHODS

=head2 new(%args)

Creates a blessed hashref from the given key-value pairs.

=head1 SEE ALSO

L<ProtocolBuffers::Generated::Message>, L<ProtocolBuffers::Generated::Enum>

=cut
