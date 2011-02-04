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
use Image::ExifTool;
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
#$settings->{rssFeed} = "http://twitter.com/statuses/user_timeline/783214.rss";

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
	#$text =~ s/'/&#39;/g;
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

	print "Loading KML file.\n" if $self->{verbose};
	$file = $self->{files}->{kml} if !defined($file);
	open(my $fd, "<", $file) or die "Failed to open KML for reading";
	binmode $fd;
	my $parser = new XML::LibXML;
	my $doc = $parser->parse_fh($fd);
	close $fd;

	return $doc;
}

sub saveKml {
	my($self, $doc, $file) = @_;

	print "Saving KML file.\n" if $self->{verbose};
	$file = $self->{files}->{kml} if !defined($file);
	open(my $fd, ">", $file) or die "Failed to open KML for writing";
	binmode $fd;
	$doc->toFH($fd);
	close $fd;
}

sub lockKml {
	my($self) = @_;

	return if exists($self->{lockFd});
	print "Waiting for lock...\n" if $self->{verbose};
	open(my $fd, '>>', $self->{files}->{lock}) or die "Can't open lock file";
	flock($fd, LOCK_EX) or die "Can't establish file lock";
	$self->{lockFd} = $fd;
	print "Locked.\n" if $self->{verbose};
}

sub loadXPath {
	my($self) = @_;

	return $self->{xc} if exists($self->{xc});
	my $xc = new XML::LibXML::XPathContext;
	$xc->registerNs('kml', "http://www.opengis.net/kml/2.2");
	$xc->registerNs('gpx', "http://www.topografix.com/GPX/1/1");
	$self->{xc} = $xc;

	return $xc;
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
	$self->{sources} = $settings->{sources};
	$self->{sources} = $sources if !defined($self->{sources});

	$self->{sourcesId} = {};
	foreach(@{$self->{sources}}) {
		next if !defined($_->{id});
		if(defined($self->{sourcesId}->{$_->{id}})) {
			warn "Duplicate source id";
			next;
		}
		$self->{sourcesId}->{$_->{id}} = $_;
	}

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

sub mkdirPath {
	my($path) = @_;

	if($^O eq "MSWin32") {
		# Windows NT and newer create intermediate directories
		# by default
		$path =~ tr:/:\\:;
		system('mkdir', $path);
	} else {
		system('mkdir', '-p', $path);
	}
}

sub createThumbnailsMod {
	my($self, $file, $path, @sizes) = @_;

	print "Using Image::Resize\n" if $self->{verbose};
	my $image = new Image::Resize "$path/$file";
	foreach (@sizes) {
		my $path2 = "$path/$_/$file";
		$path2 =~ s/[^\/]*$//;
		mkdirPath($path2);
		print "Creating ${_}x${_} thumbnail for $file\n" if $self->{verbose};
		my $thumbnail = $image->resize($_, $_);
		open(my $fd, '>:bytes', "$path/$_/$file") or die "Can't open thumbnail: $!";
		binmode($fd);
		print $fd $thumbnail->jpeg(50);
		close $fd;
	}
}

sub createThumbnailsIM {
	my($self, $file, $path, @sizes) = @_;

	print "Using ImageMagick\n" if $self->{verbose};
	foreach (@sizes) {
		my $path2 = "$path/$_/$file";
		$path2 =~ s/[^\/]*$//;
		mkdirPath($path2);
		print "Creating ${_}x${_} thumbnail for $file\n" if $self->{verbose};
		system('convert', '-geometry', $_.'x'.$_, "$path/$file", "$path/$_/$file");
	}
}

sub createThumbnails {
	my($self, $file) = @_;

	#$file =~ m:^(.*/)?([^/]+)$:;
	#my($path, $name) = ($1, $2);
	#$path = "." if !defined($path);
	#if(!defined($name) || $name eq "") {
	#	warn "Unparsable image filename '$file'";
	#	return;
	#}
	my $path = "$self->{settings}->{cwd}/images";

	if(eval 'require Image::Resize') {
		createThumbnailsMod($self, $file, $path, ("32", "160"));
	} else {
		createThumbnailsIM($self, $file, $path, ("32", "160"));
	}
}

sub processImage {
	my $filename2;
	eval {
	my($self, $file, $name) = @_;

	$name = "Image" if !defined($name);
	print "Processing image $file.\n" if $self->{verbose};
	my $fileSize = -s $file;
	#my $utcTime = 0;

	my $exif = new Image::ExifTool;
	$exif->Options(Binary => 1, PrintConv => 0);
	#my $info = $exif->ImageInfo($file);
	#print Dumper($info);
	if(!$exif->ExtractInfo($file)) {
		warn "Error: ", $exif->GetValue('Error');
		return;
	}
	$exif->SetNewValuesFromFile($file);
	if(!defined($exif->GetValue('ExifVersion'))) {
		warn "Image missing Exif header";
		return;
	}

	my $timestamp = $exif->GetValue('DateTimeOriginal');
	die "No date to use for naming file." if !defined($timestamp);
	$timestamp = parseExifDate($timestamp);

	eval {
	if((!defined($exif->GetValue('GPSVersionID')) &&
	    !defined($exif->GetValue('GPSLatitude'))) ||
	   ($exif->GetValue('GPSLatitude') == 0 &&
	    $exif->GetValue('GPSLongitude') == 0)) {
		print "Geotagging photo.\n" if $self->{verbose};
		#my $timestamp = $exif->GetValue('DateTimeOriginal');
		#die "No date to use." if !defined($timestamp);
		#$timestamp = parseExifDate($timestamp);

		if($timestamp <= 981119752) {
			die "Image timestamp is out of bounds!"
		}
		my $entry = closestEntry($self, $timestamp);
		die "No entries." if !defined($entry);
		#print Dumper($entry);
		if(abs($entry->{timestamp} - $timestamp) > 600) {
			die "Image timestamp ($timestamp) not close to any GPS entry ($entry->{timestamp}) offset is:  " . abs(($timestamp - $entry->{timestamp})/60) . " minutes.";
		}

		my $longitude = $entry->{longitude};
		my $longitudeRef = "E";
		if ($longitude < 0) {
			$longitude *= -1;
			$longitudeRef = "W";
		}

		my $latitude = $entry->{latitude};
		my $latitudeRef = "N";
		if ($latitude < 0) {
			$latitude *= -1;
			$latitudeRef = "S";
		}

		my $altitude = $entry->{altitude};
		my $altitudeRef = 0;
		if ($altitude < 0) {
			$altitude *= -1;
			$altitudeRef = 1;
		}

		$exif->SetNewValue('GPSLatitudeRef', $latitudeRef);
		$exif->SetNewValue('GPSLatitude', $latitude);
		$exif->SetNewValue('GPSLongitudeRef', $longitudeRef);
		$exif->SetNewValue('GPSLongitude', $longitude);
		$exif->SetNewValue('GPSAltitudeRef', $altitudeRef);
		$exif->SetNewValue('GPSAltitude', $altitude);
		#$exif->SetNewValue('GPSTimeStamp', $utcTime);
	}
	};
	if($@) {
		die "GPS Prob: $@\n";
	}

	#Remove Thumbnail:
	$exif->SetNewValue('IFD1:*');

	my @rotate = ( undef,
		       "",
		       "-flip horizontal",
		       "-rotate 180",
		       "-flip vertical",
		       "-transpose",
		       "-rotate 90",
		       "-transverse",
		       "-rotate 270" );

	my $orientation = $exif->GetValue('Orientation');
	my $rotate = $rotate[$orientation] if defined($orientation);
	if(!defined($rotate)) {
		warn "Orientation not recognized.\n";
		$rotate = "";
	}
	my $outFile = strftime("%m%B/%d%a, %b %e/%H%M%S", localtime($timestamp));
	my $filename = "$self->{settings}->{cwd}/images/$outFile$name.jpg";
	my $path = $filename;
	$path =~ s/[^\/]*$//;
	mkdirPath($path);
	#my($fh, $tempFile) = tempfile;
	#close $fh;
	my $tempFile = $filename;
	my @jpegtran = ("jpegtran", "-optimize", "-progressive");
	push(@jpegtran, split /\s+/, $rotate) if $rotate ne "";
	push @jpegtran, ("-trim", "-copy", "comments", "-outfile", $tempFile, $file);
	if($self->{verbose}) {
		print join(' ', @jpegtran), "\n";
	}
	my $status = system(@jpegtran);
	if(($^O eq "MSWin32" && $status != 0) || $status < 0) {
		# Jpegtran is not installed so just copy
		# image without rotating
		warn "jpegtran not installed so can't rotate image\n";
		open(my $inFd, '<:bytes', $file);
		binmode $inFd;
		open(my $outFd, '>:bytes', $tempFile);
		binmode $outFd;
		while(<$inFd>) {
			print $outFd $_;
		}
		close $outFd;
		close $inFd;
	} elsif($status != 0) {
		die "Failed to process image '$file'";
	} else {
		$exif->SetNewValue('Orientation', 1)
		    if($rotate ne "");
	}

	#Set GeoTagged EXIF data:
	my $originalName = $file;
	$originalName =~ s:.*[/\\]::;
	$exif->SetNewValue('UserComment', 'Original Filename: '.$originalName.', Original Filesize: '.$fileSize.'.');
	$exif->SetNewValue('Copyright', 'Copyright © 2010 John Doe, All Rights Reserved');

	#print Dumper($exif->GetInfo);
	#my $info = $exif->ImageInfo($tempFile);
	#print Dumper($exif->GetInfo);
	if($exif->WriteInfo($tempFile)) {
		unlink($file);
		#rename($tempFile, $file);
	} else {
		warn "Failed to save Exif data", $exif->GetValue("Error");
		unlink($tempFile);
	}
	if($self->{verbose}) {
		my $info = $exif->ImageInfo($tempFile);
		#print Dumper($exif->GetInfo);
		utf8::decode($info->{Copyright});
		print "New UserComment: $info->{UserComment}\n" if exists($info->{UserComment});;
		print "New Copyright: $info->{Copyright}\n" if exists($info->{Copyright});;
		print "New GPSLatitude: $info->{GPSLatitude}\n" if exists($info->{GPSLatitude});;
		print "New GPSLongitude: $info->{GPSLongitude}\n" if exists($info->{GPSLongitude});;
		print "New GPSAltitude: $info->{GPSAltitude}\n" if exists($info->{GPSAltitude});;
		print "New GPSAltitudeRef: $info->{GPSAltitudeRef}\n" if exists($info->{GPSAltitudeRef});;
	}
	#unlink($tempFile);

	$filename2 = "$outFile$name.jpg";
	};
	print STDERR $@ if $@;
	return $filename2;
}

sub addImage {
	my($filename, $self, $doc, $base, $title, $description) = @_;

	my $path = "$self->{settings}->{cwd}/images/$filename";
	my $exif = new Image::ExifTool;
	open(my $fd, '<:bytes', $path) or die "Can't open file $path";
	binmode($fd);
	my $info = $exif->ImageInfo($fd);
	close $fd;

	my $website = $self->{settings}->{website};

	my $timestamp;
	if(exists $info->{DateTimeOriginal}) {
		$timestamp = parseExifDate($info->{DateTimeOriginal});
	}
	my $latitude;
	my $longitude;
	my $altitude;
	if(!exists $info->{GPSPosition}) {
		print STDERR "No GPS location to add image to.\n";
		return;
	}
	$info->{GPSPosition} =~ /(\d+)\s*deg\s*(?:(\d+)'\s*(?:(\d+(?:\.\d*)?)")?)?\s*([NS]),\s*(\d+)\s*deg\s*(?:(\d+)'\s*(?:(\d+(?:\.\d*)?)")?)?\s*([EW])/;
	#print "Loc: $1° $2' $3\" $4, $5° $6' $7\" $8\n";
	$latitude = $1 + ($2 + $3/60)/60;
	$latitude *= -1 if $4 eq "S";
	$longitude = $5 + ($6 + $7/60)/60;
	$longitude *= -1 if $8 eq "W";

	my $url = "$website/images/$filename";
	my $thumbnailUrl = "$website/images/160/$filename";
	my $html = "";
	my $mark = createPlacemark($doc);
	if(defined($title)) {
		$html .= '<p><b>' . escapeText($self, $title) . '</b></p>';
		addName($doc, $mark, $title);
	}
	if(defined($description)) {
		$html .= '<p>' . escapeText($self, $description) . '</p>';
	}
	$html .= '<a href="'  . escapeText($self, $url) . '">' .
		 '<img src="' . escapeText($self, $thumbnailUrl) . '">' .
		 '</a>';
	addDescription($doc, $mark, $html);
	addRssEntry($self,  $self->{rssFeed},  $title, $url, $html);
	addAtomEntry($self, $self->{atomFeed}, $title, $url, $html);
	addTimestamp($doc, $mark, $timestamp) if defined($timestamp);
	addStyle($doc, $mark, 'photo');
	addPoint($doc, $mark, $latitude, $longitude, $altitude);
	addPlacemark($doc, $base, $mark);
	my $fieldsImage = [
		"filename",
		"title",
		"description",
	];
	writeDataPC($self, [], 'images.csv', $fieldsImage, 1) if ! -f 'images.csv';
	appendDataPC($self, [{ filename => $filename, title => $title, description => $description }], 'images.csv', 1, $fieldsImage);
}

sub findSource {
	my($self, $type, $id) = @_;

	my $source;
	if(defined($id)) {
		$source = $self->{sourcesId}->{$id};
		die "Source $id is not configured.\n"
		    if !defined($source);
		die "Source $id is not $type.\n"
		    if lc $source->{type} ne lc $type;
	} else {
		foreach(@{$self->{sources}}) {
			if(lc $_->{type} eq lc $type) {
				$source = $_;
				last;
			}
		}
		die "No $type source has been configured.\n"
		    if !defined($source);
	}

	return $source;
}

#sub findKmlNode {
#	my($self, $source, $doc, $id, $legacyPath) = @_;
#
#	my $xc = loadXPath($self);
#	my $locationPath = $legacyPath;
#	my $locationId = $source->{kml}->{location};
#	$locationPath = "//kml:Folder[\@id='$locationId']" if defined($locationId);
#	my @base = $xc->findnodes($locationPath, $doc);
#	my $parser = new XML::LibXML;
#	my $rssDoc = $parser->parse_file($rssFile);
#	my @items = $xc->findnodes('/rss/channel/item', $rssDoc);
#
#	die "Can't find base for RSS" if @base != 1;
#}

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

1;
