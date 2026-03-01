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
