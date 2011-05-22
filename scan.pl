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

my $usage = "[-id id] [image.jpg ...]";
my $id;

my $self = init($usage, {"id=s" => \$id});
lockKml($self);

my $source;
eval {
	$source = findSource($self, "Photos", $id);
};
if($@) {
	$source = {
		id => 13,
		name => "Photos",
		type => "Photos",
		deviceKey => 13,
	};
}

sub addImageScan {
	my($path, $self, $doc, $base) = @_;

	return if ! -f $path || ! -s $path;
	print "Processing $path\n" if $self->{verbose};
	my $filename = $path;
	$filename =~ s:.*/::;
	$filename =~ s:\.[jJ][pP][eE]?[gG]$:.jpg:;

	#print "Renaming '$path' to 'images/$filename'\n" if $self->{verbose};
	#rename($path, "images/$filename") or die "Failed rename(): $!";

	#my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
	#    $atime,$mtime,$ctime,$blksize,$blocks) = stat("images/$filename");

	#my $timestamp = $mtime;
	#die "Failed to stat $path: $!" if(!defined($timestamp) || $timestamp == 0);

	my $title = $filename;
	$title =~ s/\.jpg$//;
	eval {
		$filename = processImage($self, $source, $path, $title);
		die "Could not process image '$path'" if !defined($filename);
		addImage($self, $source, $filename, $doc, $base, $title);
		createThumbnails($self, $source, $filename);
	};
}

my $doc = loadKml($self);
my $xc = loadXPath($self);
my $photoPath = "/kml:kml/kml:Document/kml:Folder[kml:name='Unsorted Photos']";
my $photoId = $source->{kml}->{photo};
$photoPath = "//kml:Folder[\@id='$photoId']" if defined($photoId);
my @photoBase = $xc->findnodes($photoPath, $doc);

die "Can't find container for unsorted photos" if @photoBase != 1;


$self->{rssFeed} = loadRssFeed($self);
$self->{atomFeed} = loadAtomFeed($self);
if(!@ARGV) {
	addImageScan($_, $self, $doc, $photoBase[0])
	    foreach glob "$self->{settings}->{cwd}/uploads/*.[jJ][pP][gG] $self->{settings}->{cwd}/uploads/*.[jJ][pP][eE][gG]";
} else {
	addImageScan($_, $self, $doc, $photoBase[0])
	    foreach @ARGV;
}
saveKml($self, $doc);
saveRssFeed($self, $self->{rssFeed});
saveAtomFeed($self, $self->{atomFeed});
