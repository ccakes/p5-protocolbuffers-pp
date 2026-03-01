package ProtocolBuffers::Generated::Enum;
use strict;
use warnings;

sub name_for {
    my ($class, $num) = @_;
    my $map = $class->_values();
    for my $name (keys %$map) {
        return $name if $map->{$name} == $num;
    }
    return undef;
}

sub value_for {
    my ($class, $name) = @_;
    my $map = $class->_values();
    return $map->{$name};
}

sub _values {
    die "Subclass must implement _values";
}

1;
