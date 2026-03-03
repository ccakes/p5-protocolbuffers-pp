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

__END__

=head1 NAME

ProtocolBuffers::Generated::Enum - Base class for generated protobuf enum classes

=head1 SYNOPSIS

    # Generated code inherits from this class
    package My::Proto::Status;
    use parent 'ProtocolBuffers::Generated::Enum';

    # Usage
    my $name = My::Proto::Status->name_for(1);   # e.g., "ACTIVE"
    my $num  = My::Proto::Status->value_for("ACTIVE");  # 1

=head1 DESCRIPTION

Base class for all generated protobuf enum classes. Provides bidirectional
name-to-value lookup. Generated subclasses must implement C<_values> to
return their value mapping.

=head1 METHODS

=head2 name_for($number)

Class method. Returns the enum name for a given numeric value, or C<undef>
if not found.

=head2 value_for($name)

Class method. Returns the numeric value for a given enum name, or C<undef>
if not found.

=head2 _values()

Must be implemented by generated subclasses. Returns a hashref mapping
enum names to their numeric values.

=head1 SEE ALSO

L<ProtocolBuffers::Generated::Base>, L<ProtocolBuffers::PP::Generator>

=cut
