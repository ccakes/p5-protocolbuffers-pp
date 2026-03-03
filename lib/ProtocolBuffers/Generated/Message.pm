package ProtocolBuffers::Generated::Message;
use strict;
use warnings;
use parent 'ProtocolBuffers::Generated::Base';
use ProtocolBuffers::PP::Encode qw(encode_message);
use ProtocolBuffers::PP::Decode qw(decode_message);

sub new {
    my ($class, %args) = @_;
    my $desc = $class->__DESCRIPTOR__;
    my $self = {};

    # Initialize fields with defaults
    my $fields = $desc->{fields};
    for my $fn (keys %$fields) {
        my $fd = $fields->{$fn};
        my $name = $fd->{name};
        if ($fd->{map_entry}) {
            $self->{$name} = exists $args{$name} ? $args{$name} : {};
        } elsif ($fd->{label} == 3) {  # LABEL_REPEATED
            $self->{$name} = exists $args{$name} ? $args{$name} : [];
        } elsif (exists $args{$name}) {
            $self->{$name} = $args{$name};
            # Track oneof
            if (defined $fd->{oneof_index}) {
                $self->{_oneof_case} ||= {};
                $self->{_oneof_case}{$fd->{oneof_index}} = $fn;
            }
        }
    }

    # Copy _oneof_case if provided
    if (exists $args{_oneof_case}) {
        $self->{_oneof_case} = $args{_oneof_case};
    }

    return bless $self, $class;
}

sub encode {
    my ($self) = @_;
    return encode_message($self, $self->__DESCRIPTOR__);
}

sub decode {
    my ($class, $bytes) = @_;
    my $desc = $class->__DESCRIPTOR__;
    my $data = decode_message($desc, $bytes, $desc);

    # Recursively bless sub-messages
    _bless_recursive($data, $desc);

    return bless $data, $class;
}

sub _bless_recursive {
    my ($data, $desc) = @_;
    my $fields = $desc->{fields};
    for my $fn (keys %$fields) {
        my $fd = $fields->{$fn};
        my $name = $fd->{name};
        next unless exists $data->{$name} && defined $data->{$name};

        if ($fd->{map_entry} && $fd->{map_entry}{value_type} == 11) {
            # Map with message values
            my $val_desc = $fd->{map_entry}{value_message_descriptor};
            if ($val_desc && $val_desc->{_class}) {
                for my $k (keys %{$data->{$name}}) {
                    _bless_recursive($data->{$name}{$k}, $val_desc);
                    bless $data->{$name}{$k}, $val_desc->{_class};
                }
            }
        } elsif ($fd->{type} == 11 && $fd->{message_descriptor}) {  # TYPE_MESSAGE
            my $sub_desc = $fd->{message_descriptor};
            my $sub_class = $sub_desc->{_class};
            if ($fd->{label} == 3) {  # LABEL_REPEATED
                next unless ref $data->{$name} eq 'ARRAY';
                for my $elem (@{$data->{$name}}) {
                    if (ref $elem eq 'HASH') {
                        _bless_recursive($elem, $sub_desc);
                        bless $elem, $sub_class if $sub_class;
                    }
                }
            } else {
                if (ref $data->{$name} eq 'HASH') {
                    _bless_recursive($data->{$name}, $sub_desc);
                    bless $data->{$name}, $sub_class if $sub_class;
                }
            }
        }
    }
}

sub to_hash {
    my ($self) = @_;
    my %hash;
    my $desc = $self->__DESCRIPTOR__;
    for my $fn (keys %{$desc->{fields}}) {
        my $fd = $desc->{fields}{$fn};
        my $name = $fd->{name};
        next unless exists $self->{$name};
        $hash{$name} = $self->{$name};
    }
    return \%hash;
}

sub to_json {
    my ($self, %opts) = @_;
    require ProtocolBuffers::PP::JSON;
    return ProtocolBuffers::PP::JSON::encode_json_message($self, $self->__DESCRIPTOR__, %opts);
}

sub from_json {
    my ($class, $json_str, %opts) = @_;
    require ProtocolBuffers::PP::JSON;
    my $data = ProtocolBuffers::PP::JSON::decode_json_message($json_str, $class->__DESCRIPTOR__, %opts);
    _bless_recursive($data, $class->__DESCRIPTOR__);
    return bless $data, $class;
}

sub __DESCRIPTOR__ {
    die "Subclass must implement __DESCRIPTOR__";
}

1;

__END__

=head1 NAME

ProtocolBuffers::Generated::Message - Base class for generated protobuf message classes

=head1 SYNOPSIS

    # Generated code inherits from this class
    package My::Proto::Message;
    use parent 'ProtocolBuffers::Generated::Message';

    # Usage
    my $msg = My::Proto::Message->new(field1 => 'value');

    # Binary encoding/decoding
    my $bytes = $msg->encode();
    my $msg2  = My::Proto::Message->decode($bytes);

    # JSON encoding/decoding
    my $json = $msg->to_json();
    my $msg3 = My::Proto::Message->from_json($json);

    # Convert to plain hash
    my $hash = $msg->to_hash();

=head1 DESCRIPTION

Base class for all generated protobuf message classes. Provides constructors,
binary encoding/decoding, ProtoJSON serialization, and hash conversion.
Generated subclasses must implement C<__DESCRIPTOR__> to provide their field
definitions.

Messages are blessed hashrefs. Field access is done via generated accessor
methods on the subclass. Repeated fields default to empty arrayrefs, map
fields to empty hashrefs.

=head1 METHODS

=head2 new(%args)

Creates a new message with fields initialized from C<%args>. Repeated fields
default to C<[]>, map fields to C<{}>. Tracks oneof membership when oneof
fields are provided.

=head2 encode()

Serializes the message to Protocol Buffers binary format. Returns a byte
string.

=head2 decode($bytes)

Class method. Decodes binary protobuf bytes into a blessed message object.
Recursively blesses sub-messages using the C<_class> key from descriptors.

=head2 to_json(%opts)

Serializes the message to a ProtoJSON string. Options are passed through to
L<ProtocolBuffers::PP::JSON::Print/print_message>.

=head2 from_json($json_string, %opts)

Class method. Parses a ProtoJSON string into a blessed message object.
Options are passed through to L<ProtocolBuffers::PP::JSON::Parse/parse_message>.

=head2 to_hash()

Returns a plain (unblessed) hashref of the message's field values.

=head2 __DESCRIPTOR__()

Must be implemented by generated subclasses. Returns the message descriptor
hash containing field definitions, oneof declarations, and type metadata.

=head1 SEE ALSO

L<ProtocolBuffers::Generated::Base>, L<ProtocolBuffers::PP::Encode>,
L<ProtocolBuffers::PP::Decode>, L<ProtocolBuffers::PP::Generator>

=cut
