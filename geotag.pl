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
use Getopt::Long;
use Time::Local;
use Image::ExifTool;
use File::Temp qw(tempfile);
use Data::Dumper;

require 'common.pl';

my $verbose = 0;
my $result = GetOptions("Verbose" => \$verbose);

if(!defined($ARGV[0])) {
	die "Usage: $0 image.jpg";
}
my $self = init();
$self->{verbose} = $verbose;
lockKml($self);

sub processImage {
	eval {
	my($file) = @_;

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
	if(!defined($exif->GetValue('ExifVersion'))) {
		warn "Image missing Exif header";
		return;
	}

	eval {
	if(!defined($exif->GetValue('GPSVersionID'))) {
		print "Geotagging photo.\n" if $self->{verbose};
		my $timestamp = $exif->GetValue('DateTimeOriginal');
		die "No date to use." if !defined($timestamp);
		$timestamp = parseExifDate($timestamp);

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
		print "GPS Prob: $@\n";
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
	my($fh, $tempFile) = tempfile;
	close $fh;
	system("jpegtran", "-optimize", "-progressive", $rotate, "-trim", "-copy", "comments", "-outfile", $tempFile, $file) == 0
	    or die "Failed to process image '$file'";
	$exif->SetNewValue('Orientation', 1)
	    if($rotate ne "");

	#Set GeoTagged EXIF data:
	$exif->SetNewValue('UserComment', 'Original Filename: '.$file.', Original Filesize: '.$fileSize.'.');
	$exif->SetNewValue('Copyright', 'Copyright © 2010 John Doe, All Rights Reserved');

	if($exif->WriteInfo($tempFile)) {
		unlink($file);
		rename($tempFile, $file);
	} else {
		warn "Failed to save Exif data";
		unlink($tempFile);
	}
	#my $info = $exif->ImageInfo($tempFile);
	#unlink($tempFile);
	my $info = $exif->ImageInfo($file);
	print "New UserComment: $info->{UserComment}\n" if exists($info->{UserComment});;
	print "New Copyright: $info->{Copyright}\n" if exists($info->{Copyright});;
	print "New GPSLatitude: $info->{GPSLatitude}\n" if exists($info->{GPSLatitude});;
	print "New GPSLongitude: $info->{GPSLongitude}\n" if exists($info->{GPSLongitude});;
	print "New GPSAltitude: $info->{GPSAltitude}\n" if exists($info->{GPSAltitude});;
	print "New GPSAltitudeRef: $info->{GPSAltitudeRef}\n" if exists($info->{GPSAltitudeRef});;
	};
}

processImage($_) foreach(@ARGV);

exit 0;


#print "GPSAltitude: $info->{GPSAltitude}\n" if exists($info->{GPSAltitude});
#print "GPSAltitudeRef: $info->{GPSAltitudeRef}\n" if exists($info->{GPSAltitudeRef});
#print "GPSAreaInformation: $info->{GPSAreaInformation}\n" if exists($info->{GPSAreaInformation});
#print "GPSDestBearing: $info->{GPSDestBearing}\n" if exists($info->{GPSDestBearing});
#print "GPSDestBearingRef: $info->{GPSDestBearingRef}\n" if exists($info->{GPSDestBearingRef});
#print "GPSDestDistance: $info->{GPSDestDistance}\n" if exists($info->{GPSDestDistance});
#print "GPSDestDistanceRef: $info->{GPSDestDistanceRef}\n" if exists($info->{GPSDestDistanceRef});
#print "GPSDestLatitude: $info->{GPSDestLatitude}\n" if exists($info->{GPSDestLatitude});
#print "GPSDestLongitude: $info->{GPSDestLongitude}\n" if exists($info->{GPSDestLongitude});
#print "GPSDifferential: $info->{GPSDifferential}\n" if exists($info->{GPSDifferential});
#print "GPSDOP: $info->{GPSDOP}\n" if exists($info->{GPSDOP});
#print "GPSImgDirection: $info->{GPSImgDirection}\n" if exists($info->{GPSImgDirection});
#print "GPSImgDirectionRef: $info->{GPSImgDirectionRef}\n" if exists($info->{GPSImgDirectionRef});
#print "GPSLatitude: $info->{GPSLatitude}\n" if exists($info->{GPSLatitude});
#print "GPSLongitude: $info->{GPSLongitude}\n" if exists($info->{GPSLongitude});
#print "GPSMapDatum: $info->{GPSMapDatum}\n" if exists($info->{GPSMapDatum});
#print "GPSMeasureMode: $info->{GPSMeasureMode}\n" if exists($info->{GPSMeasureMode});
#print "GPSProcessingMethod: $info->{GPSProcessingMethod}\n" if exists($info->{GPSProcessingMethod});
#print "GPSSatellites: $info->{GPSSatellites}\n" if exists($info->{GPSSatellites});
#print "GPSSpeed: $info->{GPSSpeed}\n" if exists($info->{GPSSpeed});
#print "GPSSpeedRef: $info->{GPSSpeedRef}\n" if exists($info->{GPSSpeedRef});
#print "GPSStatus: $info->{GPSStatus}\n" if exists($info->{GPSStatus});
#print "GPSDateTime: $info->{GPSDateTime}\n" if exists($info->{GPSDateTime});
#print "GPSTrack: $info->{GPSTrack}\n" if exists($info->{GPSTrack});
#print "GPSTrackRef: $info->{GPSTrackRef}\n" if exists($info->{GPSTrackRef});
#print "GPSVersionID: $info->{GPSVersionID}\n" if exists($info->{GPSVersionID});
#exit 0;
