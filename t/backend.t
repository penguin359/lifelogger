#!/usr/bin/perl

use lib qw(../lib);
use Common;
use Test::Simple tests => 6;


ok(require "../backends/file.pl", 'require backend');

my $self = {
	settings => {
		cwd => "../t/test",
		defaults => {
			global => {
				maxdiff => 600,
			},
		},
	},
	sources => [
		{
			id => 0,
			type => 'instamapper',
			name => 'InstaMapper',
		},
	],
};
ok(defined(readData($self)), "Can read data");

ok(@{readData($self)} == 3, "Has 3 entries");

my $val;
eval { $val = closestEntry($self, $self->{sources}->[0], 1234567890); };
ok(!defined($val), "Invalid timestamp");

eval { $val = closestEntry($self, $self->{sources}->[0], 1324567890); };
ok(defined($val), "Valid timestamp");

ok($val->{timestamp} == 1324567876, "Correct timestamp");
