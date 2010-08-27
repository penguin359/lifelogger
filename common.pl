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
use vars qw($apiKey $cwd $dataSource $dbUser $dbPass $settings);
use Fcntl ':flock';
use POSIX qw(strftime);
use Time::Local;
use XML::LibXML;
#use DBI;
use Data::Dumper;

# Load default settings
$settings = {};
$settings->{apiKey} = "584014439054448247";
$settings->{cwd} = "/var/www/htdocs";
$settings->{backend} = "file";
$settings->{dataSource} = "DBI:Pg:dbname=photocatalog;host=localhost";
$settings->{dbUser} = "user";
$settings->{dbPass} = "S3cr3t!";
$settings->{website} = "http://www.example.org/";
$settings->{rssFeed} = "http://twitter.com/statuses/user_timeline/783214.rss";

require 'settings.pl';

# Convert from old-style settings file to new-style.
$settings->{apiKey} = $apiKey if defined($apiKey);
$settings->{cwd} = $cwd if defined($cwd);
$settings->{dataSource} = $dataSource if defined($dataSource);
$settings->{dbUser} = $dbUser if defined($dbUser);
$settings->{dbPass} = $dbPass if defined($dbPass);

require "backends/$settings->{backend}.pl";

my $files = {};
$files->{lock} = "$settings->{cwd}/lock";
$files->{kml} = "$settings->{cwd}/live.kml";
$files->{rss} = "$settings->{cwd}/live.rss";
$files->{atom} = "$settings->{cwd}/live.atom";

my $sources = [
	{
		id => '1',
		type => 'InstaMapper',
		apiKey => $settings->{apiKey},
	},
];

sub createPlacemark {
	my($doc) = @_;

	$doc->createElement('Placemark');
}

sub addTimestamp {
	my($doc, $mark, $timestamp) = @_;

	my $element = $doc->createElement('TimeStamp');
	my $when = $doc->createElement('when');
	my $text = $doc->createTextNode(strftime("%FT%TZ", gmtime($timestamp)));
	$when->appendChild($text);
	$element->appendChild($when);
	$mark->appendChild($element);
}

sub addExtendedData {
	my($doc, $mark, $data) = @_;

	my $extData = $doc->createElement('ExtendedData');
	foreach my $name (keys %$data) {
		my $element = $doc->createElement('Data');
		$element->setAttribute('name', $name);
		my $value = $doc->createElement('value');
		my $text = $doc->createTextNode($data->{$name});
		$value->appendChild($text);
		$element->appendChild($value);
		$extData->appendChild($element);
	}
	$mark->appendChild($extData);
}

sub addStyle {
	my($doc, $mark, $style) = @_;

	my $element = $doc->createElement('styleUrl');
	my $text = $doc->createTextNode("#$style");
	$element->appendChild($text);
	$mark->appendChild($element);
}

sub addPoint {
	my($doc, $mark, $latitude, $longitude, $altitude) = @_;

	my $point = $doc->createElement('Point');
	my $coord = $doc->createElement('coordinates');
	my $text;
	if(defined($altitude)) {
		$text = $doc->createTextNode("$longitude,$latitude,$altitude");
	} else {
		$text = $doc->createTextNode("$longitude,$latitude");
	}
	$coord->appendChild($text);
	$point->appendChild($coord);
	$mark->appendChild($point);
}

sub addName {
	my($doc, $mark, $name) = @_;

	my $element = $doc->createElement('name');
	my $text = $doc->createTextNode($name);
	$element->appendChild($text);
	$mark->appendChild($element);
}

sub addDescription {
	my($doc, $mark, $description) = @_;

	my $element = $doc->createElement('description');
	my $text = $doc->createTextNode($description);
	$element->appendChild($text);
	$mark->appendChild($element);
}

sub addPlacemark {
	my($doc, $base, $mark) = @_;

	$base->appendChild($mark);
	my $text = $doc->createTextNode("\n");
	$base->appendChild($text);
}

sub parseDate {
	my($date) = @_;

	$date =~ /(?:(\w{3}),)?\s+(\d+)\s+(\w{3})\s+(\d+)\s+(\d+):(\d+)(?::(\d+))?\s+([-+])(\d\d)(\d\d)/;
	my $day = $1;
	my $mday = $2;
	my $monStr = $3;
	my $year = $4;
	my $hour = $5;
	my $min = $6;
	my $sec = $7;
	my $tzdir = $8;
	my $tzhour = $9;
	my $tzmin = $10;
	$sec = 0 if !defined($sec);
	my %monStrToNum = (
		Jan =>  1,
		Feb =>  2,
		Mar =>  3,
		Apr =>  4,
		May =>  5,
		Jun =>  6,
		Jul =>  7,
		Aug =>  8,
		Sep =>  9,
		Oct => 10,
		Nov => 11,
		Dec => 12
	);
	my $mon = $monStrToNum{$monStr};
	$mon = 1 if !defined $mon;
	my $tzoffset = ($tzhour*60 + $tzmin)*60;
	$tzoffset *= -1 if $tzdir eq '-';
	#print "PD: $day,  $mday $mon $year  $hour:$min:$sec  $tzdir$tzhour:$tzmin\n";
	return timegm($sec, $min, $hour, $mday, $mon-1, $year) - $tzoffset;
}

sub parseExifDate {
	my($date) = @_;

	$date =~ /(\d+):(\d+):(\d+)\s+(\d+):(\d+):(\d+)/;
	my $year = $1;
	my $mon = $2;
	my $mday = $3;
	my $hour = $4;
	my $min = $5;
	my $sec = $6;
	#my $tzoffset = (-7*60 + 0)*60;
	#return timegm($sec, $min, $hour, $mday, $mon-1, $year) - $tzoffset;
	return timelocal($sec, $min, $hour, $mday, $mon-1, $year);
}

sub escapeText {
	my($self, $text) = @_;

	$text =~ s/&/&amp;/g;
	$text =~ s/</&lt;/g;
	$text =~ s/>/&gt;/g;
	$text =~ s/"/&quot;/g;
	$text =~ s/'/&#39;/g;
	$text;
}

sub loadRssFeed {
	my($self) = @_;

	eval "require XML::RSS;" or return;
	my $rssFeed = new XML::RSS version => '2.0', encode_cb => \&escapeText;
	$rssFeed->parsefile($self->{files}->{rss});
	return $rssFeed;
}

sub loadAtomFeed {
	my($self) = @_;

	eval "require XML::Atom::Entry;" or return;
	eval "require XML::Atom::Feed;" or return;

	$XML::Atom::DefaultVersion = "1.0";
	$XML::Atom::ForceUnicode = 1;

	return new XML::Atom::Feed $self->{files}->{atom};
}

sub saveRssFeed {
	my($self, $feed) = @_;

	return if !defined($feed);
	$feed->save($self->{files}->{rss});
}

sub saveAtomFeed {
	my($self, $feed) = @_;

	return if !defined($feed);
	my $data = $feed->as_xml;
	utf8::decode($data);
	open(my $fd, ">$self->{files}->{atom}") or print STDERR "Can't update atom file\n";
	print $fd $data;
	close $fd;
}

sub addRssEntry {
	my($self, $feed, $title, $id, $content) = @_;

	return if !defined($feed);
	$feed->add_item(title      => $title,
		       guid        => $id,
		       description => $content);
}

sub addAtomEntry {
	my($self, $feed, $title, $id, $content) = @_;

	return if !defined($feed);
	my $entry = new XML::Atom::Entry;
	$entry->title($title);
	$entry->id($id);
	$entry->content($content);
	$feed->add_entry($entry);
}

sub loadKml {
	my($self, $file) = @_;

	$file = $self->{files}->{kml} if !defined($file);
	open(my $fd, "<", $file) or die "Failed to open KML for reading";
	binmode $fd;
	my $doc = XML::LibXML->load_xml(IO => $fd);
	close $fd;

	return $doc;
}

sub saveKml {
	my($self, $doc, $file) = @_;

	$file = $self->{files}->{kml} if !defined($file);
	open(my $fd, ">", $file) or die "Failed to open KML for writing";
	binmode $fd;
	$doc->toFH($fd);
	close $fd;
}

sub lockKml {
	my($self) = @_;

	return if exists($self->{lockFd});
	open(my $fd, '>>', $self->{files}->{lock}) or die "Can't open lock file";
	flock($fd, LOCK_EX) or die "Can't establish file lock";
	$self->{lockFd} = $fd;
}

sub insertDB {
	my($self) = @_;

	$self->{dbh}->do("INSERT INTO locations (source, timestamp, latitude, longitude) VALUES (1, '2010-07-31 14:30', 10, 20)");
}

sub openDB {
	my($self) = @_;

	return if exists($self->{dbh});
	my $dbh = DBI->connect($dataSource, $dbUser, $dbPass);
	$self->{dbh} = $dbh;
}

sub init {
	my $self = {};

	$self->{settings} = $settings;
	$self->{files} = $files;
	$self->{sources} = $sources;

	chdir $settings->{cwd};
	umask 0022;

	return $self;
}

sub parseIsoTime {
	my($self, $time) = @_;

	# Subset of ISO 8601
	# YYYY-MM-DDTHH:MM:SS
	# Optional timezone suffix of Z or +HH:MM
	# Seconds, and symbols : and - are optional
	# Minutes in timezone are optional
	# Whitespace around timestamp is allowed
	if($time !~ /^\s*(\d\d\d\d)-?(\d\d)-?(\d\d)T(\d\d):?(\d\d)(?::?(\d\d))?(Z|([+-])(\d\d)(?::?(\d\d))?)?\s*$/) {
		warn "Can't parse ISO 8601 timestamp";
		return 0;
	}
	my $year = $1;
	my $mon = $2;
	my $mday = $3;
	my $hour = $4;
	my $min = $5;
	my $sec = $6;
	$sec = 0 if !defined($sec);
	if($mon < 1 || $mon > 12 ||
	   $mday < 1 || $mday > 31 ||
	   $hour < 0 || $hour > 24 ||
	   $min < 0 || $min > 59 ||
	   $sec < 0 || $sec > 60) {
		warn "Invalid ISO 8601 timestamp";
		return 0;
	}
	my $offset = $7;
	if(defined($offset)) {
		if($offset eq "Z") {
			$offset = 0;
		} else {
			my $hourOffset = $9;
			my $minOffset = $10;
			#print "O: $1$hourOffset:$minOffset ";
			$minOffset = 0 if !defined($minOffset);
			$offset = ($hourOffset*60 + $minOffset)*60;
			$offset *= -1 if $8 eq "-";
		}
		return timegm($sec, $min, $hour, $mday, $mon-1, $year) - $offset;
	} else {
		# No offset specified so use local time
		return timelocal($sec, $min, $hour, $mday, $mon-1, $year);
	}
}

sub createThumbnailsMod {
	my($self, $file, $path, $name, @sizes) = @_;

	print "Using Image::Resize\n" if $self->{verbose};
	my $image = new Image::Resize $file;
	foreach (@sizes) {
		print "Creating ${_}x${_} thumbnail for $name\n" if $self->{verbose};
		my $thumbnail = $image->resize($_, $_);
		open(my $fd, '>:bytes', "$path/$_/$name") or die "Can't open thumbnail: $!";
		binmode($fd);
		print $fd $thumbnail->jpeg(50);
		close $fd;
	}
}

sub createThumbnailsIM {
	my($self, $file, $path, $name, @sizes) = @_;

	print "Using ImageMagick\n" if $self->{verbose};
	foreach (@sizes) {
		print "Creating ${_}x${_} thumbnail for $name\n" if $self->{verbose};
		system('convert', '-geometry', $_.'x'.$_, $file, "$path/$_/$name");
	}
}

sub createThumbnails {
	my($self, $file) = @_;

	$file =~ m:^(.*/)?([^/]+)$:;
	my($path, $name) = ($1, $2);
	$path = "." if !defined($path);
	if(!defined($name) || $name eq "") {
		warn "Unparsable image filename '$file'";
		return;
	}

	if(eval 'require Image::Resize') {
		createThumbnailsMod($self, $file, $path, $name, ("32", "160"));
	} else {
		createThumbnailsIM($self, $file, $path, $name, ("32", "160"));
	}
}

1;
