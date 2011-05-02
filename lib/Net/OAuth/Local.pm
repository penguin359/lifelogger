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


package Net::OAuth::Local;

use 5.008_001;
use strict;
use warnings;

#use utf8;
#use open ':utf8', ':std';
use vars qw($oauthApps);
use Net::OAuth;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(requestSign);

$oauthApps = {};

eval { require 'OAuthConf.pm'; };

my $requestTypes = {
	request => {
		object => "Request Token",
		requiredParams => [ "callback" ],
	},
	authorize => {
		object => "Access Token",
		requiredParams => [ "verifier" ],
	},
	access => {
		object => "Access Token",
	},
	resource => {
		object => "Protected Resource",
	},
};

sub errorResponse {
	my($error, $detail) = @_;

	my $msg = "ERROR: $error";
	$msg .= ": $detail" if defined $detail;
	die $msg;
}

sub requestSign {
	my($obj) = @_;

	if(!defined($obj->{protocol}) ||
	   !defined($obj->{app}) ||
	   !defined($obj->{type}) ||
	   !defined($obj->{params})) {
		errorResponse("Invalid request") if $@;
	}

	errorResponse("Unknown protocol", $obj->{protocol}) if lc $obj->{protocol} ne "oauth 1.0a";
	errorResponse("Unknown app", $obj->{app}) if !defined($oauthApps->{lc $obj->{app}});
	errorResponse("Unknown type", $obj->{type}) if !defined($requestTypes->{lc $obj->{type}});

	open(my $randomFd, '<', "/dev/random") or errorResponse("Failed to get randomness");
	read $randomFd, my $data, 8;
	my $nonce = unpack "I", $data;
	eval { $nonce = unpack "Q", $data };

	my $request;
	eval {
		$request = Net::OAuth->request($requestTypes->{lc $obj->{type}}->{object})->new(
			timestamp => time,
			nonce => $nonce,
			version => "1.0",
			%{$obj->{params}},
			%{$oauthApps->{lc $obj->{app}}->{oauth}},
		);
	};
	errorResponse("Error generating request", $@) if $@;

	eval {
		$request->add_required_message_params(@{$requestTypes->{lc $obj->{type}}->{requiredParams}}) if defined($requestTypes->{lc $obj->{type}}->{requiredParams});
		$request->sign;
	};
	errorResponse("Error signing", $@) if $@;

	my $ret = {
		authorization => $request->to_authorization_header($oauthApps->{lc $obj->{app}}->{realm}),
		url => $request->to_url,
	};
	$ret->{post_body} = $request->to_post_body if $obj->{params}->{request_method} eq "POST";
	return $ret;
}

1;
