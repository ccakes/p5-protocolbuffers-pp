requires 'JSON::PP';
requires 'MIME::Base64';
requires 'Math::BigInt';
requires 'POSIX';

on 'test' => sub {
    requires 'Test::More';
    requires 'Test::Exception';
};
