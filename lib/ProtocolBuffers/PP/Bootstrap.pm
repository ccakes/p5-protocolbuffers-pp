package ProtocolBuffers::PP::Bootstrap;
use strict;
use warnings;
use ProtocolBuffers::PP::Types qw(
    TYPE_INT32 TYPE_UINT64 TYPE_BOOL TYPE_STRING TYPE_BYTES TYPE_MESSAGE TYPE_ENUM
    LABEL_OPTIONAL LABEL_REPEATED
);

# Hand-coded descriptors for the protoc plugin protocol.
# These are the minimal descriptors needed to decode CodeGeneratorRequest
# and encode CodeGeneratorResponse, plus the descriptor.proto types they reference.

my $VERSION_DESC;
my $FILE_OPTIONS_DESC;
my $MESSAGE_OPTIONS_DESC;
my $FIELD_OPTIONS_DESC;
my $ENUM_VALUE_DESC;
my $ENUM_DESC;
my $ONEOF_DESC;
my $FIELD_DESC;
my $DESCRIPTOR_PROTO;
my $SOURCE_CODE_INFO_LOCATION_DESC;
my $SOURCE_CODE_INFO_DESC;
my $FILE_DESCRIPTOR_PROTO;
my $CODE_GEN_REQUEST;
my $CODE_GEN_RESPONSE_FILE;
my $CODE_GEN_RESPONSE;

# Build descriptors bottom-up

$VERSION_DESC = {
    full_name => 'google.protobuf.compiler.Version',
    syntax => 'proto2',
    fields => {
        1 => { name => 'major',  number => 1, type => TYPE_INT32,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        2 => { name => 'minor',  number => 2, type => TYPE_INT32,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        3 => { name => 'patch',  number => 3, type => TYPE_INT32,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        4 => { name => 'suffix', number => 4, type => TYPE_STRING, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
    },
    oneofs => [],
    is_map_entry => 0,
};

$FILE_OPTIONS_DESC = {
    full_name => 'google.protobuf.FileOptions',
    syntax => 'proto2',
    fields => {
        # We only need a few fields from FileOptions
        1  => { name => 'java_package',          number => 1,  type => TYPE_STRING, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        11 => { name => 'go_package',            number => 11, type => TYPE_STRING, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
    },
    oneofs => [],
    is_map_entry => 0,
};

$MESSAGE_OPTIONS_DESC = {
    full_name => 'google.protobuf.MessageOptions',
    syntax => 'proto2',
    fields => {
        7 => { name => 'map_entry', number => 7, type => TYPE_BOOL, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
    },
    oneofs => [],
    is_map_entry => 0,
};

$FIELD_OPTIONS_DESC = {
    full_name => 'google.protobuf.FieldOptions',
    syntax => 'proto2',
    fields => {
        2 => { name => 'packed', number => 2, type => TYPE_BOOL, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
    },
    oneofs => [],
    is_map_entry => 0,
};

$ENUM_VALUE_DESC = {
    full_name => 'google.protobuf.EnumValueDescriptorProto',
    syntax => 'proto2',
    fields => {
        1 => { name => 'name',   number => 1, type => TYPE_STRING, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        2 => { name => 'number', number => 2, type => TYPE_INT32,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
    },
    oneofs => [],
    is_map_entry => 0,
};

$ENUM_DESC = {
    full_name => 'google.protobuf.EnumDescriptorProto',
    syntax => 'proto2',
    fields => {
        1 => { name => 'name',  number => 1, type => TYPE_STRING,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        2 => { name => 'value', number => 2, type => TYPE_MESSAGE, label => LABEL_REPEATED, packed => 0, oneof_index => undef,
               message_descriptor => $ENUM_VALUE_DESC },
    },
    oneofs => [],
    is_map_entry => 0,
};

$ONEOF_DESC = {
    full_name => 'google.protobuf.OneofDescriptorProto',
    syntax => 'proto2',
    fields => {
        1 => { name => 'name', number => 1, type => TYPE_STRING, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
    },
    oneofs => [],
    is_map_entry => 0,
};

$FIELD_DESC = {
    full_name => 'google.protobuf.FieldDescriptorProto',
    syntax => 'proto2',
    fields => {
        1  => { name => 'name',           number => 1,  type => TYPE_STRING,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        2  => { name => 'extendee',       number => 2,  type => TYPE_STRING,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        3  => { name => 'number',         number => 3,  type => TYPE_INT32,   label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        4  => { name => 'label',          number => 4,  type => TYPE_ENUM,    label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        5  => { name => 'type',           number => 5,  type => TYPE_ENUM,    label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        6  => { name => 'type_name',      number => 6,  type => TYPE_STRING,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        7  => { name => 'default_value',  number => 7,  type => TYPE_STRING,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        8  => { name => 'options',        number => 8,  type => TYPE_MESSAGE, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef,
                message_descriptor => $FIELD_OPTIONS_DESC },
        9  => { name => 'oneof_index',    number => 9,  type => TYPE_INT32,   label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        10 => { name => 'json_name',      number => 10, type => TYPE_STRING,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        17 => { name => 'proto3_optional', number => 17, type => TYPE_BOOL,   label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
    },
    oneofs => [],
    is_map_entry => 0,
};

$DESCRIPTOR_PROTO = {
    full_name => 'google.protobuf.DescriptorProto',
    syntax => 'proto2',
    fields => {
        1 => { name => 'name',        number => 1, type => TYPE_STRING,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        2 => { name => 'field',       number => 2, type => TYPE_MESSAGE, label => LABEL_REPEATED, packed => 0, oneof_index => undef,
               message_descriptor => $FIELD_DESC },
        3 => { name => 'nested_type', number => 3, type => TYPE_MESSAGE, label => LABEL_REPEATED, packed => 0, oneof_index => undef },
            # message_descriptor set below (circular ref)
        4 => { name => 'enum_type',   number => 4, type => TYPE_MESSAGE, label => LABEL_REPEATED, packed => 0, oneof_index => undef,
               message_descriptor => $ENUM_DESC },
        6 => { name => 'extension',   number => 6, type => TYPE_MESSAGE, label => LABEL_REPEATED, packed => 0, oneof_index => undef,
               message_descriptor => $FIELD_DESC },
        7 => { name => 'options',     number => 7, type => TYPE_MESSAGE, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef,
               message_descriptor => $MESSAGE_OPTIONS_DESC },
        8 => { name => 'oneof_decl',  number => 8, type => TYPE_MESSAGE, label => LABEL_REPEATED, packed => 0, oneof_index => undef,
               message_descriptor => $ONEOF_DESC },
        10 => { name => 'reserved_name', number => 10, type => TYPE_STRING, label => LABEL_REPEATED, packed => 0, oneof_index => undef },
    },
    oneofs => [],
    is_map_entry => 0,
};
# Fix circular reference: nested_type is also DescriptorProto
$DESCRIPTOR_PROTO->{fields}{3}{message_descriptor} = $DESCRIPTOR_PROTO;

$SOURCE_CODE_INFO_LOCATION_DESC = {
    full_name => 'google.protobuf.SourceCodeInfo.Location',
    syntax => 'proto2',
    fields => {
        1 => { name => 'path', number => 1, type => TYPE_INT32, label => LABEL_REPEATED, packed => 1, oneof_index => undef },
        2 => { name => 'span', number => 2, type => TYPE_INT32, label => LABEL_REPEATED, packed => 1, oneof_index => undef },
        3 => { name => 'leading_comments',  number => 3, type => TYPE_STRING, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        4 => { name => 'trailing_comments', number => 4, type => TYPE_STRING, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        6 => { name => 'leading_detached_comments', number => 6, type => TYPE_STRING, label => LABEL_REPEATED, packed => 0, oneof_index => undef },
    },
    oneofs => [],
    is_map_entry => 0,
};

$SOURCE_CODE_INFO_DESC = {
    full_name => 'google.protobuf.SourceCodeInfo',
    syntax => 'proto2',
    fields => {
        1 => { name => 'location', number => 1, type => TYPE_MESSAGE, label => LABEL_REPEATED, packed => 0, oneof_index => undef,
               message_descriptor => $SOURCE_CODE_INFO_LOCATION_DESC },
    },
    oneofs => [],
    is_map_entry => 0,
};

$FILE_DESCRIPTOR_PROTO = {
    full_name => 'google.protobuf.FileDescriptorProto',
    syntax => 'proto2',
    fields => {
        1  => { name => 'name',             number => 1,  type => TYPE_STRING,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        2  => { name => 'package',          number => 2,  type => TYPE_STRING,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        3  => { name => 'dependency',       number => 3,  type => TYPE_STRING,  label => LABEL_REPEATED, packed => 0, oneof_index => undef },
        4  => { name => 'message_type',     number => 4,  type => TYPE_MESSAGE, label => LABEL_REPEATED, packed => 0, oneof_index => undef,
                message_descriptor => $DESCRIPTOR_PROTO },
        5  => { name => 'enum_type',        number => 5,  type => TYPE_MESSAGE, label => LABEL_REPEATED, packed => 0, oneof_index => undef,
                message_descriptor => $ENUM_DESC },
        7  => { name => 'extension',        number => 7,  type => TYPE_MESSAGE, label => LABEL_REPEATED, packed => 0, oneof_index => undef,
                message_descriptor => $FIELD_DESC },
        8  => { name => 'options',          number => 8,  type => TYPE_MESSAGE, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef,
                message_descriptor => $FILE_OPTIONS_DESC },
        9  => { name => 'source_code_info', number => 9,  type => TYPE_MESSAGE, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef,
                message_descriptor => $SOURCE_CODE_INFO_DESC },
        10 => { name => 'public_dependency', number => 10, type => TYPE_INT32,  label => LABEL_REPEATED, packed => 0, oneof_index => undef },
        11 => { name => 'weak_dependency',   number => 11, type => TYPE_INT32,  label => LABEL_REPEATED, packed => 0, oneof_index => undef },
        12 => { name => 'syntax',           number => 12, type => TYPE_STRING,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        14 => { name => 'edition',          number => 14, type => TYPE_ENUM,    label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
    },
    oneofs => [],
    is_map_entry => 0,
};

$CODE_GEN_REQUEST = {
    full_name => 'google.protobuf.compiler.CodeGeneratorRequest',
    syntax => 'proto2',
    fields => {
        1  => { name => 'file_to_generate',  number => 1,  type => TYPE_STRING,  label => LABEL_REPEATED, packed => 0, oneof_index => undef },
        2  => { name => 'parameter',         number => 2,  type => TYPE_STRING,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        3  => { name => 'compiler_version',  number => 3,  type => TYPE_MESSAGE, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef,
                message_descriptor => $VERSION_DESC },
        15 => { name => 'proto_file',        number => 15, type => TYPE_MESSAGE, label => LABEL_REPEATED, packed => 0, oneof_index => undef,
                message_descriptor => $FILE_DESCRIPTOR_PROTO },
        17 => { name => 'source_file_descriptors', number => 17, type => TYPE_MESSAGE, label => LABEL_REPEATED, packed => 0, oneof_index => undef,
                message_descriptor => $FILE_DESCRIPTOR_PROTO },
    },
    oneofs => [],
    is_map_entry => 0,
};

$CODE_GEN_RESPONSE_FILE = {
    full_name => 'google.protobuf.compiler.CodeGeneratorResponse.File',
    syntax => 'proto2',
    fields => {
        1  => { name => 'name',            number => 1,  type => TYPE_STRING, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        2  => { name => 'insertion_point',  number => 2,  type => TYPE_STRING, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        15 => { name => 'content',         number => 15, type => TYPE_STRING, label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
    },
    oneofs => [],
    is_map_entry => 0,
};

$CODE_GEN_RESPONSE = {
    full_name => 'google.protobuf.compiler.CodeGeneratorResponse',
    syntax => 'proto2',
    fields => {
        1  => { name => 'error',              number => 1,  type => TYPE_STRING,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        2  => { name => 'supported_features', number => 2,  type => TYPE_UINT64,  label => LABEL_OPTIONAL, packed => 0, oneof_index => undef },
        15 => { name => 'file',               number => 15, type => TYPE_MESSAGE, label => LABEL_REPEATED, packed => 0, oneof_index => undef,
                message_descriptor => $CODE_GEN_RESPONSE_FILE },
    },
    oneofs => [],
    is_map_entry => 0,
};

sub code_generator_request_descriptor  { $CODE_GEN_REQUEST }
sub code_generator_response_descriptor { $CODE_GEN_RESPONSE }
sub file_descriptor_proto_descriptor   { $FILE_DESCRIPTOR_PROTO }
sub descriptor_proto_descriptor        { $DESCRIPTOR_PROTO }
sub field_descriptor_proto_descriptor  { $FIELD_DESC }
sub enum_descriptor_proto_descriptor   { $ENUM_DESC }

1;
