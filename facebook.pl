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
use warnings;
use strict;

use utf8;
use open ':utf8', ':std';
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/lib";
use Getopt::Long;
use File::Basename;
use LWP::UserAgent 5.810;
use HTTP::Cookies;
use HTTP::Request::Common;
use Facebook;

require 'common.pl';

my $verbose = 0;
my $result = GetOptions(
	"verbose" => \$verbose);
die "Usage: $0" if !$result || @ARGV > 1;

my $self = init();
$self->{verbose} = $verbose;
lockKml($self);

sub getNode {
	my($xc, $node, $path) = @_;

	my @nodeList = $xc->findnodes($path, $node);
	warn "Multiple nodes for '$path' on " . $node->nodeName
	    if @nodeList > 1;
	return $nodeList[0] if @nodeList == 1;
	return;
}

sub getTextNode {
	my($xc, $node, $path) = @_;

	$node = getNode($xc, $node, $path . "/text()");
	return $node->nodeValue if defined($node);
	return;
}

sub postPhoto {
	my($ua, $token, $title, $descr, $file) = @_;

	my $f = new Facebook token => $token, ua => $ua;
	my $albumId = 1;
	my $photoObj = $f->post('photos', $albumId, [ message => $title, source => [ $file ] ]);
	my $photoId = $photoObj->{id};
	$f->post('comments', $photoId, [ message => $descr ])
	    if defined($photoId) && $descr;
}

my $xc = loadXPath($self);
my $parser = new XML::LibXML;
my $settingsDoc = $parser->parse_file("facebook.xml");

my $token = getTextNode($xc, $settingsDoc, '/settings/sources/source/accessToken');
print "Token: '", $token, "'\n";

my $doc = loadKml($self);
my @placemarks = $xc->findnodes("/kml:kml/kml:Document/kml:Folder[kml:name='Photos']/kml:Placemark", $doc);

my $ua = new LWP::UserAgent agent => 'PhotoCatalog/0.01', cookie_jar => new HTTP::Cookies;
foreach(@placemarks) {
	my $name = getTextNode($xc, $_, 'kml:name');
	my $fullDescr = getTextNode($xc, $_, 'kml:description');
	$fullDescr =~ s@^<p><b>[^<]*</b></p>@@;
	$fullDescr =~ m@^<p>([^<]*)</p>@;
	my $descr = $1;
	$descr =~ s@&#39;@'@g;
	$descr =~ s@&quot;@"@g;
	$descr =~ s@&lt;@<@g;
	$descr =~ s@&gt;@>@g;
	$descr =~ s@&amp;@\&@g;
	$descr =~ s@&#39;@'@g;  # Undo an accidental double-escape
	$descr =~ s@^[[:space:]]*@@;
	$descr =~ s@[[:space:]]*$@@;
	$fullDescr =~ m@<img src="http://.*/images/160/([^"]*)"@;
	my $img = '/home/user/public_html/photocatalog/images/' . $1;
	#my $dir = dirname($img);
	#my $file = basename($img);
	#my $outFile = "$dir/descriptions/$file.txt";
	print "Name: '", $name, "'\n";
	print "Description: '", $descr, "'\n";
	print "Image: '", $img, "'\n";
	postPhoto($ua, $token, $name, $descr, $img)
	#print "Image: '", $dir, "', '", $file, "'\n";
	#next if !$descr;
	#open(my $fd, '>', $outFile) or die "Problem: $!";
	#print $fd $descr;
	#close $fd;
}

exit 0;
