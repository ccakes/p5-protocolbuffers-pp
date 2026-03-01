use strict;
use warnings;
use Test::More;
use lib 'lib';
use ProtocolBuffers::PP::Encode qw(encode_message);
use ProtocolBuffers::PP::Decode qw(decode_message);
use ProtocolBuffers::PP::Types qw(
    TYPE_INT32 TYPE_INT64 TYPE_UINT32 TYPE_UINT64
    TYPE_SINT32 TYPE_SINT64 TYPE_BOOL TYPE_STRING TYPE_BYTES
    TYPE_DOUBLE TYPE_FLOAT TYPE_FIXED32 TYPE_FIXED64
    TYPE_SFIXED32 TYPE_SFIXED64 TYPE_ENUM TYPE_MESSAGE
    LABEL_OPTIONAL LABEL_REPEATED
);

# Simple scalar message: message Test { int32 id = 1; string name = 2; bool active = 3; }
my $simple_desc = {
    full_name => 'test.Simple',
    syntax => 'proto3',
    fields => {
        1 => { name => 'id',     number => 1, type => TYPE_INT32,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        2 => { name => 'name',   number => 2, type => TYPE_STRING, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        3 => { name => 'active', number => 3, type => TYPE_BOOL,   label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
    },
    fields_by_name => { id => 1, name => 2, active => 3 },
    oneofs => [],
    is_map_entry => 0,
};

# Roundtrip basic scalars
{
    my $msg = { id => 42, name => 'hello', active => 1 };
    my $bytes = encode_message($msg, $simple_desc);
    ok(length($bytes) > 0, 'encoded non-empty');
    my $decoded = decode_message($simple_desc, $bytes, $simple_desc);
    is($decoded->{id}, 42, 'decoded id');
    is($decoded->{name}, 'hello', 'decoded name');
    is($decoded->{active}, 1, 'decoded active');
}

# Proto3 default omission
{
    my $msg = { id => 0, name => '', active => 0 };
    my $bytes = encode_message($msg, $simple_desc);
    is($bytes, '', 'proto3 defaults produce empty encoding');
}

# Non-default values
{
    my $msg = { id => -1, name => 'test', active => 0 };
    my $bytes = encode_message($msg, $simple_desc);
    my $decoded = decode_message($simple_desc, $bytes, $simple_desc);
    is($decoded->{id}, -1, 'negative int32');
    is($decoded->{name}, 'test', 'string');
}

# Repeated field: message TestRepeated { repeated int32 values = 1; repeated string names = 2; }
my $repeated_desc = {
    full_name => 'test.Repeated',
    syntax => 'proto3',
    fields => {
        1 => { name => 'values', number => 1, type => TYPE_INT32,  label => LABEL_REPEATED, packed => 1, oneof_index => undef },
        2 => { name => 'names',  number => 2, type => TYPE_STRING, label => LABEL_REPEATED, packed => 0, oneof_index => undef },
    },
    fields_by_name => { values => 1, names => 2 },
    oneofs => [],
    is_map_entry => 0,
};

{
    my $msg = { values => [1, 2, 3, 4, 5], names => ['a', 'b', 'c'] };
    my $bytes = encode_message($msg, $repeated_desc);
    my $decoded = decode_message($repeated_desc, $bytes, $repeated_desc);
    is_deeply($decoded->{values}, [1, 2, 3, 4, 5], 'packed repeated int32');
    is_deeply($decoded->{names}, ['a', 'b', 'c'], 'repeated string');
}

# Empty repeated
{
    my $msg = { values => [], names => [] };
    my $bytes = encode_message($msg, $repeated_desc);
    is($bytes, '', 'empty repeated produces empty encoding');
    my $decoded = decode_message($repeated_desc, $bytes, $repeated_desc);
    is_deeply($decoded->{values}, [], 'empty repeated decoded');
    is_deeply($decoded->{names}, [], 'empty repeated strings decoded');
}

# Nested message
my $inner_desc = {
    full_name => 'test.Inner',
    syntax => 'proto3',
    fields => {
        1 => { name => 'value', number => 1, type => TYPE_INT32, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
    },
    fields_by_name => { value => 1 },
    oneofs => [],
    is_map_entry => 0,
};

my $outer_desc = {
    full_name => 'test.Outer',
    syntax => 'proto3',
    fields => {
        1 => { name => 'inner', number => 1, type => TYPE_MESSAGE, label => LABEL_OPTIONAL, packed => 0,
               oneof_index => undef, proto3_optional => 0, message_descriptor => $inner_desc },
        2 => { name => 'tag',   number => 2, type => TYPE_STRING,  label => LABEL_OPTIONAL, packed => 0,
               oneof_index => undef, proto3_optional => 0 },
    },
    fields_by_name => { inner => 1, tag => 2 },
    oneofs => [],
    is_map_entry => 0,
};

{
    my $msg = { inner => { value => 99 }, tag => 'nested' };
    my $bytes = encode_message($msg, $outer_desc);
    my $decoded = decode_message($outer_desc, $bytes, $outer_desc);
    is($decoded->{inner}{value}, 99, 'nested message value');
    is($decoded->{tag}, 'nested', 'outer tag');
}

# Unknown fields preservation
{
    # Encode with the simple descriptor (has fields 1,2,3)
    my $msg = { id => 42, name => 'hello', active => 1 };
    my $bytes = encode_message($msg, $simple_desc);

    # Decode with a descriptor that only knows field 1
    my $partial_desc = {
        full_name => 'test.Partial',
        syntax => 'proto3',
        fields => {
            1 => { name => 'id', number => 1, type => TYPE_INT32, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        },
        fields_by_name => { id => 1 },
        oneofs => [],
        is_map_entry => 0,
    };

    my $decoded = decode_message($partial_desc, $bytes, $partial_desc);
    is($decoded->{id}, 42, 'known field preserved');
    ok(defined $decoded->{_unknown_fields}, 'unknown fields captured');
    ok(length($decoded->{_unknown_fields}) > 0, 'unknown fields non-empty');

    # Re-encode with unknown fields
    my $re_encoded = encode_message($decoded, $partial_desc);
    # Decode again with full descriptor
    my $full_decoded = decode_message($simple_desc, $re_encoded, $simple_desc);
    is($full_decoded->{id}, 42, 'id preserved through unknown fields');
    is($full_decoded->{name}, 'hello', 'name preserved through unknown fields');
    is($full_decoded->{active}, 1, 'active preserved through unknown fields');
}

# All numeric types
my $all_nums_desc = {
    full_name => 'test.AllNums',
    syntax => 'proto3',
    fields => {
        1  => { name => 'f_double',   number => 1,  type => TYPE_DOUBLE,   label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        2  => { name => 'f_float',    number => 2,  type => TYPE_FLOAT,    label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        3  => { name => 'f_int64',    number => 3,  type => TYPE_INT64,    label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        4  => { name => 'f_uint64',   number => 4,  type => TYPE_UINT64,   label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        5  => { name => 'f_int32',    number => 5,  type => TYPE_INT32,    label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        6  => { name => 'f_fixed64',  number => 6,  type => TYPE_FIXED64,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        7  => { name => 'f_fixed32',  number => 7,  type => TYPE_FIXED32,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        8  => { name => 'f_uint32',   number => 8,  type => TYPE_UINT32,   label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        9  => { name => 'f_sfixed32', number => 9,  type => TYPE_SFIXED32, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        10 => { name => 'f_sfixed64', number => 10, type => TYPE_SFIXED64, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        11 => { name => 'f_sint32',   number => 11, type => TYPE_SINT32,   label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        12 => { name => 'f_sint64',   number => 12, type => TYPE_SINT64,   label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        13 => { name => 'f_enum',     number => 13, type => TYPE_ENUM,     label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        14 => { name => 'f_bytes',    number => 14, type => TYPE_BYTES,    label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
    },
    fields_by_name => {
        f_double => 1, f_float => 2, f_int64 => 3, f_uint64 => 4, f_int32 => 5,
        f_fixed64 => 6, f_fixed32 => 7, f_uint32 => 8, f_sfixed32 => 9, f_sfixed64 => 10,
        f_sint32 => 11, f_sint64 => 12, f_enum => 13, f_bytes => 14,
    },
    oneofs => [],
    is_map_entry => 0,
};

{
    my $msg = {
        f_double   => 3.14,
        f_float    => 1.5,
        f_int64    => -9223372036854775808,
        f_uint64   => 18446744073709551615,
        f_int32    => -2147483648,
        f_fixed64  => 12345678901234,
        f_fixed32  => 4294967295,
        f_uint32   => 4294967295,
        f_sfixed32 => -100,
        f_sfixed64 => -200,
        f_sint32   => -300,
        f_sint64   => -400,
        f_enum     => 2,
        f_bytes    => "\x00\x01\xFF",
    };
    my $bytes = encode_message($msg, $all_nums_desc);
    my $decoded = decode_message($all_nums_desc, $bytes, $all_nums_desc);

    ok(abs($decoded->{f_double} - 3.14) < 1e-10, 'double roundtrip');
    ok(abs($decoded->{f_float} - 1.5) < 1e-6, 'float roundtrip');
    is($decoded->{f_int64}, -9223372036854775808, 'int64 min');
    is($decoded->{f_uint64}, 18446744073709551615, 'uint64 max');
    is($decoded->{f_int32}, -2147483648, 'int32 min');
    is($decoded->{f_fixed64}, 12345678901234, 'fixed64');
    is($decoded->{f_fixed32}, 4294967295, 'fixed32 max');
    is($decoded->{f_uint32}, 4294967295, 'uint32 max');
    is($decoded->{f_sfixed32}, -100, 'sfixed32');
    is($decoded->{f_sfixed64}, -200, 'sfixed64');
    is($decoded->{f_sint32}, -300, 'sint32');
    is($decoded->{f_sint64}, -400, 'sint64');
    is($decoded->{f_enum}, 2, 'enum');
    is($decoded->{f_bytes}, "\x00\x01\xFF", 'bytes');
}

# Oneof field
my $oneof_desc = {
    full_name => 'test.OneofTest',
    syntax => 'proto3',
    fields => {
        1 => { name => 'id',    number => 1, type => TYPE_INT32,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        5 => { name => 'str_val', number => 5, type => TYPE_STRING, label => LABEL_OPTIONAL, packed => 0, oneof_index => 0, proto3_optional => 0 },
        6 => { name => 'int_val', number => 6, type => TYPE_INT32,  label => LABEL_OPTIONAL, packed => 0, oneof_index => 0, proto3_optional => 0 },
        7 => { name => 'msg_val', number => 7, type => TYPE_MESSAGE, label => LABEL_OPTIONAL, packed => 0, oneof_index => 0, proto3_optional => 0,
               message_descriptor => $inner_desc },
    },
    fields_by_name => { id => 1, str_val => 5, int_val => 6, msg_val => 7 },
    oneofs => [ { name => 'test_oneof', fields => [5, 6, 7] } ],
    is_map_entry => 0,
};

{
    my $msg = { id => 1, str_val => 'hello', _oneof_case => { 0 => 5 } };
    my $bytes = encode_message($msg, $oneof_desc);
    my $decoded = decode_message($oneof_desc, $bytes, $oneof_desc);
    is($decoded->{id}, 1, 'oneof: id');
    is($decoded->{str_val}, 'hello', 'oneof: str_val active');
    ok(!defined $decoded->{int_val}, 'oneof: int_val not set');
    is($decoded->{_oneof_case}{0}, 5, 'oneof: case tracks field 5');
}

# Proto3 optional (has-presence)
my $opt_desc = {
    full_name => 'test.OptionalTest',
    syntax => 'proto3',
    fields => {
        1 => { name => 'opt_int', number => 1, type => TYPE_INT32, label => LABEL_OPTIONAL, packed => 0,
               oneof_index => 0, proto3_optional => 1 },
    },
    fields_by_name => { opt_int => 1 },
    oneofs => [ { name => '_opt_int', fields => [1] } ],
    is_map_entry => 0,
};

{
    # Even zero should be encoded for proto3_optional
    my $msg = { opt_int => 0, _oneof_case => { 0 => 1 } };
    my $bytes = encode_message($msg, $opt_desc);
    ok(length($bytes) > 0, 'proto3_optional: zero is encoded');
    my $decoded = decode_message($opt_desc, $bytes, $opt_desc);
    is($decoded->{opt_int}, 0, 'proto3_optional: zero roundtrips');
    is($decoded->{_oneof_case}{0}, 1, 'proto3_optional: case set');
}

done_testing();
