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


my $dataFile = "$settings->{cwd}/location.csv";
my $timestampFile = "$settings->{cwd}/timestamp";

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

sub writeDataFile {
	my($self, $entries, $file) = @_;

	my $str = "InstaMapper API v1.00\n";
	foreach my $entry (@$entries) {
		$str .= "$entry->{key},$entry->{label},$entry->{timestamp},$entry->{latitude},$entry->{longitude},$entry->{altitude},$entry->{speed},$entry->{heading}\n";
	}

	open(my $fd, ">$file") or die "Can't Write InstaMapper updates";
	print $fd $str;
	close $fd;
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

1;
