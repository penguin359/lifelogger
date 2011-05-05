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

use utf8;
use open ':utf8', ':std';
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/lib";
use Common;
use MIME::Parser;
use MIME::WordDecoder;
use Encode;

my $usage = "[message.eml]";

my $self = init($usage);
die $self->{usage} if @ARGV > 1;
lockKml($self);

my $descrText = "";

sub scanEntity {
	my($entity, $self, $doc, $base) = @_;

	my $website = $self->{settings}->{website};

	my $i = 0;
	while($entity->parts($i)) {
		scanEntity($entity->parts($i++), $self, $doc, $base);
	}
	if($entity->head->mime_type eq "image/jpeg") {
		print "Found an image\n" if $self->{verbose};
		$self->{matched} = 1;
		#print $entity->body->as_string;
		#print "CD: '", $entity->head->get('Content-Disposition', 0), "'\n";
		my $filename = $entity->head->mime_attr('Content-Disposition.filename');
		$filename = $entity->head->mime_attr('Content-Type.name') if !defined($filename);
		if(!defined($filename)) {
			print STDERR "No filename to use.\n";
			return;
		}
		$filename =~ s:[/\\]:_:g;
		$entity->bodyhandle->binmode(1);
		my $fd = $entity->bodyhandle->open('r');
		open(my $outFd, '>:bytes', "tmp/$filename");
		binmode $outFd;
		while(<$fd>) {
			print $outFd $_;
		}
		close $outFd;
		eval {
			$filename = processImage($self, "tmp/$filename", $self->{subject});
			die "Could not process image 'tmp/$filename'" if !defined($filename);
			addImage($filename, $self, $doc, $base, $self->{subject}, $descrText);
			createThumbnails($self, $filename);
		};
	} elsif($entity->head->mime_type eq "text/plain") {
		print "Found text\n" if $self->{verbose};
		#$entity->bodyhandle->print(\*STDOUT);
		#print $entity->bodyhandle->as_string;
		$descrText = $entity->bodyhandle->as_string;
		my $wd = MIME::WordDecoder->new(['utf-8' => 'KEEP', '*' => \&myToUtf8, 'raw' => \&myFromRaw]);
		$self->{subject} = $wd->decode($self->{subject});
		$descrText = decode($entity->head->mime_attr('Content-type.charset'), $descrText);
		$descrText = escapeText($self, $descrText);
	} elsif($entity->head->get('Content-Disposition', 0) =~ /^\s*attachment\s*(?:;.*)?$/) {
		print "Found other attachment\n" if $self->{verbose};
		$entity->bodyhandle->binmode(1);
		my $fd = $entity->bodyhandle->open('r');
		my $filename = $entity->head->mime_attr('Content-Disposition.filename');
		$filename =~ s:[/\\]:_:g;
		open(my $outFd, '>:bytes', "files/$filename");
		binmode $outFd;
		while(<$fd>) {
			print $outFd $_;
		}
	}
}

sub myToUtf8 {
	my($data, $charset) = @_;
	decode($charset, $data);
}

sub myFromRaw {
	my($data, $charset) = @_;
	decode('us-ascii', $data);
}

my $doc = loadKml($self);
my $xc = loadXPath($self);
my @messageBase = $xc->findnodes("/kml:kml/kml:Document/kml:Folder[kml:name='Messages']", $doc);
my @photoBase = $xc->findnodes("/kml:kml/kml:Document/kml:Folder[kml:name='Photos']", $doc);

die "Can't find base for photos" if @photoBase != 1;
die "Can't find base for messages" if @messageBase != 1;

my $messageBase = $messageBase[0];
my $photoBase = $photoBase[0];

my $tmp = "/tmp";
$tmp = $ENV{TEMP} if defined $ENV{TEMP};

my $parser = new MIME::Parser;
$parser->output_under($tmp);
my $entity;
if(defined $ARGV[0]) {
	open(my $fd, '<:bytes', $ARGV[0]) or die "failed to read";
	binmode $fd;
	$entity = $parser->parse($fd);
} else {
	binmode STDIN;
	$entity = $parser->parse(\*STDIN);
}
#$entity->parts(1)->print_body;
#$entity->dump_skeleton;
#$entity->head->decode;


my $subject = $entity->head->get('Subject');
chomp($subject);
$self->{subject} = $subject;


$self->{rssFeed} = loadRssFeed($self);
$self->{atomFeed} = loadAtomFeed($self);
$self->{date} = parseDate($entity->head->get('Date'));
$self->{matched} = 0;
scanEntity($entity, $self, $doc, $photoBase);
if(!$self->{matched}) {
	my $title = $self->{subject};
	my $descr = $descrText;
	my $html = "<p><b>$title</b></p><p>$descr</p>";
	my $mark = createPlacemark($doc);
	my $entry = closestEntry($self, $self->{date});
	addName($doc, $mark, $title);
	addDescription($doc, $mark, $html);
	addStyle($doc, $mark, 'text');
	addTimestamp($doc, $mark, $self->{date});
	addPoint($doc, $mark, $entry->{latitude}, $entry->{longitude}, $entry->{altitude});
	addPlacemark($doc, $messageBase, $mark);
	my $uuid = `uuidgen`;
	chomp($uuid);
	addRssEntry($self, $self->{rssFeed}, $title, "urn:uuid:$uuid", $html);
	addAtomEntry($self, $self->{atomFeed}, $title, "urn:uuid:$uuid", $html);
}
saveKml($self, $doc);
saveRssFeed($self, $self->{rssFeed});
saveAtomFeed($self, $self->{atomFeed});
