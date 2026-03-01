use strict;
use warnings;
use Test::More;
use lib 'lib';

# Load the generated code
do "./lib/Test.pm" or die $@ || $!;

# Basic scalar roundtrip
{
    my $msg = Test::Simple->new(id => 42, name => 'hello', active => 1, score => 3.14);
    my $bytes = $msg->encode();
    ok(length($bytes) > 0, 'encoded non-empty');

    my $decoded = Test::Simple->decode($bytes);
    is($decoded->id, 42, 'id roundtrip');
    is($decoded->name, 'hello', 'name roundtrip');
    is($decoded->active, 1, 'active roundtrip');
    ok(abs($decoded->score - 3.14) < 1e-10, 'score roundtrip');
}

# Nested message
{
    my $msg = Test::Simple->new(
        id => 1,
        inner => Test::Inner->new(value => 99, label => 'nested'),
    );
    my $bytes = $msg->encode();
    my $decoded = Test::Simple->decode($bytes);
    is($decoded->id, 1, 'id with nested');
    ok(defined $decoded->inner, 'inner exists');
    is($decoded->inner->value, 99, 'inner value');
    is($decoded->inner->label, 'nested', 'inner label');
}

# Repeated fields
{
    my $msg = Test::Simple->new(
        tags => [1, 2, 3, 4, 5],
        items => [
            Test::Inner->new(value => 10, label => 'a'),
            Test::Inner->new(value => 20, label => 'b'),
        ],
    );
    my $bytes = $msg->encode();
    my $decoded = Test::Simple->decode($bytes);
    is_deeply($decoded->tags, [1, 2, 3, 4, 5], 'packed repeated int32');
    is(scalar @{$decoded->items}, 2, 'repeated message count');
    is($decoded->items->[0]->value, 10, 'repeated msg[0] value');
    is($decoded->items->[1]->label, 'b', 'repeated msg[1] label');
}

# Enum
{
    my $msg = Test::Simple->new(color => Test::Color->BLUE);
    my $bytes = $msg->encode();
    my $decoded = Test::Simple->decode($bytes);
    is($decoded->color, 2, 'enum value');
    is(Test::Color->name_for(2), 'BLUE', 'enum name lookup');
    is(Test::Color->value_for('GREEN'), 1, 'enum value lookup');
}

# Map
{
    my $msg = Test::Simple->new(metadata => { 'key1' => 10, 'key2' => 20 });
    my $bytes = $msg->encode();
    my $decoded = Test::Simple->decode($bytes);
    is($decoded->metadata->{'key1'}, 10, 'map key1');
    is($decoded->metadata->{'key2'}, 20, 'map key2');
}

# Oneof
{
    my $msg = Test::Simple->new(id => 1);
    $msg->str_val('hello');
    is($msg->str_val, 'hello', 'oneof str_val set');
    is($msg->{_oneof_case}{0}, 10, 'oneof case tracks str_val');

    my $bytes = $msg->encode();
    my $decoded = Test::Simple->decode($bytes);
    is($decoded->str_val, 'hello', 'oneof str_val roundtrip');
    ok(!defined $decoded->int_val, 'oneof int_val not set');

    # Switch oneof member
    $msg->int_val(42);
    is($msg->int_val, 42, 'oneof int_val set');
    ok(!defined $msg->str_val, 'oneof str_val cleared');
    is($msg->{_oneof_case}{0}, 11, 'oneof case tracks int_val');
}

# Proto3 optional
{
    my $msg = Test::Simple->new();
    $msg->opt_field(0);
    my $bytes = $msg->encode();
    ok(length($bytes) > 0, 'proto3_optional zero encodes');
    my $decoded = Test::Simple->decode($bytes);
    is($decoded->opt_field, 0, 'proto3_optional zero roundtrips');
    is($decoded->{_oneof_case}{1}, 12, 'proto3_optional case set');
}

# Proto3 default omission
{
    my $msg = Test::Simple->new(id => 0, name => '', active => 0);
    my $bytes = $msg->encode();
    is($bytes, '', 'proto3 defaults omitted');
}

done_testing();
