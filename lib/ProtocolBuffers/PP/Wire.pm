package ProtocolBuffers::PP::Wire;
use strict;
use warnings;

use constant {
    VARINT          => 0,
    FIXED64         => 1,
    LENGTH_DELIMITED => 2,
    START_GROUP     => 3,
    END_GROUP       => 4,
    FIXED32         => 5,
};

1;
