#!/usr/bin/env perl
#This script written by ferringb on #Gentoo @ irc.freenode.net as an adaptation of Ronald Bynoe's photocat bash script.
#Please retain this header in all modifications of the script.
#See http://web.praeluceo.net/benchmark.sxw for my explanation on why to use progressive-scan format.
#
#This work is licensed under the Creative Commons Attribution-ShareAlike License. To view a copy of this license, visit http://creativecommons.org/licenses/by-sa/1.0/ or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.
#
#Version:  1.3
#History:
# 04/19/2004 - bash script converted to perl
# 05/12/2004 - added verbose output, and logging ability.

#Todo:
# 1)  Add ability to accept command-line switches
#    -h, -c, -l, -r, f
# 2)  Cleanup output
# 3)  Integrate GeoTagging into script, the ability to handle external InstaMapper database & automatically create monthly/yearly kml files with photos on route with associated twitter & e-mail posts w/icons.
# 4)  Replace jhead usage with Image::ExifTool
# 5)  Ensure it handles photos from multiple cameras correctly, especially camera phones.

use Date::Manip qw(UnixDate);
use strict;
use warnings;
my @args = @ARGV;
my @files;
my $jhead = `which jhead`;		chomp($jhead);
my $jpegtran = `which jpegtran`;	chomp($jpegtran);
my $logfile = "/dev/null";

my @fancy_month = ('Unknown', '01-Jan', '02-Feb', '03-March', '04-April', '05-May', '06-June', '07-July', '08-August', '09-Sept', '10-Oct', '11-Nov', '12-Dec');
if ( ! -x $jpegtran ) {
	print "This script requires jpegtran to be installed\n";
	die("please install it before continuing.\n");
}
if( ! -x $jhead ) {
	print "This script requires jhead to be installed\n";
	die("please install it before continuing.\n");
} else {
	$jhead .= ' -exonly';
}

##insert opts code splicing from @args
###temporarily hardwire script to always log & compress:
my $recompress = 1;
my $logging = 1;
###
##

if(! scalar(@args)) {
	die("Error, too few arguments.\nTry photocat -h for help.\n");
} else {
	@files = @args;
}

my $ext = 'jpeg';

foreach my $file (@files) {
        my $comments = '"Original Filename:   "' . ${file} . '" Copyright 2009 Ronald@Bynoe.us"';
	my @start = time();
	my $data = `$jhead '$file'`;
	$data=~/Date\/Time\s+:\s+(\d{4}):(\d{1,2}):(\d{1,2})\s+(\d{1,2}):(\d{1,2}):(\d{1,2})/;
	my ($year, $month, $day, $hour, $minute, $second) = ($1, $2, $3, $4, $5, $6);
	$data=~/Camera\s+model\s+:\s+([^\n]+)/;
	my $model = $1;

	$model =~ s/$_//gi foreach qw(digital camera kodak canon olympus zoom);
	$model =~ s/^\s+|\s+$//g;


	if($logging) {
	$logfile = sprintf("%s/%s/%s", $year, $fancy_month[$month], "output.log");
	}

	if($recompress) {
	my $oSize = (-s $file);

	print "Optimizing photo (this is a lossless transform)...";
		system("$jhead -c -dt -autorot '$file' 1>> $logfile 2>&1 &&
		$jhead -c -cmd '\'$jpegtran\' -progressive -o &i > &o' '$file' 1>> $logfile 2>&1");
	my $percent = sprintf ("%.2f", (100 - (((-s $file)/$oSize) * 100)));
	printf "%s is %.2f%% smaller, done.\n",$file,$percent;
	}

	print "Sorting photo...";
	my $dir = sprintf("%s/%s/%s/%s", $year, $fancy_month[$month], $day);
	my $timestamp;
	if ( ! -e $dir ) {
	#Calling the system is bad, but
		system("mkdir -p '${dir}'");
	#the below line doesn't support the -p(arent) option
	#and I don't know how to "make" it work.
	#mkdir($dir,0755);
	#
		$timestamp = UnixDate(sprintf("%s/%s/%s 00:00:00", $month, $day, $year), '%s');
		utime($timestamp, $timestamp, $dir);
	}

	my $newfile=sprintf('%s/Photo_%02i%02i', $dir, $hour, $minute);
	if ( -e "${newfile}.${ext}" ) {
		$newfile .= sprintf("%02i", $second);
		if ( -e "${newfile}.${ext}") {
			warn("bailing. ${newfile}.${ext} exists already!\n");
			next;
		}
	}
	print "moved to $newfile.$ext.\n";
	system("`wrjpgcom -c '${comments}' '${file}' > '${newfile}.${ext}';rm '$file'`");
	#$timestamp = UnixDate(sprintf("%s/%s/%s %s:%s:%s", $month, $day, $year, $hour, $minute, $second), '%s');
	print "Setting file timestamp to original date & time...";
	#utime($timestamp, $timestamp, $newfile.$ext);
	system("jhead -c -ft '${newfile}.${ext}' 1>> $logfile 2>&1");
	#
	#use Digest::MD5;
	#my $file = shift || "/etc/passwd";
	#open(FILE, $file) or die "Can't open '$file': $!";
	#binmode(FILE);
	#print Digest::MD5->new->addfile(*FILE)->hexdigest, " $file\n";
	print "done.\n";
	print "Finished processing Photo_$hour$minute.$ext\n";
}
