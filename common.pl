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
use vars qw($apiKey $cwd $dataSource $dbUser $dbPass);
use Fcntl ':flock';
use Encode;
use XML::RSS;
use XML::Atom::Feed;
use XML::Atom::Entry;
use DBI;

require 'settings.pl';

my $dataFile = "$cwd/location.csv";
my $kmlFile = "$cwd/live.kml";
my $rssFile = "$cwd/live.rss";
my $atomFile = "$cwd/live.atom";
my $timestampFile = "$cwd/timestamp";

$XML::Atom::DefaultVersion = "1.0";
$XML::Atom::ForceUnicode = 1;

sub parseData {
	my($self, $lines) = @_;
	die "Missing header" if @$lines < 1;
	my $version = shift @$lines;
	chomp($version);
	die "Unreconized format or version" if $version ne "InstaMapper API v1.00";
	my $lastTimestamp = 0;
	my $entries = [];
	foreach(@$lines) {
		chomp;
		#next if $_ eq "";
		next if $_ !~ /^[[:digit:]]+,([^,]*,){6}/;
		my $entry = {};
		($entry->{key},      $entry->{label},     $entry->{timestamp},
		 $entry->{latitude}, $entry->{longitude}, $entry->{altitude},
		 $entry->{speed},    $entry->{heading})   = split /,/, $_, 8;
		$lastTimestamp = $entry->{timestamp}
		    if $lastTimestamp < $entry->{timestamp};
		push @$entries, $entry;
	}

	return ($entries, $lastTimestamp);
}

sub updateLastTimestamp {
	my($self, $timestamp) = @_;
	$self->{lastTimestamp} = $timestamp;
	open(my $fd, ">$timestampFile") or return;
	print $fd "$timestamp\n";
	close $fd;
}

sub lastTimestamp {
	my($self) = @_;

	return $self->{lastTimestamp} if exists($self->{lastTimestamp});
	if(open(my $fd, $timestampFile)) {
		my $timestamp = <$fd>;
		close $fd;
		chomp $timestamp;
		if($timestamp =~ /^\d+$/) {
			$self->{lastTimestamp} = $timestamp;
			return $self->{lastTimestamp};
		}
	}
	loadData($self);
	updateLastTimestamp($self, $self->{lastTimestampData});
	return $self->{lastTimestamp};
}

sub writeData {
	my($self, $entries) = @_;
	my $str = "InstaMapper API v1.00\n";
	my $lastTimestamp = lastTimestamp($self);
	foreach my $entry (@$entries) {
		$str .= "$entry->{key},$entry->{label},$entry->{timestamp},$entry->{latitude},$entry->{longitude},$entry->{altitude},$entry->{speed},$entry->{heading}\n";
		$lastTimestamp = $entry->{timestamp}
		    if $lastTimestamp < $entry->{timestamp};
	}

	open(my $fd, ">$dataFile") or die "Can't Write InstaMapper updates";
	print $fd $str;
	close $fd;

	updateLastTimestamp($self, $lastTimestamp);
}

sub appendData {
	my($self, $entries) = @_;
	my $str = "";
	my $lastTimestamp = lastTimestamp($self);
	foreach my $entry (@$entries) {
		$str .= "$entry->{key},$entry->{label},$entry->{timestamp},$entry->{latitude},$entry->{longitude},$entry->{altitude},$entry->{speed},$entry->{heading}\n";
		$lastTimestamp = $entry->{timestamp}
		    if $lastTimestamp < $entry->{timestamp};
	}

	open(my $fd, ">>$dataFile") or die "Can't append InstaMapper updates";
	print $fd $str;
	close $fd;

	updateLastTimestamp($self, $lastTimestamp);
}

sub loadData {
	my($self) = @_;

	return $self->{data} if exists($self->{data});

	open(my $fd, $dataFile) or die "Can't open data file";
	my @lines = <$fd>;
	close $fd;

	($self->{data}, $self->{lastTimestampData}) = parseData($self, \@lines);

	return $self->{data};
}

sub saveData {
	my($self, $str) = @_;

	open(my $fd, ">>$dataFile") or die "Can't write InstaMapper updates";
	print $fd $str;
	close $fd;
	#print Dumper($newEntries);
	#exit 0;
	#unlink($dataFile);
	#rename("$dataFile.bak", $dataFile);
}

sub closestEntry {
	my($self, $timestamp) = @_;

	my $entries = loadData($self);
	my $matchEntry = $entries->[0];
	my $offset = abs($matchEntry->{timestamp} - $timestamp);
	foreach my $entry (@$entries) {
		if(abs($entry->{timestamp} - $timestamp) < $offset) {
			$matchEntry = $entry;
			$offset = abs($entry->{timestamp} - $timestamp);
		}
	}

	return $matchEntry;
}

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
		Jan =>  0,
		Feb =>  1,
		Mar =>  2,
		Apr =>  3,
		May =>  4,
		Jun =>  5,
		Jul =>  6,
		Aug =>  7,
		Sep =>  8,
		Oct =>  9,
		Nov => 10,
		Dec => 11
	);
	my $mon = $monStrToNum{$monStr};
	$mon = 0 if !defined $mon;
	my $tzoffset = ($tzhour*60 + $tzmin)*60;
	$tzoffset *= -1 if $tzdir ne '-';
	#print "PD: $day,  $mday $mon $year  $hour:$min:$sec  $tzdir$tzhour:$tzmin\n";
	return mktime($sec, $min, $hour, $mday, $mon, $year-1900) + $tzoffset;
}

sub escapeText {
	my($a, $text) = @_;

	$text =~ s/&/&amp;/g;
	$text =~ s/</&lt;/g;
	$text =~ s/>/&gt;/g;
	$text =~ s/"/&quot;/g;
	$text =~ s/'/&apos;/g;
	$text;
}

sub loadRssFeed {
	my $rssFeed = new XML::RSS version => '2.0', encode_cb => \&escapeText;
	$rssFeed->parsefile($rssFile);
	return $rssFeed;
}

sub loadAtomFeed {
	return new XML::Atom::Feed $atomFile;
}

sub saveRssFeed {
	my($feed) = @_;

	$feed->save($rssFile);
}

sub saveAtomFeed {
	my($feed) = @_;

	my $data = $feed->as_xml;
	utf8::decode($data);
	open(my $fd, ">$atomFile") or print STDERR "Can't update atom file\n";
	print $fd $data;
	close $fd;
}

sub addRssEntry {
	my($feed, $title, $id, $content) = @_;

	$feed->add_item(title      => $title,
		       guid        => $id,
		       description => $content);
}

sub addAtomEntry {
	my($feed, $title, $id, $content) = @_;

	my $entry = new XML::Atom::Entry;
	$entry->title($title);
	$entry->id($id);
	$entry->content($content);
	$feed->add_entry($entry);
}

sub loadKml {
	my($self) = @_;

	my $parser = new XML::DOM::Parser;
	my $doc = $parser->parsefile($kmlFile);
	#my $doc = $parser->parsefile("test.kml");

	return $doc;
}

sub saveKml {
	my($self, $doc) = @_;

	#print $doc->toString;
	open(my $fd, ">$kmlFile") or die "Failed to open KML for writing";
	$doc->printToFileHandle($fd);
	#$doc->printToFile($kmlFile);
}

sub lockKml {
	my($self) = @_;

	return if exists($self->{lockFd});
	open(my $fd, $kmlFile) or die "Can't open kml file for locking";
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

	chdir $cwd;
	umask 0022;

	return $self;
}

1;
