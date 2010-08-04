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


use 5.008;
use warnings;
use strict;

use utf8;
use open ':utf8', ':std';
use POSIX qw(mktime strftime);
use Fcntl ':flock';
use XML::DOM;
use XML::DOM::XPath;
use MIME::Parser;
use MIME::WordDecoder;
use Image::ExifTool;
use Encode;
use Data::Dumper;

require 'common.pl';

my $descrText = "";

sub scanEntity {
	my($entity, $self, $doc, $base) = @_;

	my $i = 0;
	while($entity->parts($i)) {
		scanEntity($entity->parts($i++), $self, $doc, $base);
	}
	if($entity->head->mime_type eq "image/jpeg") {
		$self->{matched} = 1;
		my $exif = new Image::ExifTool;
		#print $entity->body->as_string;
		$entity->bodyhandle->binmode(1);
		my $fd = $entity->bodyhandle->open('r');
		my $info = $exif->ImageInfo($fd);
		#print "CD: '", $entity->head->get('Content-Disposition', 0), "'\n";
		my $filename = $entity->head->mime_attr('Content-Disposition.filename');
		$filename = $entity->head->mime_attr('Content-Type.name') if !defined($filename);
		$filename =~ s:/:_:;
		#print Dumper($info);
		$fd = $entity->bodyhandle->open('r');
		open(my $outFd, ">images/$filename");
		binmode $outFd;
		while(<$fd>) {
			print $outFd $_;
		}
		close $outFd;
		system('convert','-geometry','160x160',"images/$filename","images/160/$filename");
		system('convert','-geometry','32x32',"images/$filename","images/32/$filename");

		my $timestamp = $self->{date};
		if(exists $info->{DateTimeOriginal}) {
			$info->{DateTimeOriginal} =~ /(\d+):(\d+):(\d+)\s+(\d+):(\d+):(\d+)/;
			my $year = $1;
			my $mon = $2;
			my $mday = $3;
			my $hour = $4;
			my $min = $5;
			my $sec = $6;
			my $tzoffset = (-7*60 + 0)*60;
			$tzoffset *= -1;
			#print "SD: $mday $mon $year  $hour:$min:$sec\n";
			$timestamp = mktime($sec, $min, $hour, $mday, $mon-1, $year-1900) + $tzoffset;
		}
		my $latitude;
		my $longitude;
		my $altitude;
		if(exists $info->{GPSPosition}) {
			$info->{GPSPosition} =~ /(\d+)\s*deg\s*(?:(\d+)'\s*(?:(\d+(?:\.\d*)?)")?)?\s*([NS]),\s*(\d+)\s*deg\s*(?:(\d+)'\s*(?:(\d+(?:\.\d*)?)")?)?\s*([EW])/;
			#print "Loc: $1° $2' $3\" $4, $5° $6' $7\" $8\n";
			$latitude = $1 + ($2 + $3/60)/60;
			$latitude *= -1 if $4 eq "S";
			$longitude = $5 + ($6 + $7/60)/60;
			$longitude *= -1 if $8 eq "W";
		} else {
			my $entry = closestEntry($self, $timestamp);
			$latitude = $entry->{latitude};
			$longitude = $entry->{longitude};
			$altitude = $entry->{altitude};
		}
		#print "$longitude,$latitude\n";

		my $mark = createPlacemark($doc);
		addName($doc, $mark, $self->{subject});
		addDescription($doc, $mark, "<p><b>$self->{subject}</b></p><p>$descrText</p><a href=\"http://www.example.org/images/$filename\"><img src=\"http://www.example.org/images/160/$filename\"></a>");
		addRssEntry($self->{rssFeed}, $self->{subject}, "http://www.example.org/images/$filename", "<p><b>$self->{subject}</b></p><p>$descrText</p><a href=\"http://www.example.org/images/$filename\"><img src=\"http://www.example.org/images/160/$filename\"></a>");
		addAtomEntry($self->{atomFeed}, $self->{subject}, "http://www.example.org/images/$filename", "<p><b>$self->{subject}</b></p><p>$descrText</p><a href=\"http://www.example.org/images/$filename\"><img src=\"http://www.example.org/images/160/$filename\"></a>");
		addTimestamp($doc, $mark, $timestamp);
		addStyle($doc, $mark, 'photo');
		addPoint($doc, $mark, $latitude, $longitude);
		addPlacemark($doc, $base, $mark);
	} elsif($entity->head->mime_type eq "text/plain") {
		#$entity->bodyhandle->print(\*STDOUT);
		#print $entity->bodyhandle->as_string;
		$descrText = $entity->bodyhandle->as_string;
		my $wd = MIME::WordDecoder->new(['utf-8' => 'KEEP', '*' => \&myToUtf8, 'raw' => \&myFromRaw]);
		$self->{subject} = $wd->decode($self->{subject});
		$descrText = decode($entity->head->mime_attr('Content-type.charset'), $descrText);
		$descrText =~ s/&/&amp;/g;
		$descrText =~ s/"/&quot;/g;
		$descrText =~ s/</&lt;/g;
		$descrText =~ s/>/&gt;/g;
	} elsif($entity->head->get('Content-Disposition', 0) =~ /^\s*attachment\s*(?:;.*)?$/) {
		$entity->bodyhandle->binmode(1);
		my $fd = $entity->bodyhandle->open('r');
		my $filename = $entity->head->mime_attr('Content-Disposition.filename');
		$filename =~ s:/:_:;
		open(my $outFd, ">files/$filename");
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

my $self = init();
lockKml($self);

my $doc = loadKml($self);
#my @base = $doc->findnodes('/kml/Document');
my @messageBase = $doc->findnodes("/kml/Document/Folder[name='Messages']");
my @photoBase = $doc->findnodes("/kml/Document/Folder[name='Photos']");

die "Can't find base for photos" if @photoBase != 1;
die "Can't find base for messages" if @messageBase != 1;

my $parser = new MIME::Parser;
$parser->output_under("/tmp");
binmode STDIN;
my $entity = $parser->parse(\*STDIN);
#$entity->parts(1)->print_body;
#$entity->dump_skeleton;
#$entity->head->decode;


my $subject = $entity->head->get('Subject');
chomp($subject);
#print "S: '", $subject, "'\n";
$self->{subject} = $subject;


$self->{rssFeed} = loadRssFeed();
$self->{atomFeed} = loadAtomFeed();
$self->{date} = parseDate($entity->head->get('Date'));
$self->{matched} = 0;
#exit 0;
scanEntity($entity, $self, $doc, $photoBase[0]);
if(!$self->{matched}) {
	my $mark = createPlacemark($doc);
	my $entry = closestEntry($self, $self->{date});
	addName($doc, $mark, $self->{subject});
	addDescription($doc, $mark, "<p><b>$self->{subject}</b></p><p>$descrText</p>");
	addStyle($doc, $mark, 'text');
	addPoint($doc, $mark, $entry->{latitude}, $entry->{longitude}, $entry->{altitude});
	addPlacemark($doc, $messageBase[0], $mark);
	my $uuid = `uuidgen`;
	chomp($uuid);
	addRssEntry($self->{rssFeed}, $self->{subject}, "urn:uuid:$uuid", "<p><b>$self->{subject}</b></p><p>$descrText</p>");
	addAtomEntry($self->{atomFeed}, $self->{subject}, "urn:uuid:$uuid", "<p><b>$self->{subject}</b></p><p>$descrText</p>");
}
saveKml($self, $doc);
saveRssFeed($self->{rssFeed});
saveAtomFeed($self->{atomFeed});
