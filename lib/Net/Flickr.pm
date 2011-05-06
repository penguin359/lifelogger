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


package Net::Flickr;

use 5.008_001;
use strict;
use warnings;

use utf8;
use open ':utf8', ':std';
use Digest::MD5;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(signFlickr);

my $flickrSecret = "";

sub signFlickr {
	my($url) = @_;

	my $md5 = new Digest::MD5;
	my($base, $query) = split /\?/, $url, 2;
	my @params = split /&/, $query;
	my %params;
	foreach(@params) {
		my ($key, $value) = split /=/, $_, 2;
		$params{$key} = $value;
	}
	$md5->add($flickrSecret);
	foreach(sort keys %params) {
		$md5->add($_);
		$md5->add($params{$_});
	}
	my $sig = $md5->hexdigest;
	return "$url&api_sig=$sig";
}

1;
