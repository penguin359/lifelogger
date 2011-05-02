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
use Getopt::Long;

require 'common.pl';

my $verbose = 0;
my $result = GetOptions("verbose" => \$verbose);

my $self = init();
$self->{verbose} = $verbose;
lockKml($self);

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
		$filename = processImage($self, $path, $title);
		die "Could not process image '$path'" if !defined($filename);
		addImage($filename, $self, $doc, $base, $title);
		createThumbnails($self, $filename);
	};
}

my $doc = loadKml($self);
my $xc = loadXPath($self);
my @base = $xc->findnodes("/kml:kml/kml:Document/kml:Folder[kml:name='Unsorted Photos']", $doc);

die "Can't find base for unsorted photos" if @base != 1;


$self->{rssFeed} = loadRssFeed($self);
$self->{atomFeed} = loadAtomFeed($self);
if(!@ARGV) {
	addImageScan($_, $self, $doc, $base[0])
	    foreach glob "$self->{settings}->{cwd}/uploads/*.[jJ][pP][gG] uploads/*.[jJ][pP][eE][gG]";
} else {
	addImageScan($_, $self, $doc, $base[0])
	    foreach @ARGV;
}
saveKml($self, $doc);
saveRssFeed($self, $self->{rssFeed});
saveAtomFeed($self, $self->{atomFeed});
