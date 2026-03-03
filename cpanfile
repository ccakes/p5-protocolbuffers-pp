requires 'JSON::PP';
requires 'MIME::Base64';
requires 'Math::BigInt';
requires 'POSIX';

# gRPC client dependencies
requires 'Mojolicious', '>= 9.0';
requires 'Protocol::HTTP2', '>= 1.10';

on 'test' => sub {
    requires 'Test::More';
    requires 'Test::Exception';
};
