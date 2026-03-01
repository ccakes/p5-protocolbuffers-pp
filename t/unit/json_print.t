use strict;
use warnings;
use Test::More;
use lib 'lib';
use JSON::PP;
use ProtocolBuffers::PP::JSON::Print qw(print_message);
use ProtocolBuffers::PP::Types qw(
    TYPE_INT32 TYPE_INT64 TYPE_UINT64 TYPE_BOOL TYPE_STRING
    TYPE_BYTES TYPE_DOUBLE TYPE_FLOAT TYPE_ENUM TYPE_MESSAGE
    LABEL_OPTIONAL LABEL_REPEATED
);

my $json = JSON::PP->new->canonical(1)->allow_nonref(1)->utf8(1);

# Simple descriptor
my $desc = {
    full_name => 'test.Simple',
    syntax => 'proto3',
    fields => {
        1 => { name => 'id',     json_name => 'id',     number => 1, type => TYPE_INT32,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        2 => { name => 'name',   json_name => 'name',   number => 2, type => TYPE_STRING, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        3 => { name => 'active', json_name => 'active', number => 3, type => TYPE_BOOL,   label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        4 => { name => 'score',  json_name => 'score',  number => 4, type => TYPE_DOUBLE, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        5 => { name => 'big',    json_name => 'big',    number => 5, type => TYPE_INT64,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        6 => { name => 'data',   json_name => 'data',   number => 6, type => TYPE_BYTES,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
    },
    fields_by_name => { id => 1, name => 2, active => 3, score => 4, big => 5, data => 6 },
    fields_by_json_name => { id => 1, name => 2, active => 3, score => 4, big => 5, data => 6 },
    oneofs => [],
    is_map_entry => 0,
};

# Proto3 default omission
{
    my $msg = { id => 0, name => '', active => 0, score => 0.0 };
    my $result = print_message($msg, $desc);
    is($result, '{}', 'proto3 defaults omitted');
}

# Non-default values
{
    my $msg = { id => 42, name => 'hello', active => 1 };
    my $result = $json->decode(print_message($msg, $desc));
    is($result->{id}, 42, 'int32 value');
    is($result->{name}, 'hello', 'string value');
    is($result->{active}, JSON::PP::true, 'bool true');
}

# Int64 as string
{
    my $msg = { big => 9223372036854775807 };
    my $result = $json->decode(print_message($msg, $desc));
    is($result->{big}, '9223372036854775807', 'int64 as string');
}

# Bytes as base64
{
    my $msg = { data => "\x00\x01\x02\xFF" };
    my $result = $json->decode(print_message($msg, $desc));
    is($result->{data}, 'AAEC/w==', 'bytes as base64');
}

# Float special values
{
    my $float_desc = {
        full_name => 'test.FloatTest',
        syntax => 'proto3',
        fields => {
            1 => { name => 'val', json_name => 'val', number => 1, type => TYPE_FLOAT, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef, proto3_optional => 0 },
        },
        fields_by_name => { val => 1 },
        fields_by_json_name => { val => 1 },
        oneofs => [], is_map_entry => 0,
    };

    my $nan = unpack("f<", pack("V", 0x7FC00000));
    my $result = $json->decode(print_message({ val => $nan }, $float_desc));
    is($result->{val}, 'NaN', 'NaN as string');

    $result = $json->decode(print_message({ val => 9**9**9 }, $float_desc));
    is($result->{val}, 'Infinity', 'Infinity as string');

    $result = $json->decode(print_message({ val => -(9**9**9) }, $float_desc));
    is($result->{val}, '-Infinity', '-Infinity as string');
}

done_testing();
