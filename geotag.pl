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

require 'common.pl';

my $verbose = 0;
my $result = GetOptions("verbose" => \$verbose);

if(!defined($ARGV[0])) {
	die "Usage: $0 image.jpg";
}
my $self = init();
$self->{verbose} = $verbose;
lockKml($self);

eval { processImage($self, $_); 1; } || warn $@ foreach(@ARGV);

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
