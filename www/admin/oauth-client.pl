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

use lib qw(
	/home/sttng359/local-i386/lib/perl/5.8.8
	/home/sttng359/local-i386/lib/perl/5.8.8/auto
	/home/sttng359/local-i386/lib/perl/5.8
	/home/sttng359/local-i386/lib/perl/5.8/auto
	/home/sttng359/local-i386/share/perl/5.8
	/home/sttng359/local-i386/share/perl/5.8.8
	/home/sttng359/public_html/XML-DOM-1.44/blib/lib
	/home/sttng359/public_html/libwww-perl-5.837/blib/lib
);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use Net::Flickr;
use CGI;
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON;
use XML::LibXML;
use Data::Dumper;

sub handleLatitude {
	my($cgi, $resp) = @_;

	#print "Content-Type: text/plain\r\n\r\n";
	print $cgi->header, $cgi->start_html(-Title => 'Google Latitude Location', -encoding => 'utf-8');

	my $obj = decode_json $resp->content;
	my $timestamp = $obj->{data}->{timestampMs};
	my $latitude = $obj->{data}->{latitude};
	my $longitude = $obj->{data}->{longitude};
	$timestamp = 0 if !defined $timestamp;
	$latitude = 0 if !defined $latitude;
	$longitude = 0 if !defined $longitude;
	$timestamp /= 1000;

	if($latitude == 0 && $longitude == 0) {
		print $cgi->p("Google Latitude doesn't know where you are.");
		#print $resp->content, "\n";
		print $cgi->p(Dumper($obj));
	} else {
		print $cgi->p("[ $latitude, $longitude ] @ $timestamp");
		print "<p><a href=\"http://maps.google.com/?q=$latitude,$longitude\">View on Google Maps</a></p>\n";
	}
	print $cgi->end_html;
}

sub handleXML {
	my($cgi, $resp) = @_;

	print "Content-Type: text/plain\r\n\r\n";
	print $resp->status_line . "\n\n", $resp->content;
}

sub handleTwitter {
	my($cgi, $resp) = @_;

	print "Content-Type: text/plain\r\n\r\n";
	my $doc = XML::LibXML->new->parse_string($resp->content);
	my @nodes = $doc->findnodes('/statuses/status/text/text()');
	#print $resp->status_line . "\n\n", $resp->content;
	print "Found " . scalar @nodes, " tweets\n";
	print "Last tweet: " . $nodes[0]->nodeValue . "\n";
}

sub handleFourSquare {
	my($cgi, $resp) = @_;

	print "Content-Type: text/plain\r\n\r\n";
	my $doc = XML::LibXML->new->parse_string($resp->content);
	my @nodes = $doc->findnodes('/checkins/checkin/display/text()');
	#print $resp->status_line . "\n\n", $resp->content;
	print "Found " . scalar @nodes, " check-ins\n";
	print "Last check-in: " . $nodes[0]->nodeValue . "\n";
}

my $apps = {
	foursquare => {
                request => 'http://foursquare.com/oauth/request_token',
                authorize => 'http://foursquare.com/oauth/authorize',
                access => 'http://foursquare.com/oauth/access_token',
		api => 'https://api.foursquare.com/v1/history',
		#apiParams => {
		#	l => 1,
		#},
		handler => \&handleFourSquare,
	},
	google => {
		request => 'https://www.google.com/accounts/OAuthGetRequestToken',
		authorize => 'https://www.google.com/latitude/apps/OAuthAuthorizeToken?domain=www.north-winds.org&location=all&granularity=best',
		access => 'https://www.google.com/accounts/OAuthGetAccessToken',
		#api => 'https://www.googleapis.com/latitude/v1/currentLocation',
		api => 'https://www.googleapis.com/latitude/v1/location',
		requestParams => {
			scope => 'https://www.googleapis.com/auth/latitude',
		},
		handler => \&handleLatitude,
	},
	twitter => {
		request => 'https://api.twitter.com/oauth/request_token',
		authorize => 'https://api.twitter.com/oauth/authorize',
		access => 'https://api.twitter.com/oauth/access_token',
		#api => 'https://api.twitter.com/1/users/search.xml?q=DWAnimation',
		api => 'https://api.twitter.com/1/statuses/home_timeline.xml',
		#handler => \&handleTwitter,
		handler => \&handleXML,
	},
	statusnet => {
		request => 'http://status.north-winds.org/api/oauth/request_token',
		authorize => 'http://status.north-winds.org/api/oauth/authorize',
		access => 'http://status.north-winds.org/api/oauth/access_token',
		api => 'https://status.north-winds.org/api/statuses/home_timeline.xml',
		#handler => \&handleTwitter,
		handler => \&handleXML,
	},
};

sub requestSign {
	my($oauthData, $cgi, $ua) = @_;

	my $json = new JSON;
	$json->utf8(1);
	#print $cgi->p($json->encode($oauthData));
	#print $cgi->p(Dumper(POST "http://praeluceo.net/~loren/oauth-sign.pl", Content_Type => "application/json", Content => $json->encode($oauthData)));
	#my $resp = $ua->request(POST "http://praeluceo.net/~loren/oauth-sign.pl", Content_Type => "application/json", Content => $json->encode($oauthData));
	my $resp = $ua->request(POST "https://www.north-winds.org/photocatalog/cgi/oauth-sign.pl", Content_Type => "application/json", Content => $json->encode($oauthData));
	if(!$resp->is_success) {
		errorResponse("Failure to request OAuth signature", "R: ". $resp->status_line. ", ". $resp->content, 500);
	}

	return $resp->content;
}

sub errorResponse {
        my($error, $detail, $code) = @_;

        $code = 400 if !defined($code);
        print "Status: $code $error\r\n";
        print "Content-Type: text/plain\r\n\r\n";
        print "ERROR: $error";
        print ": $detail" if defined $detail;
        print "\n";

        exit 0;
}

my $cgi = new CGI;
if(!$cgi->param() || !$cgi->param('app')) {
	errorResponse("No app specified");
}

my $app = $cgi->param('app');
my $appL = lc $app;

my $a = $apps->{$appL};

my $ua = new LWP::UserAgent;

my($token, $tokenSecret) = ("", "");

if(open(my $fd, "$appL-token")) {
	$token = <$fd>;
	$token = "" if !defined $token;
	chomp($token);
	close $fd;
}

if(open(my $fd, "$appL-secret")) {
	$tokenSecret = <$fd>;
	$tokenSecret = "" if !defined $tokenSecret;
	chomp($tokenSecret);
	close $fd;
}

if($appL eq "facebook" && ($cgi->param('code') || $cgi->param('error'))) {
	my $code = $cgi->param('code');
	my $source = $cgi->param('source');
	my $error = $cgi->param('error');
	my $errorDescription = $cgi->param('error_description');
	errorResponse("Facebook Authorization: ", $error . ", " . $errorDescription) if $error;
	#my $error = $cgi->param('error_reason');
	print "Content-Type: text/plain\r\n\r\n";
	print "Successfully added Facebook source $source with code $code!\n";
	exit 0;
}

# This handles Step 4 in OAuth 1.0a
if($token eq "" && $cgi->param('oauth_token')) {
	$token = $cgi->param('oauth_token');
	my $verifier = $cgi->param('oauth_verifier');
	my $oauthData = {
		protocol => "oauth 1.0a",
		app => $app,
		type => "authorize",
		params => {
			token => $token,
			token_secret => $tokenSecret,
			verifier => $verifier,
			request_url => $a->{access},
			request_method => 'GET',
		},
	};

	my $resp = $ua->request(GET $a->{access}, Authorization => requestSign($oauthData, $cgi, $ua));

	if(!$resp->is_success) {
		print "Content-Type: text/plain\r\n\r\n";
		print "Failed to get token: " . $resp->status_line . ", " . $resp->content;
		exit 0;
		errorResponse("Failed to get token", $resp->status_line . ", " . $resp->content);
	}

	my $tokenCgi = new CGI($resp->content);
	$token = $tokenCgi->param('oauth_token');
	$tokenSecret = $tokenCgi->param('oauth_token_secret');

	open(my $fd, ">$appL-token") or errorResponse("Failed to token");
	print $fd $token;
	close $fd;

	open($fd, ">$appL-secret") or errorResponse("Failed to secret");
	print $fd $tokenSecret;
	close $fd;
}

if($token ne "") {
	#print "Content-Type: text/plain\r\n\r\n";
	#print "Have token.\n";
	#exit 0;
	#print $cgi->header, $cgi->start_html(-Title => 'Google Latitude Location', -encoding => 'utf-8');
	my $oauthData = {
		protocol => "oauth 1.0a",
		app => $app,
		type => "Access",
		params => {
			token => $token,
			token_secret => $tokenSecret,
			request_url => $a->{api},
			request_method => 'GET',
		},
	};

	my $resp;
	if(defined($a->{apiParams})) {
		$oauthData->{params}->{request_method} = 'POST';
		$oauthData->{params}->{extra_params} = $a->{apiParams};
		$resp = $ua->request(POST $a->{api}, Authorization => requestSign($oauthData, $cgi, $ua), Content => [ %{$a->{apiParams}} ]);
	} else {
		$resp = $ua->request(GET $a->{api}, Authorization => requestSign($oauthData, $cgi, $ua));
	}

	if(!$resp->is_success) {
		errorResponse("Failed to get $app", $resp->status_line . ", " . $resp->content);
		#print $cgi->p("Failed to get $app: " . $resp->status_line . ", " . $resp->content);
		exit 0;
	}
	$a->{handler}($cgi, $resp);
	#print $cgi->p($resp->status_line . "\n"), $cgi->code($resp->content);
	#print $cgi->end_html;

	exit 0;
}

my $redirectURL = "http";
$redirectURL .= "s" if defined $ENV{HTTPS} && lc $ENV{HTTPS} eq "on";
$redirectURL .= "://$ENV{SERVER_NAME}$ENV{SCRIPT_NAME}";
#$redirectURL .= "://$ENV{SERVER_NAME}$ENV{SCRIPT_NAME}?app=$app";
#$redirectURL =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
#my $callbackURL = 'http://www.north-winds.org/photocatalog/cgi/redirect.pl?redirect_url='.$redirectURL;

# RFC3986
sub escapeReserved {
	my($param) = @_;

	# Escape all reserved characters
	$param =~ s/([^A-Za-z0-9\-._~])/sprintf("%%%02X", ord($1))/seg;
	return $param;
}

sub escapeCgiParam {
	my($param) = @_;

	# Escape all non-safe for query key/value
	$param =~ s/([^A-Za-z0-9\-._~!\$'()*,; :\/?@])/sprintf("%%%02X", ord($1))/seg;
	$param =~ s/ /+/g;
	return $param;
}

sub addCgiParam {
	my($baseURL, $params) = @_;

	my $fragment = "";
	if($baseURL =~ /^([^#]*)(#.*)$/) {
		$baseURL = $1;
		$fragment = $2;
	}
	my $sep = "?";
	$sep = "&" if $baseURL =~ /\?/;
	my $query = "";
	foreach(keys %$params) {
		$query .= $sep . escapeCgiParam($_) . "=" . escapeCgiParam($params->{$_});
		$sep = "&";
	}

	return $baseURL . $query . $fragment;
}

$redirectURL = addCgiParam($redirectURL, { app => $app, source => 8 });
my $callbackURL = addCgiParam('http://www.north-winds.org/photocatalog/cgi/redirect.pl', { redirect_url => $redirectURL });

if($appL eq "facebook") {
	my $url = addCgiParam('https://graph.facebook.com/oauth/authorize?client_id=101285466606087', { redirect_uri => $callbackURL, scope => 'user_photos,user_videos,publish_stream,offline_access' });
	print "Location: $url\r\n\r\n";
	exit 0;
}
if($appL eq "flickr") {
	my $url = addCgiParam('http://flickr.com/services/auth/', { api_key => 'c9d5f00dcc25ab2150e776947a9e3e35', perms => 'read' });
	$url = signFlickr($url);
	print "Location: $url\r\n\r\n";
	exit 0;
}

#print "Content-Type: text/plain\r\n\r\n";
my $oauthData = {
	protocol => "oauth 1.0a",
	app => $app,
	type => "Request",
	params => {
		request_url => $a->{request},
		request_method => 'GET',
		callback => 'http://www.north-winds.org/photocatalog/cgi/redirect.pl?redirect_url='.$redirectURL,
	},
};

my $resp;
if(defined($a->{requestParams})) {
	$oauthData->{params}->{request_method} = 'POST';
	$oauthData->{params}->{extra_params} = $a->{requestParams};
	$resp = $ua->request(POST $a->{request}, Authorization => requestSign($oauthData, $cgi, $ua), Content => [ %{$a->{requestParams}} ]);
} else {
	$resp = $ua->request(GET $a->{request}, Authorization => requestSign($oauthData, $cgi, $ua));
}

if(!$resp->is_success) {
	errorResponse("Failed to get token", $resp->status_line . ", " . $resp->content);
}
#print "Content-Type: text/plain\r\n\r\n";
#print $resp->status_line, "\n", $resp->content, "\n";
my $tokenCgi = new CGI($resp->content);
$token = $tokenCgi->param('oauth_token');
$tokenSecret = $tokenCgi->param('oauth_token_secret');
my $callbackConfirmed = $tokenCgi->param('oauth_callback_confirmed');
if($callbackConfirmed ne "true") {
	errorResponse("Problem with callback", $resp->content, 500);
}
open(my $fd, ">$appL-secret") or errorResponse("Failed to secret", undef, 500);
print $fd $tokenSecret;
close $fd;
$token =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
#print "Location: https://www.google.com/accounts/OAuthAuthorizeToken?oauth_token=$token\r\n\r\n";
#print "Location: https://www.google.com/latitude/apps/OAuthAuthorizeToken?oauth_token=$token&domain=www.north-winds.org&location=all&granularity=best\r\n\r\n";
#print "Location: https://api.twitter.com/oauth/authorize?oauth_token=$token\r\n\r\n";
my $sep = '?';
$sep = '&' if $a->{authorize} =~ /\?/;
print "Location: $a->{authorize}${sep}oauth_token=$token\r\n\r\n";
