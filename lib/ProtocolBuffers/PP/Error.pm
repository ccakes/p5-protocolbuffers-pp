package ProtocolBuffers::PP::Error;
use strict;
use warnings;

use overload '""' => \&stringify, fallback => 1;

sub new {
    my ($class, %args) = @_;
    return bless {
        type    => $args{type}    || 'unknown',
        message => $args{message} || 'Unknown error',
    }, $class;
}

sub throw {
    my ($class_or_self, $type, $message) = @_;
    die $class_or_self->new(type => $type, message => $message);
}

sub type    { return $_[0]->{type} }
sub message { return $_[0]->{message} }

sub stringify {
    my ($self) = @_;
    return "ProtocolBuffers::PP::Error($self->{type}): $self->{message}";
}

1;

__END__

=head1 NAME

ProtocolBuffers::PP::Error - Structured error class for protobuf operations

=head1 SYNOPSIS

    use ProtocolBuffers::PP::Error;

    # Throw an error (dies with a blessed object)
    ProtocolBuffers::PP::Error->throw('decode', 'Truncated varint');

    # Catch and inspect
    eval { ... };
    if (ref $@ && $@->isa('ProtocolBuffers::PP::Error')) {
        warn "Error type: " . $@->type;
        warn "Message: "    . $@->message;
    }

=head1 DESCRIPTION

A lightweight error class that carries a category (type) and message.
Overloads stringification so errors can be used naturally with C<die>/C<eval>.

=head1 METHODS

=head2 new(%args)

    my $err = ProtocolBuffers::PP::Error->new(
        type    => 'decode',
        message => 'Truncated varint',
    );

Constructor. Accepts C<type> and C<message> named parameters.

=head2 throw($type, $message)

    ProtocolBuffers::PP::Error->throw('json', 'Invalid JSON: ...');

Class method that creates a new error and immediately C<die>s with it.

=head2 type()

Returns the error category string (e.g., C<'decode'>, C<'json'>).

=head2 message()

Returns the human-readable error message.

=head2 stringify()

Returns a formatted string: C<ProtocolBuffers::PP::Error(type): message>.
Called automatically when the object is used in string context.

=head1 SEE ALSO

L<ProtocolBuffers::PP::Decode>, L<ProtocolBuffers::PP::JSON::Parse>

=cut
