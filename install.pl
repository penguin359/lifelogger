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


my $force = 0;
if(defined($ARGV[0])) {
	$force = 1 if $ARGV[0] eq "-f";
}

sub ask {
	my ($prompt, $default) = @_;

	$default = "" if !defined($default);
	print "$prompt [$default]: ";
	my $answer = <STDIN>;
	chomp($answer);
	$answer = $default if $answer eq "";
	return $answer;
}

foreach my $lib (
    "XML::DOM",
    "XML::DOM::XPath",
    "HTTP::Request",
    "XML::RSS",
    "XML::Atom::Feed") {
	eval "require $lib"; print STDERR "Need to install $lib\n" if $@;
}

my $author = ask("Author", "John Doe");
my $website = ask("Website", "http://www.example.org/");
my $email = ask("E-Mail", "webmaster\@example.org");
my $title = ask("Title", "My Adventurous Life");

sub installFile {
	my ($file) = @_;

	return if -f $file && !$force;
	open my $inFd, "$file.dist" or die "Can't open $file.dist";
	open my $outFd, ">$file" or die "Can't open $file";
	my $line;
	while($line = <$inFd>) {
		chomp($line);
		while($line =~ /^(.*)@@([A-Z_]+)@@(.*)$/) {
			my $pre = $1;
			my $var = $2;
			my $post = $3;
			if($var eq "AUTHOR") {
				$var = $author;
			} elsif($var eq "WEBSITE") {
				$var = $website;
			} elsif($var eq "EMAIL") {
				$var = $email;
			} elsif($var eq "TITLE") {
				$var = $title;
			} else {
				die "Unknown variable $var";
			}
			$line = "$pre$var$post";
		}
		print $outFd "$line\n";
	}
	close $outFd;
	close $inFd;
}

installFile("live.atom");
installFile("live.kml");
installFile("live.rss");
#installFile("locations.csv");
installFile("settings.pl");