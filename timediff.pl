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
use strict;
use warnings;

use utf8;
use open ':utf8', ':std';
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/lib";

require 'common.pl';

my $usage = "[-diff time]";
my $diff = 300;

my $self = init($usage, {"diff=i" => \$diff});
die $self->{usage} if @ARGV > 0;
lockKml($self);

my $entries = readData($self);
my $lastTimestamp = @{$entries}[0]->{timestamp};
my $line = 2;
foreach(@$entries) {
	if(abs($_->{timestamp} - $lastTimestamp) > $diff) {
		printf "Big time difference: %.2f @ %d at line $line\n", ($_->{timestamp} - $lastTimestamp)/60, $_->{timestamp};
	}
	if($_->{timestamp} == $lastTimestamp && $line > 2) {
		print "Duplicate timestamp: $_->{timestamp} at line $line\n";
	}
	if($_->{timestamp} < $lastTimestamp) {
		printf "Time went backwarks: %.2f @ %d at line $line\n", ($_->{timestamp} - $lastTimestamp)/60, $_->{timestamp};
	}
	$lastTimestamp = $_->{timestamp};
	$line++;
}
