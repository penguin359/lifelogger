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

sub parseDataIM {
	my($self, $lines) = @_;

	die "Missing header" if @$lines < 1;
	my $version = shift @$lines;
	chomp($version);
	die "Unreconized format or version" if $version ne "InstaMapper API v1.00";

	my $sources = $self->{sources};
	my $multisource = 0;
	$multisource = 1
	    if @$sources > 0 ||
	       (@$sources == 1 &&
	        lc $sources->[0]->{type} eq "instamapper"
		&& defined($sources->[0]->{deviceKey}));
	my %keyToSource;
	my $defaultSource = 1;
	if($multisource) {
		foreach(@$sources) {
			$keyToSource{$_->{deviceKey}} = $_->{id}
			    if lc $_->{type} eq "instamapper" &&
			       defined($_->{deviceKey});
		}
	} else {
		$defaultSource = $sources->[0]->{id}
		    if defined($sources->[0]);
	}

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
		if($multisource) {
			$entry->{source} = $keyToSource{$entry->{key}};
		} else {
			$entry->{source} = $defaultSource;
		}
		push @$entries, $entry;
	}

	return ($entries, $lastTimestamp);
}

sub parseDataHeaderPC {
	my($self, $lines, $required) = @_;

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

	$required = ['source', 'timestamp', 'latitude', 'longitude']
	    if !defined($required);
	foreach(@$required) {
		die "Missing required field $_" if !defined($fields{$_});
	}
	push @$required, 'id' if defined($fields{id});

	return(\@fields, \%fields, $required);
}

sub parseDataPC {
	my($self, $lines, $required) = @_;

	my $fields;
	(undef, $fields, $required) = parseDataHeaderPC($self, $lines, $required);

	my $line = 3;
	my $lastTimestamp = 0;
	my $lastTrack = 0;
	my $lastSeg = 0;
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
		if(defined($entry->{id}) &&
		   $entry->{id} !~ /^\s*\d+\s*$/) {
			warn "Bad id on line ", $line-1, "\n";
			next;
		}
		if(defined($entry->{timestamp}) &&
		   $entry->{timestamp} !~ /^\s*\d+\s*$/) {
			warn "Bad timestamp on line ", $line-1, "\n";
			next;
		}
		if(defined($entry->{latitude}) &&
		   ($entry->{latitude} !~ /^\s*-?\d+(.\d*)?\s*$/ ||
		    $entry->{latitude} < -90 || $entry->{latitude} > 90)) {
			warn "Bad latitude on line ", $line-1, "\n";
			next;
		}
		if(defined($entry->{longitude}) &&
		   ($entry->{longitude} !~ /^\s*-?\d+(.\d*)?\s*$/ ||
		    $entry->{longitude} < -180 || $entry->{longitude} > 180)) {
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

my $fieldsTimestamp = [
    "source",
    "timestamp",
    "id",
    "seg",
    "track"];

sub updateLastTimestamp {
	my($self, $timestamp) = @_;

	print "Updating last timestamp.\n" if $self->{verbose};
	$self->{lastTimestamp} = $timestamp;
	$self->{sources}->[0]->{last} = {
		source => $self->{sources}->[0]->{id},
		timestamp => $timestamp,
		id => 0,
		seg => 0,
		track => 0
	};
	my @entries = ();
	push @entries, _lastTimestamp($self, $_)
	    foreach(keys %{$self->{sourcesId}});
	writeDataPC($self, \@entries, $timestampFile, $fieldsTimestamp);
}

sub _lastTimestamp {
	my($self, $id) = @_;

	if(!defined($id)) {
		return $self->{lastTimestamp}
		    if defined($self->{lastTimestamp});
		return 0;
	}

	my $source = $self->{sourcesId}->{$id};
	die "Source $id not configured" if !defined($source);

	my $last = $source->{last};
	$last->{source}	   = $id;
	$last->{timestamp} = 0 if !defined($last->{timestamp});
	$last->{id}	   = 0 if !defined($last->{id});
	$last->{seg}	   = 0 if !defined($last->{seg});
	$last->{track}	   = 0 if !defined($last->{track});

	return $last;
}

sub lastTimestamp {
	my($self, $id) = @_;

	my $sourcesId = $self->{sourcesId};
	my $source0 = $self->{sources}->[0];

	# Check if specific id declared.
	return _lastTimestamp($self, $id)
	    if defined($self->{lastTimestamp});
	if(open(my $fd, "<", $timestampFile)) {
		my @lines = <$fd>;
		close $fd;
		if(@lines > 1) {
			my($entries) = parseDataPC($self, \@lines, $fieldsTimestamp);
			foreach(@$entries) {
				$sourcesId->{$_->{source}}->{last} = $_
				    if defined($sourcesId->{$_->{source}});
			}
			$self->{lastTimestamp} = $source0->{last}->{timestamp}
			    if(defined($source0) &&
			       defined($source0->{last}->{timestamp}));
		} elsif(@lines == 1) {
			my $timestamp = $lines[0];
			chomp $timestamp;
			if($timestamp =~ /^\d+$/) {
				$self->{lastTimestamp} = $timestamp;
				$source0->{last} = {
					source => $source0->{id},
					timestamp => $self->{lastTimestamp},
					id => 0,
					seg => 0,
					track => 0
				} if defined($source0);
			}
		}
	}
	return _lastTimestamp($self, $id)
	    if defined($self->{lastTimestamp});
	print "No valid cached timestamp.\n" if $self->{verbose};
	readData($self);
	updateLastTimestamp($self, $self->{lastTimestampData});
	return _lastTimestamp($self, $id);
}

my $fieldsIM = [
    "key",
    "label",
    "timestamp",
    "latitude",
    "longitude",
    "altitude",
    "speed",
    "heading"];

my $fieldsPC = [
    "source",
    "id",
    "seg",
    "track",
    "timestamp",
    "latitude",
    "longitude",
    "altitude",
    "speed",
    "heading"];

sub writeEntries {
	my($self, $fd, $entries, $fields, $update) = @_;

	my $sourcesId = $self->{sourcesId};
	foreach my $entry (@$entries) {
		my $line = "";
		my $first = 1;
		foreach(@$fields) {
			$line .= "," if !$first;
			$line .= $entry->{$_} if defined($entry->{$_});
			$first = 0;
		}
		$line .= "\n";
		if($update &&
		   defined($entry->{source}) &&
		   defined($sourcesId->{$entry->{source}})) {
			my $last = _lastTimestamp($self, $entry->{source});
			$last->{timestamp} = $entry->{timestamp}
			    if defined($entry->{timestamp}) &&
			       $last->{timestamp} < $entry->{timestamp};
			$last->{id} = $entry->{id}
			    if defined($entry->{id}) &&
			       $last->{id} < $entry->{id};
			$last->{seg} = $entry->{seg}
			    if defined($entry->{seg}) &&
			       $last->{seg} < $entry->{seg};
			$last->{track} = $entry->{track}
			    if defined($entry->{track}) &&
			       $last->{track} < $entry->{track};
		}
		print $fd $line;
	}
}

sub writeDataIM {
	my($self, $entries, $file) = @_;

	my $update = 0;
	if(!defined($file)) {
		$file = $dataFile;
		$update = 1;
	}
	open(my $fd, ">", $file) or die "Can't Write InstaMapper updates";

	print $fd "InstaMapper API v1.00\n";
	my $lastTimestamp = lastTimestamp($self);
	$lastTimestamp = writeEntries($self, $fd, $entries, $fieldsIM, $update);
	close $fd;

	updateLastTimestamp($self, $lastTimestamp) if $update;
}

sub writeDataPC {
	my($self, $entries, $file, $fields) = @_;

	my $update = 0;
	if(!defined($file)) {
		$file = $dataFile;
		$update = 1;
	}
	open(my $fd, ">", $file) or die "Can't Write InstaMapper updates";

	$fields = $fieldsPC if !defined($fields);
	my $header = "";
	my $first = 1;
	foreach(@$fields) {
		$header .= "," if !$first;
		$header .= $_;
		$first = 0;
	}
	$header .= "\n";
	print $fd "PhotoCatalog v1.0\n";
	print $fd $header;
	my $lastTimestamp = lastTimestamp($self);
	$lastTimestamp = writeEntries($self, $fd, $entries, $fields, $update);
	close $fd;

	updateLastTimestamp($self, $lastTimestamp) if $update;
}

sub appendDataIM {
	my($self, $entries, $file) = @_;

	my $update = 0;
	if(!defined($file)) {
		$file = $dataFile;
		$update = 1;
	}
	open(my $fd, ">>", $file) or die "Can't append InstaMapper updates";

	my $lastTimestamp = lastTimestamp($self);
	$lastTimestamp = writeEntries($self, $fd, $entries, $fieldsIM, $update);
	close $fd;

	updateLastTimestamp($self, $lastTimestamp) if $update;
}

sub appendDataPC {
	my($self, $entries, $file) = @_;

	my $update = 0;
	if(!defined($file)) {
		$file = $dataFile;
		$update = 1;
	}
	open(my $fd, "+<", $file) or die "Can't append PhotoCatalog updates";

	# Grab first two lines of file and parse
	my @lines = ();
	push @lines, $_ if defined($_ = <$fd>);
	push @lines, $_ if defined($_ = <$fd>);
	my($fields, undef, $required) = parseDataHeaderPC($self, \@lines);
	seek $fd, 0, SEEK_END;

	my $lastTimestamp = lastTimestamp($self);
	$lastTimestamp = writeEntries($self, $fd, $entries, $fields, $update);
	close $fd;

	updateLastTimestamp($self, $lastTimestamp) if $update;
}

sub appendData {
	my($self, $entries, $file) = @_;

	my $appendFile = $file;
	$appendFile = $dataFile if !defined($appendFile);
	open(my $fd, "<", $appendFile) or die "Can't append updates";

	my $version = <$fd>;
	close $fd;

	die "Missing header for updates" if !defined($version);
	if($version =~ "InstaMapper API") {
		return appendDataIM($self, $entries, $file);
	} elsif($version =~ "PhotoCatalog") {
		return appendDataPC($self, $entries, $file);
	} else {
		die "Unrecognized file for updates";
	}
}

sub readData {
	my($self, $file) = @_;

	my $fd;
	my $data;
	if(!defined($file)) {
		return $self->{data} if exists($self->{data});

		open($fd, $dataFile) or die "Can't open data file";
		my @lines = <$fd>;
		close $fd;

		($self->{data}, $self->{lastTimestampData}) = parseData($self, \@lines);
		$data = $self->{data};
		my $last = {
			source => $self->{sources}->[0]->{id},
			timestamp => $self->{lastTimestampData},
			id => 0,
			seg => 0,
			track => 0
		};
	} else {
		open($fd, $file) or die "Can't open data file";
		my @lines = <$fd>;
		close $fd;

		($data) = parseData($self, \@lines);
	}

	return $data;
}

sub closestEntry {
	my($self, $timestamp) = @_;

	my $entries = readData($self);
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
