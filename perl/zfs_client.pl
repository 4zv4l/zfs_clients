#!/usr/bin/env perl

use Digest::MD5;
use IO::Socket::INET;
use v5.38;

$|=1;

sub download($conn) {
    print "> ";
    my $filename = scalar <STDIN>;
    $conn->send($filename);
    chomp($filename);

    # get md5sum
    $conn->recv(my $md5sum, 16);
    $md5sum = unpack("H*", $md5sum);
    say "md5sum => '$md5sum'";
    
    # get filesize
    $conn->recv(my $filesize, 8);
    $filesize = unpack("Q", $filesize);
    say "filesize => $filesize";
    
    if ($md5sum eq '00000000000000000000000000000000')
    {
        $conn->recv(my $err, $filesize);
        say $err;
        return;
    }
    
    # download file and check md5sum
    my $md5 = Digest::MD5->new;
    my $downloaded = 0;
    open my $output, '>', $filename;
    while ($downloaded < $filesize)
    {
        $conn->recv(my $chunk, 1024); 
        $md5->add($chunk);
        $downloaded += length($chunk);
        print "\rDownloaded $downloaded/$filesize bytes";
    }
    print "\n";
    close($output);
    
    $md5sum eq $md5->hexdigest ? say "md5sum matches !" : say "md5sum does not match got '", $md5->hexdigest, "' !!!";
}

(my $ip, my $port) = ($ARGV[0] || "127.0.0.1", $ARGV[1] || 8080);
my $conn = IO::Socket::INET->new("$ip:$port") or die;
while(1) {download($conn)};
$conn->close;
