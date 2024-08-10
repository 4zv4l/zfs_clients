#!/usr/bin/env perl

use Digest::MD5;
use IO::Socket::INET;
use v5.38;

$|=1;

sub getMd5($conn) {
    # get md5sum
    $conn->recv(my $md5sum, 16);
    $md5sum = unpack("H*", $md5sum);
    say "md5sum => '$md5sum'";
    $md5sum;
}

sub getSize($conn) {
    # get filesize
    $conn->recv(my $filesize, 8);
    $filesize = unpack("Q", $filesize);
    say "filesize => $filesize";
    $filesize; 
}

sub download($conn) {
    print "> ";
    my $filename = scalar <STDIN>;
    $conn->send($filename);
    chomp($filename);

    my $md5sum = getMd5($conn);
    my $filesize = getSize($conn);
    if ($md5sum eq '00000000000000000000000000000000')
    {
        $conn->recv(my $err, $filesize);
        say $err;
        return;
    }

    my $md5 = Digest::MD5->new;;
    if ($filename =~ /^\$/) {
        $conn->recv(my $list, $filesize);
        print "------ LIST ------\n";
        print $list;
        $md5->add($list);
        print "------------------\n";
    } else {
        # download file and check md5sum
        my $downloaded = 0;
        $filename =~ s{/}{__};
        open my $output, '>', $filename;
        while ($downloaded < $filesize)
        {
            $conn->recv(my $chunk, 1024); 
            $md5->add($chunk);
            $downloaded += length($chunk);
            print $output $chunk;
            print "\rDownloaded $downloaded/$filesize bytes";
        }
        print "\n";
        close($output);
    }
    $md5sum eq $md5->hexdigest ? say "md5sum matches !" : say "md5sum does not match got '", $md5->hexdigest, "' !!!";
}

(my $ip, my $port) = ($ARGV[0] || "127.0.0.1", $ARGV[1] || 8080);
my $conn = IO::Socket::INET->new("$ip:$port") or die;
while(1) {download($conn)};
$conn->close;
