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


package Facebook;

use 5.008_001;
use strict;
use warnings;

use utf8;
use open ':utf8', ':std';
use Getopt::Long;
use File::Basename;
use LWP::UserAgent;
use HTTP::Cookies;
use HTTP::Request::Common;
use JSON;
use Data::Dumper;

sub new {
	my $class = shift;
	bless { @_ }, $class;
}

sub post {
	my($self, $type, $id, $vars) = @_;

	my $ua = $self->{ua};
	my $token = $self->{token};

	my $json = new JSON;
	$json->utf8(1);
	my $req = POST "https://graph.facebook.com/$id/$type",
		    Content_Type => 'form-data',
		    Content      => [ access_token => $token,
				      @$vars
				    ];
	my $resp = $ua->request($req);
	if(!$resp->is_success) {
		my $obj = $json->decode($resp->content);
		die "Bad request: Failed to issue $type request: ".$obj->{error}->{type} . ".\n" . $obj->{error}->{message}
		    if defined($obj->{error});
		die "Bad request: $type request failed: " . $resp->status_line . ".\n" . $resp->content;
		return;
	}
	my $obj = $json->decode($resp->content);
	die "Failed to issue $type request: ".$obj->{error}->{type} . ".\n" . $obj->{error}->{message}
	    if defined($obj->{error});

	return $obj;
}

1;
