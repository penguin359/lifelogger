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
use POSIX qw(getcwd);


my $force = 0;
if(defined($ARGV[0])) {
	if($ARGV[0] eq "-f") {
		$force = 1;
	} else {
		die "Usage: $0 [-f]";
	}
}

die "Please run installer.pl from top-level of checkout" if ! -f 'settings.pl.dist';

sub ask {
	my ($prompt, $default) = @_;

	$default = "" if !defined($default);
	print "$prompt [$default]: ";
	my $answer = <STDIN>;
	chomp($answer);
	$answer = $default if $answer eq "";
	return $answer;
}

my $activePerl = 0;
my $autoinstall = '?';

sub installLib {
	my($lib) = @_;

	if($autoinstall eq '?') {
		$autoinstall = 0;
		if(eval "require ActivePerl") {
			print "You appear to be using ActivePerl\n";
			print "Do you want to automatically install dependencies? ";
			my $ans = <>;
			chomp($ans);
			$activePerl = 1;
			$autoinstall = 1 if $ans =~ /^y(es)?$/i;
			print "Not installing dependencies.\n" if !$autoinstall;
			print "\n";
		}
	}
	if($autoinstall && $activePerl) {
		system("ppm", "install", $lib);
	}
}

print "Installing Photocatalog\n";
print "\n";
print "Checking dependencies...\n";
foreach my $lib (
    "Bundle::LWP",
    "Image::ExifTool",
    "MIME::Tools",
    "XML::DOM",
    "XML::DOM::XPath",
    "XML::RSS",
    "XML::Atom") {
	if(!eval "require $lib") {
		print STDERR "Need to install $lib\n";
		if($lib eq "XML::RSS" || $lib eq "XML::Atom") {
			print STDERR "  This is a non-essential module\n";
		}
		installLib($lib);
	}
}

eval "require Image::Resize";
my $dummy = `convert`;
if($@ && $?) {
	print STDERR "Either Image::Resize needs to be installed or ImageMagick must be in the PATH\n";
	installLib("Image::Resize");
}

eval {
	require XML::DOM;
	$XML::DOM::VERSION =~ /^(\d+)\.(\d+)$/;
	if($1 < 1 || $1 == 1 && $2 < 44) {
		print "XML-DOM-$XML::DOM::VERSION is older than 1.44.\n";
		print "Please upgrade as older versions do not handle UTF-8 well.\n";
	}
};

print "\n";
print <<EOF;
Most of the functionality of these scripts currently requires an
InstaMapper account.  The main exception are photos that have already
been Geotagged, and soon will be Geotagged Tweets.  We plan to support
other sources as well, but for now, you can get an InstaMapper account
at http://www.instamapper.com/.

The default API Key is a demo car that can be used for testing.  Only
one device is supported at this time so don't use a Master API Key.

You can specify . for the Website if you just want to view the KML
files locally in Google Earth.

EOF

my $title = ask("Title", "My Adventurous Life");
my $author = ask("Author", "John Doe");
my $email = ask("E-Mail", "webmaster\@example.org");
my $website = ask("Website", "http://www.example.org/");
my $description = ask("Description", "My life is very adventurous!");
my $apiKey = ask("InstaMapper API Key", "584014439054448247");
my $cwd = getcwd;

my $rssFeed;
eval {
	require LWP::UserAgent;
	require HTTP::Request;
	my $username = ask("Twitter Username", "twitter");
	my $request = HTTP::Request->new(GET => "http://twitter.com/$username");
	my $ua = LWP::UserAgent->new;
	my $response = $ua->request($request);
	if($response->is_success) {
		my $html = $response->decoded_content;
		while(!defined($rssFeed) &&
		      $html =~ s{<link\s+(?:[^>]*\s+)?href="([^">]*/user_timeline/[^">]*)"(?:\s+[^>]*|/)?>}{}) {
			my $tag = $&;
			my $href = $1;
			#print "Possible: '$tag'\n";
			$rssFeed = $href
			    if $tag =~ m{\brel="alternate"} && $tag =~ m{\btype="application/rss\+xml"};
		}
		if(!defined($rssFeed)) {
			print STDERR "  No valid RSS feed found for user $username\n";
		}
	} else {
		print STDERR "  Failed to retrieve user's Twitter feed\n";
		print STDERR "  User does not exist\n" if $response->code == 404;
	}
};
print STDERR "  Failed to load Bundle::LWP: $@" if $@;
if(defined($rssFeed)) {
	print "  Found Twitter RSS feed for user: $rssFeed\n";
} else {
	$rssFeed = ask("Twitter RSS Feed", "http://twitter.com/statuses/user_timeline/783214.rss");
}
print "\n";

print "Your settings:\n";
print " Title:                  $title\n";
print " Author:                 $author\n";
print " E-Mail:                 $email\n";
print " Website:                $website\n";
print " Description:            $description\n";
print " InstaMapper API Key:    $apiKey\n";
print " Twitter RSS Feed:       $rssFeed\n";
print " Photocatalog Directory: $cwd\n";
my $ans = ask("Is this correct", "yes");
exit 0 if $ans !~ /y(es)?/i;
print "\n";

# Support for Windows users
$cwd =~ s:\\:\\\\:g;

sub installFile {
	my ($file) = @_;

	return if -f $file && !$force;
	print "Installing $file\n";
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
			} elsif($var eq "DESCRIPTION") {
				$var = $description;
			} elsif($var eq "TITLE") {
				$var = $title;
			} elsif($var eq "APIKEY") {
				$var = $apiKey;
			} elsif($var eq "CWD") {
				$var = $cwd;
			} elsif($var eq "RSSFEED") {
				$var = $rssFeed;
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

installFile("examples/aliases");
installFile("examples/crontab");
installFile("examples/procmailrc");
installFile("live.atom");
installFile("live.kml");
installFile("live.rss");
installFile("location.csv");
installFile("settings.pl");
