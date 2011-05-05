#!/usr/bin/perl
#
# Copyright (c) 2009, Loren M. Lang
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 
#     * Redistributions of source code must retain the above copyright
#	notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above
#	copyright notice, this list of conditions and the following
#	disclaimer in the documentation and/or other materials provided
#	with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#


use 5.008_001;
use strict;
use warnings;

use bytes;
#use utf8;
use open ':utf8', ':std';
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/lib";
use Common;
use CGI qw(:standard);
use Data::Dumper;

#binmode STDIN;
binmode \*STDIN;
binmode \*STDIN, ":bytes";
print "Content-type: text/plain; charset=utf-8\r\n\r\n";
#system('env');


my $verbose = 0;

#print "Hi!\n";

binmode \*STDIN;
binmode \*STDIN, ":bytes";
#eval { param('response') };
#print "Eval: $@\n";
my $response = param('response');
my $finish = param('finish');

my $text = 0;
$text = 1 if defined($response) && $response eq "text";

if(!$finish) {
	print "ERROR\n" if $text;
	print "Upload incomplete.\n";
	exit 0;
}

if(defined(param('type')) && param('type') eq "gps") {
	my $source = param('source');
	if(!defined($source)) {
		print "ERROR\n" if $text;
		print "No source defined.\n";
		exit 0;
	}
	my $readFd = upload('file');
	if(!defined($readFd)) {
		open(my $outFd, '>:bytes', "tmp/gps.csv");
		binmode $outFd;
		print $outFd param('file');
		close $outFd;
	} else {
		open(my $outFd, '>:bytes', "tmp/gps.csv");
		binmode $outFd;
		while(<$readFd>) {
			print $outFd $_;
		}
		close $outFd;
		close $readFd;
	}
	system("./updatelocation.pl", "-id", $source, "-www", "tmp/gps.csv");
	if($?) {
		print "ERROR\n";
		print "Failed to exec updatelocation.pl\n";
		exit 0;
	}
	print "OK\n";
	exit 0;
}

$verbose = 1 if !$text;

my $self = init();
$self->{verbose} = $verbose;
lockKml($self);

my $doc = loadKml($self);
my $xc = loadXPath($self);
my @messageBase = $xc->findnodes("/kml:kml/kml:Document/kml:Folder[kml:name='Messages']", $doc);
my @photoBase = $xc->findnodes("/kml:kml/kml:Document/kml:Folder[kml:name='Photos']", $doc);

print "Checking for base...\n" if !$text;
die "Can't find base for photos" if @photoBase != 1;
die "Can't find base for messages" if @messageBase != 1;
print "Found.\n" if !$text;

$self->{rssFeed} = loadRssFeed($self);
$self->{atomFeed} = loadAtomFeed($self);

print "Feeds loaded.\n" if !$text;

my $messageBase = $messageBase[0];
my $photoBase = $photoBase[0];


print "Checking form.\n" if !$text;
binmode \*STDIN;
binmode \*STDIN, ":bytes";
foreach('file', 'description', 'title') {
	print "$_: '" . param($_) . "'\n" if defined(param($_)) && !$text;
}

my $title = param('title');
my $descr = param('description');

$title = "" if !defined($title);
$descr = "" if !defined($descr);

if(defined(upload('file'))) {
	print "Found an image\n" if $self->{verbose};
	foreach my $readFd (upload('file')) {
		print Dumper uploadInfo($readFd) if !$text;
		my $filename;
		if(defined(uploadInfo($readFd)) && defined(uploadInfo($readFd)->{'Content-Disposition'})) {
			if(uploadInfo($readFd)->{'Content-Disposition'} =~ /filename="([^;]*)"/) {
				$filename = $1;
			}
		}
		if(!defined($filename)) {
			print "ERROR\n" if $text;
			print "No filename to use.\n";
			exit 0;
		}
		$filename =~ s:[/\\]:_:g;
		open(my $outFd, '>:bytes', "tmp/$filename");
		binmode $outFd;
		while(<$readFd>) {
			print $outFd $_;
		}
		close $outFd;
		close $readFd;
		print "File: '" . $filename . "'\n" if !$text;
		eval {
			my $oldFilename = $filename;
			$filename = processImage($self, "tmp/$filename", $title);
			die "Could not process image 'tmp/$oldFilename'" if !defined($filename);
			addImage($filename, $self, $doc, $photoBase, $title, $descr);
			createThumbnails($self, $filename);
		};
		if($@) {
			print "ERROR\n" if $text;
			print "Error: $@\n";
			exit 0;
		}
		print "File: '" . $filename . "'\n" if !$text;
	}
} else {
	my $html = "<p><b>$title</b></p><p>$descr</p>";
	my $mark = createPlacemark($doc);
	#my $entry = closestEntry($self, $self->{date});
	my $entry = {};
	addName($doc, $mark, $title);
	addDescription($doc, $mark, $html);
	addStyle($doc, $mark, 'text');
	#addTimestamp($doc, $mark, $self->{date});
	addPoint($doc, $mark, $entry->{latitude}, $entry->{longitude}, $entry->{altitude});
	addPlacemark($doc, $messageBase, $mark);
	my $uuid = `uuidgen`;
	chomp($uuid);
	addRssEntry($self, $self->{rssFeed}, $title, "urn:uuid:$uuid", $html);
	addAtomEntry($self, $self->{atomFeed}, $title, "urn:uuid:$uuid", $html);
}

print "OK\n" if $text;

saveKml($self, $doc);
saveRssFeed($self, $self->{rssFeed});
saveAtomFeed($self, $self->{atomFeed});
