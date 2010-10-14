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

#use utf8;
#use open ':utf8', ':std';
use Getopt::Long;
use File::Basename;
use LWP::UserAgent;
use HTTP::Cookies;
use HTTP::Request::Common;
use JSON;
use Data::Dumper;

require 'common.pl';

my $verbose = 0;
my $result = GetOptions(
	"Verbose" => \$verbose);
die "Usage: $0" if !$result || @ARGV > 1;

my $self = init();
$self->{verbose} = $verbose;
lockKml($self);

$JSON::UTF8 = 1;

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
	#print Dumper($node);
	return $node->nodeValue if defined($node);
	return;
}

sub postGraph {
	my($ua, $token, $type, $id, $vars) = @_;

	my $json = new JSON;
	my $req = POST "https://graph.facebook.com/$id/$type",
		    Content_Type => 'form-data',
		    Content      => [ access_token => $token,
				      @$vars
				    ];
	#
	#print "curl ";
	#my %pass = ( access_token => $token, @$vars );
	#foreach(keys %pass) {
	#	if(ref $pass{$_}) {
	#		print "-F '$_=\@$pass{$_}->[0]' ";
	#	} else {
	#		print "-F '$_=$pass{$_}' ";
	#	}
	#}
	#print "https://graph.facebook.com/$id/$type\n";
	#print "https://graph.facebook.com/$id/$type";
	#print Dumper($vars);
	#print Dumper($req);
	#exit 0;
	my $resp = $ua->request($req);
	#print Dumper($resp);
	if(!$resp->is_success) {
		my $obj = $json->jsonToObj($resp->content);
		die "Bad request: Failed to issue $type request: ".$obj->{error}->{type} . ".\n" . $obj->{error}->{message}
		    if defined($obj->{error});
		die "Bad request: $type request failed: " . $resp->status_line . ".\n" . $resp->content;
		return;
	}
	my $obj = $json->jsonToObj($resp->content);
	die "Failed to issue $type request: ".$obj->{error}->{type} . ".\n" . $obj->{error}->{message}
	    if defined($obj->{error});

	return $obj;
}

sub postPhoto {
	my($ua, $token, $title, $descr, $file) = @_;

	my $albumId = 1;
	#print "F: '$file'\n";
	open(my $fd, '<:bytes', $file) or die "No image: $!";
	binmode($fd);
	my @lines = <$fd>;
	my $cont = join '', @lines;
	close $fd;
	open($fd, '>:bytes', 'temp.jpg') or die "No out file: $!";
	print $fd $cont;
	close $fd;
	#my $photoObj = postGraph($ua, $token, 'photos', $albumId, [ message => $title, source => [ undef, 'image.jpg', Content => $cont ] ]);
	utf8::encode($title);
	utf8::encode($file);
	my $photoObj = postGraph($ua, $token, 'photos', $albumId, [ message => $title, source => [ $file ] ]);
	my $photoId = $photoObj->{id};
	#my $photoId = $albumId;
	postGraph($ua, $token, 'comments', $photoId, [ message => $descr ])
	    if defined($photoId) && $descr;
}

my $xc = loadXPath($self);
my $parser = new XML::LibXML;
my $settingsDoc = $parser->parse_file("facebook.xml");

my $token = getTextNode($xc, $settingsDoc, '/settings/sources/source/accessToken');
utf8::encode($token);
print "Token: '", $token, "'\n";

my $doc = loadKml($self);
my @placemarks = $xc->findnodes("/kml:kml/kml:Document/kml:Folder[kml:name='Photos']/kml:Placemark", $doc);

my $ua = new LWP::UserAgent agent => 'PhotoCatalog/0.01', cookie_jar => new HTTP::Cookies;
foreach(@placemarks) {
	#print Dumper($_);
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
	$descr =~ s@[[:space:]]*$@@;
	$fullDescr =~ m@<img src="http://.*/images/160/([^"]*)"@;
	my $img = '/home/user/public_html/photocatalog/images/' . $1;
	#my $dir = dirname($img);
	#my $file = basename($img);
	#my $outFile = "$dir/descriptions/$file.txt";
	print "Name: '", $name, "'\n";
	print "Description: '", $descr, "'\n";
	print "Image: '", $img, "'\n";
	#$img = basename($img);
	postPhoto($ua, $token, $name, $descr, $img)
	#print "Image: '", $dir, "', '", $file, "'\n";
	#next if !$descr;
	#open(my $fd, '>', $outFile) or die "Problem: $!";
	#print $fd $descr;
	#close $fd;
}

exit 0;
