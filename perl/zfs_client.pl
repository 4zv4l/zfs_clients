#!/usr/bin/env perl

use Digest::MD5;
use IO::Socket::INET;
use v5.38;

# connect and send file request to server
my $conn = IO::Socket::INET->new("127.0.0.1:9999") or die;
$conn->send(scalar <>);

# get the md5sum or error if the hash is 0
my $md5sum;
$conn->recv($md5sum, 16);
$md5sum = unpack("H*", $md5sum);
say "md5sum => '$md5sum'";

if ($md5sum eq '00000000000000000000000000000000')
{
    my $err;
    $conn->recv($err, 100);
    say $err;
    exit;
}

# get filesize
my $filesize;
$conn->recv($filesize, 8);
$filesize = unpack("Q", $filesize);
say "filesize => $filesize";

# download file and check md5sum
my $md5 = Digest::MD5->new;
open my $output, '>', 'out';
while (my $chunk = <$conn>)
{
    print $output $chunk;
    $md5->add($chunk);
}
close($output);

$md5sum eq $md5->hexdigest ? say "md5sum matches !" : say "md5sum does not match !!!";

$conn->close;
