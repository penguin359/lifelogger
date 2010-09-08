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
use Fcntl qw(:seek);


my $dataFile = "$settings->{cwd}/location.csv";
my $timestampFile = "$settings->{cwd}/timestamp";

sub parseDataHeaderPC {
	my($self, $lines) = @_;

	die "Missing header" if @$lines < 2;
	my $version = shift @$lines;
	chomp($version);
	die "Unreconized format or version" if $version ne "PhotoCatalog v1.0";

	my $header = shift @$lines;
	chomp($header);
	my @fields = split /,/, $header;
	my %fields;
	for(my $i = 0; $i < @fields; $i++) {
		$fields{$fields[$i]} = $i;
	}

	my @required = ('timestamp', 'latitude', 'longitude');
	foreach(@required) {
		die "Missing required field $_" if !defined($fields{$_});
	}
	push @required, 'id' if defined($fields{id});

	return(\@fields, \%fields, \@required);
}

sub parseDataPC {
	my($self, $lines) = @_;

	my(undef, $fields, $required) = parseDataHeaderPC($self, $lines);

	#print Dumper($fields, $required);
	my $line = 3;
	my $lastTimestamp = 0;
	my $entries = [];
	line: foreach(@$lines) {
		chomp;
		my @cells = split /,/;
		my $entry = {};
		foreach(keys %$fields) {
			$entry->{$_} = $cells[$fields->{$_}]
			    if(defined($cells[$fields->{$_}]) &&
			       $cells[$fields->{$_}] ne "");
		}
		$entry->{id} = $line if !defined($fields->{id});
		$line++;

		foreach(@$required) {
			if(!defined($entry->{$_})) {
				warn "Missing field $_ on line ", $line-1, "\n";
				next line;
			}
		}
		if($entry->{id} !~ /^\s*\d+\s*$/) {
			warn "Bad id on line ", $line-1, "\n";
			next;
		}
		if($entry->{timestamp} !~ /^\s*\d+\s*$/) {
			warn "Bad timestamp on line ", $line-1, "\n";
			next;
		}
		if($entry->{latitude} !~ /^\s*-?\d+(.\d*)?\s*$/ ||
		   $entry->{latitude} < -90 || $entry->{latitude} > 90) {
			warn "Bad latitude on line ", $line-1, "\n";
			next;
		}
		if($entry->{longitude} !~ /^\s*-?\d+(.\d*)?\s*$/ ||
		   $entry->{longitude} < -180 || $entry->{longitude} > 180) {
			warn "Bad longitude on line ", $line-1, "\n";
			next;
		}

		$lastTimestamp = $entry->{timestamp}
		    if $lastTimestamp < $entry->{timestamp};
		push @$entries, $entry;
	}
	#print Dumper($entries);
	#exit 0;

	return ($entries, $lastTimestamp);
}

sub parseDataIM {
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

sub parseData {
	my($self, $lines) = @_;

	die "Missing header" if @$lines < 1;
	my $version = @$lines[0];
	if($version =~ "InstaMapper API") {
		return parseDataIM($self, $lines);
	} elsif($version =~ "PhotoCatalog") {
		return parseDataPC($self, $lines);
	} else {
		die "Unrecognized file";
	}
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

	return $self->{sources}->[0]->{lastTimestamp} if exists($self->{sources}->[0]->{lastTimestamp});
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

sub appendDataPC {
	my($self, $entries) = @_;

	open(my $fd, "+<", $dataFile) or die "Can't append PhotoCatalog updates";

	# Grab first two lines of file and parse
	my @lines = ();
	push @lines, $_ if defined($_ = <$fd>);
	push @lines, $_ if defined($_ = <$fd>);
	my($fields, undef, $required) = parseDataHeaderPC($self, \@lines);
	seek $fd, 0, SEEK_END;

	my $lastTimestamp = lastTimestamp($self);
	foreach my $entry (@$entries) {
		my $line = "";
		my $first = 1;
		foreach(@$fields) {
			$line .= "," if !$first;
			$line .= $entry->{$_} if defined($entry->{$_});
			$first = 0;
		}
		$line .= "\n";
		$lastTimestamp = $entry->{timestamp}
		    if defined($entry->{timestamp}) &&
		       $lastTimestamp < $entry->{timestamp};
		print $fd $line;
	}

	close $fd;

	#updateLastTimestamp($self, $lastTimestamp);
}

sub appendDataIM {
	my($self, $entries) = @_;

	open(my $fd, "+<", $dataFile) or die "Can't append InstaMapper updates";
	seek $fd, 0, SEEK_END;

	my $lastTimestamp = lastTimestamp($self);
	foreach my $entry (@$entries) {
		print $fd "$entry->{key},$entry->{label},$entry->{timestamp},$entry->{latitude},$entry->{longitude},$entry->{altitude},$entry->{speed},$entry->{heading}\n";
		$lastTimestamp = $entry->{timestamp}
		    if defined($entry->{timestamp}) &&
		       $lastTimestamp < $entry->{timestamp};
	}

	close $fd;

	updateLastTimestamp($self, $lastTimestamp);
}

sub appendData {
	my($self, $entries) = @_;

	open(my $fd, "<", $dataFile) or die "Can't append updates";

	my $version = <$fd>;
	close $fd;

	die "Missing header for updates" if !defined($version);
	if($version =~ "InstaMapper API") {
		return appendDataIM($self, $entries);
	} elsif($version =~ "PhotoCatalog") {
		return appendDataPC($self, $entries);
	} else {
		die "Unrecognized file for updates";
	}
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
