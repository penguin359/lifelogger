#!/usr/bin/perl
#
# Copyright (c) 2009-2013, Loren M. Lang
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


package LifeLogger::Controller::OAuth;
use Moose;
use namespace::autoclean;

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
use Common;
use Net::Flickr;
use CGI;
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON;
use XML::LibXML;
use Data::Dumper;

BEGIN { extends 'Catalyst::Controller'; }

sub handleLatitude {
	my($c, $cgi, $resp) = @_;

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
	my($c, $cgi, $resp) = @_;

	print "Content-Type: text/plain; charset=UTF-8\r\n\r\n";
	print $resp->status_line . "\n\n", $resp->content;
}

sub handleFlickr {
	my($c, $cgi, $resp) = @_;

	my $parser = new XML::LibXML;
	my $doc = $parser->parse_string($resp->content);
	my @stat = $doc->findnodes('/rsp/@stat');
	if(@stat < 1) {
		errorResponse($c, "Failed to parse Flickr API response");
		return;
	}
	#print "Stat: '".$stat[0]->nodeValue."'\n";
	if($stat[0]->nodeValue ne "ok") {
		my @error = $doc->findnodes('/rsp/err/@msg');
		my $error = $error[0]->nodeValue if @error >= 1;
		errorResponse($c, "Error in Flickr API response", $error);
		return;
	}
	print "Content-Type: text/plain; charset=UTF-8\r\n\r\n";
	print $doc->toString(0);
}

sub handleTwitter {
	my($c, $cgi, $resp) = @_;

	print "Content-Type: text/plain; charset=UTF-8\r\n\r\n";
	my $doc = XML::LibXML->new->parse_string($resp->content);
	my @nodes = $doc->findnodes('/statuses/status/text/text()');
	#print $resp->status_line . "\n\n", $resp->content;
	print "Found " . scalar @nodes, " tweets\n";
	print "Last tweet: " . $nodes[0]->nodeValue . "\n";
}

sub handleFourSquare {
	my($c, $cgi, $resp) = @_;

	$c->response->body("FourSquare!!!".$resp->content);
	return;
	print "Content-Type: text/plain; charset=UTF-8\r\n\r\n";
	my $doc = XML::LibXML->new->parse_string($resp->content);
	my @nodes = $doc->findnodes('/checkins/checkin/display/text()');
	#print $resp->status_line . "\n\n", $resp->content;
	print "Found " . scalar @nodes, " check-ins\n";
	print "Last check-in: " . $nodes[0]->nodeValue . "\n";
}

my $apps = {
	facebook => {
		version => '2.0',
		authorize => 'https://graph.facebook.com/oauth/authorize',
		authorizeParams => {
			client_id => '101285466606087',
			scope => 'user_photos,user_videos,publish_stream,offline_access',
		},
		api => '',
		tokenParam => 'access_token',
		handler => \&handleXML,
	},
	flickr => {
		version => 'flickr',
		authorizeParams => {
			api_key => 'c9d5f00dcc25ab2150e776947a9e3e35',
			perms => 'read',
		},
		access => 'http://flickr.com/services/rest/?method=flickr.auth.getToken',
		accessParams => {
			api_key => 'c9d5f00dcc25ab2150e776947a9e3e35',
		},
		api => 'http://flickr.com/services/rest/?method=flickr.contacts.getList',
		#api => 'http://flickr.com/services/rest/?method=flickr.people.getInfo',
		apiParams => {
			api_key => 'c9d5f00dcc25ab2150e776947a9e3e35',
		},
		doubleRedirect => 1,
		handler => \&handleFlickr,
	},
	foursquare => {
		version => '2.0',
                authorize => 'https://foursquare.com/oauth2/authenticate',
		authorizeParams => {
			client_id => '5JO5GTM4ZLRSE53RC5TRZN4OGFYJI3PV1BH24Q5OCFQHTL3R',
			response_type => 'code',
		},
		api => 'https://api.foursquare.com/v2/users/self/checkins',
		#apiParams => {
		#	l => 1,
		#},
		tokenParam => 'oauth_token',
		handler => \&handleFourSquare,
		#handler => \&handleXML,
	},
	latitude => {
		version => '1.0a',
		request => 'https://www.google.com/accounts/OAuthGetRequestToken',
		authorize => 'https://www.google.com/latitude/apps/OAuthAuthorizeToken?domain=www.north-winds.org&location=all&granularity=best',
		authorizeParams => {
		},
		access => 'https://www.google.com/accounts/OAuthGetAccessToken',
		#api => 'https://www.googleapis.com/latitude/v1/currentLocation',
		api => 'https://www.googleapis.com/latitude/v1/location',
		requestParams => {
			scope => 'https://www.googleapis.com/auth/latitude',
		},
		handler => \&handleLatitude,
	},
	twitter => {
		version => '1.0a',
		request => 'https://api.twitter.com/oauth/request_token',
		authorize => 'https://api.twitter.com/oauth/authorize',
		authorizeParams => {
		},
		access => 'https://api.twitter.com/oauth/access_token',
		#api => 'https://api.twitter.com/1/users/search.xml?q=DWAnimation',
		api => 'https://api.twitter.com/1/statuses/home_timeline.xml',
		#handler => \&handleTwitter,
		handler => \&handleXML,
	},
	statusnet => {
		version => '1.0',
		request => 'http://status.north-winds.org/api/oauth/request_token',
		authorize => 'http://status.north-winds.org/api/oauth/authorize',
		authorizeParams => {
		},
		access => 'http://status.north-winds.org/api/oauth/access_token',
		api => 'https://status.north-winds.org/api/statuses/home_timeline.xml',
		doubleRedirect => 1,
		#handler => \&handleTwitter,
		handler => \&handleXML,
	},
	identica => {
		version => '1.0a',
		request => 'https://identi.ca/api/oauth/request_token',
		authorize => 'https://identi.ca/api/oauth/authorize',
		authorizeParams => {
		},
		access => 'https://identi.ca/api/oauth/access_token',
		api => 'https://identi.ca/api/statuses/home_timeline.xml',
		doubleRedirect => 1,
		handler => \&handleTwitter,
		#handler => \&handleXML,
	},
};

sub requestSign {
	my($c, $oauthData, $ua) = @_;

	my $json = new JSON;
	$json->utf8(1);
	#print $cgi->p($json->encode($oauthData));
	#print $cgi->p(Dumper(POST "http://praeluceo.net/~loren/oauth-sign.pl", Content_Type => "application/json", Content => $json->encode($oauthData)));
	#my $resp = $ua->request(POST "http://praeluceo.net/~loren/oauth-sign.pl", Content_Type => "application/json", Content => $json->encode($oauthData));
	my $resp = $ua->request(POST "https://www.north-winds.org/photocatalog/cgi/oauth-sign.pl", Content_Type => "application/json", Content => $json->encode($oauthData));
	if(!$resp->is_success) {
		errorResponse($c, "Failure to request OAuth signature", "R: ". $resp->status_line. ", ". $resp->content, 500);
	}

	return $resp->content;
}

sub errorResponse {
        my($c, $error, $detail, $code) = @_;

        $code = 400 if !defined($code);
	$c->response->status($code);
        $c->response->header("Content-Type" => "text/plain; charset=UTF-8");
	my $msg = "ERROR: $error";
        $msg .= ": $detail" if defined $detail;
        $msg .= "\n";
        $c->response->body($msg);
}

=head1 NAME

LifeLogger::Controller::OAuth - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index

=cut

sub index :Local :Args(0) {
    my ( $self2, $c ) = @_;

    if(!$c->request->param() || !$c->request->param('source')) {
	    errorResponse($c, "No source specified");
	    return;
    }

    my $self = init();
    $self->{debug} = $c->request->param('debug');
    print "Content-Type: text/plain; charset=UTF-8\r\n\r\n" if $self->{debug};
    #die $self->{usage} if @ARGV > 0;
    lockKml($self);

    my $source;
    eval {
	    $source = findSource($self, undef, $c->request->param('source'));
    };
    if($@) {
	    errorResponse($c, "Failed to locate source", $@);
	    return;
    }
    my $app = $source->{type};
    my $appL = lc $app;

    my $a = $apps->{$appL};
    
    if(!defined($a)) {
	errorResponse($c, "Unknown application $app");
	return;
    }

    my $ua = new LWP::UserAgent;

    my($token, $tokenSecret) = ($source->{token}, $source->{tokenSecret});
    $token = "" if !defined($token);
    $tokenSecret = "" if !defined($tokenSecret);
    if($c->request->param('refresh')) {
	    $token = "";
	    $tokenSecret = "";
    }

    my $saveTokens = 0;

    if($a->{version} eq "2.0" && ($c->request->param('access_token') || $c->request->param('error'))) {
	    $token = "dummy";
	    $tokenSecret = $c->request->param('access_token');
	    my $error = $c->request->param('error');
	    my $errorDescription = $c->request->param('error_description');
	    if($error) {
		    errorResponse($c, "OAuth Authorization: ", $error . ", " . $errorDescription);
		    return;
	    }
	    #my $error = $c->request->param('error_reason');
	    $saveTokens = 1;
    }

    if($a->{version} eq "flickr" && $c->request->param('frob')) {
	    my $url = addCgiParam($a->{access}, { frob => $c->request->param('frob'), %{$a->{accessParams}} });
	    my $resp = $ua->request(GET signFlickr($url));
	    if(!$resp->is_success) {
		    print "Content-Type: text/plain; charset=UTF-8\r\n\r\n";
		    print "Failed to get Flickr token: " . $resp->status_line . ", " . $resp->content;
		    exit 0;
		    #errorResponse($c, "Failed to get token", $resp->status_line . ", " . $resp->content);
	    }
	    #print "Content-Type: text/plain; charset=UTF-8\r\n\r\n";
	    #print $resp->content;
	    my $parser = new XML::LibXML;
	    my $doc = $parser->parse_string($resp->content);
	    my @stat = $doc->findnodes('/rsp/@stat');
	    if(@stat < 1) {
		errorResponse($c, "Failed to parse Flickr API response");
		return;
	    }
	    #print "Stat: '".$stat[0]->nodeValue."'\n";
	    if($stat[0]->nodeValue ne "ok") {
		    my @error = $doc->findnodes('/rsp/err/@msg');
		    my $error = $error[0]->nodeValue if @error >= 1;
		    errorResponse($c, "Error in Flickr API response", $error);
		    return;
	    }
	    #print $doc->toString(0);
	    my @nodes = $doc->findnodes('/rsp/auth/token/text()');
	    #print Dumper(\@nodes);
	    #print "Node: '", $nodes[0]->nodeValue, "'\n";
    
	    $token = "dummy";
	    $tokenSecret = $nodes[0]->nodeValue;
	    $saveTokens = 1;
    }

    # This handles Step 4 in OAuth 1.0a
    #if($token eq "" && $c->request->param('oauth_token')) {
    if($c->request->param('redirected') && $c->request->param('oauth_token')) {
	    $token = $c->request->param('oauth_token');
	    my $verifier = $c->request->param('oauth_verifier');
	    my $oauthData = {
		    protocol => "oauth 1.0a",
		    app => $app,
		    type => "authorize",
		    params => {
			    token => $token,
			    token_secret => $tokenSecret,
			    request_url => $a->{access},
			    request_method => 'GET',
		    },
	    };
	    $oauthData->{params}->{verifier} = $verifier if $a->{version} eq "1.0a";

	    my $resp = $ua->request(GET $a->{access}, Authorization => requestSign($c, $oauthData, $ua));

	    if(!$resp->is_success) {
		    print "Content-Type: text/plain; charset=UTF-8\r\n\r\n";
		    print "Failed to get token: " . $resp->status_line . ", " . $resp->content;
		    exit 0;
		    errorResponse($c, "Failed to get token", $resp->status_line . ", " . $resp->content);
		    return;
	    }

	    my $tokenCgi = new CGI($resp->content);
	    $token = $tokenCgi->param('oauth_token');
	    $tokenSecret = $tokenCgi->param('oauth_token_secret');

	    $saveTokens = 1;
    }

    if($saveTokens) {
	    my $xc = loadXPath($self);
	    my $parser = new XML::LibXML;
	    my $doc = $parser->parse_file($self->{configFile});
	    my $sourceNode = getNode($xc, $doc, '/settings/sources/source[id/text() = "'.$source->{id}.'"]');
	    if(!defined $sourceNode) {
		errorResponse($c, "Failed to locate source", "in $self->{configFile}");
		return;
	    }
	    my $textNode = $doc->createTextNode($token);

	    my $tokenNode = getNode($xc, $sourceNode, 'token');
	    if(defined($tokenNode)) {
		    if(defined($tokenNode->firstChild)) {
			    $tokenNode->replaceChild($textNode,
						     $tokenNode->firstChild);
		    } else {
			    $tokenNode->appendChild($textNode);
		    }
	    } else {
		    $tokenNode = $doc->createElement('token');
		    $tokenNode->appendChild($textNode);
		    $sourceNode->appendTextNode("    ");
		    $sourceNode->appendChild($tokenNode);
		    $sourceNode->appendTextNode("\n\t");
	    }

	    $textNode = $doc->createTextNode($tokenSecret);
	    my $tokenSecretNode = getNode($xc, $sourceNode, 'tokenSecret');
	    if(defined($tokenSecretNode)) {
		    if(defined($tokenSecretNode->firstChild)) {
			    $tokenSecretNode->replaceChild($textNode,
						     $tokenSecretNode->firstChild);
		    } else {
			    $tokenSecretNode->appendChild($textNode);
		    }
	    } else {
		    $tokenSecretNode = $doc->createElement('tokenSecret');
		    $tokenSecretNode->appendChild($textNode);
		    $sourceNode->appendTextNode("    ");
		    $sourceNode->appendChild($tokenSecretNode);
		    $sourceNode->appendTextNode("\n\t");
	    }

	    $doc->toFile($self->{configFile}, 0);

	    my $redirectURL = "http";
	    $redirectURL .= "s" if defined $ENV{HTTPS} && lc $ENV{HTTPS} eq "on";
	    $redirectURL .= "://$ENV{SERVER_NAME}$ENV{SCRIPT_NAME}";
	    $redirectURL = addCgiParam($redirectURL, { app => $app, source => $source->{id}, redirected => 1, debug => $self->{debug} });
	    #print "Location: $redirectURL\r\n\r\n";
	    $c->response->redirect($redirectURL);
	    return;
    }

    if($token ne "") {
	    my $req;
	    if($a->{version} eq "2.0") {
		    $req = GET addCgiParam($a->{api}, { $a->{tokenParam} => $tokenSecret });
	    } elsif($a->{version} eq "flickr") {
		    my $url = addCgiParam($a->{api}, { auth_token => $tokenSecret, %{$a->{apiParams}} });
		    $req = GET signFlickr($url);
	    } else {
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

		    if(defined($a->{apiParams})) {
			    $oauthData->{params}->{request_method} = 'POST';
			    $oauthData->{params}->{extra_params} = $a->{apiParams};
			    $req = POST $a->{api}, Authorization => requestSign($c, $oauthData, $ua), Content => [ %{$a->{apiParams}} ];
		    } else {
			    $req = GET $a->{api}, Authorization => requestSign($c, $oauthData, $ua);
		    }
	    }
	    #print Dumper $req;
	    my $resp = $ua->request($req);

	    if(!$resp->is_success) {
		    errorResponse($c, "Failed to get $app", $resp->status_line . ", " . $resp->content);
		    #print $cgi->p("Failed to get $app: " . $resp->status_line . ", " . $resp->content);
		    return;
	    }
	    $a->{handler}($c, undef, $resp);
	    #print $cgi->p($resp->status_line . "\n"), $cgi->code($resp->content);
	    #print $cgi->end_html;

	    return;
    }

    #if(defined($c->request->param('query'))) {
    #	print "Content-Type: text/plain\r\n\r\n";
    #	print "Got me a frob: ".$c->request->param('query')."\n";
    #	exit 0;
    #}

    if($c->request->param('redirected')) {
	    errorResponse($c, "Failed to acquire token for source $source->{id}");
	    return;
    }

    my $redirectURL = "http";
    $redirectURL .= "s" if defined $ENV{HTTPS} && lc $ENV{HTTPS} eq "on";
    $redirectURL .= "://$ENV{SERVER_NAME}$ENV{SCRIPT_NAME}";
    #$redirectURL .= "://$ENV{SERVER_NAME}$ENV{SCRIPT_NAME}?app=$app";
    #$redirectURL =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
    #my $callbackURL = 'http://www.north-winds.org/photocatalog/cgi/redirect.pl?redirect_url='.$redirectURL;

    $redirectURL = addCgiParam($redirectURL, { app => $app, source => $source->{id}, redirected => 1, debug => $self->{debug} });
    my $callbackURL = addCgiParam('http://www.north-winds.org/photocatalog/cgi/redirect.pl', { redirect_url => $redirectURL, debug => $self->{debug} });

    #print "Content-Type: text/plain\r\n\r\n";

    # App uses OAuth 2.0
    if($a->{version} eq "2.0") {
	    $callbackURL = addCgiParam('http://www.north-winds.org/photocatalog/cgi/oauth2.pl', { redirect_url => $redirectURL, app => $app, debug => $self->{debug} });
	    my $url = addCgiParam($a->{authorize}, { redirect_uri => $callbackURL, %{$a->{authorizeParams}} });
	    sendRedirect($url, $callbackURL, $appL, $self, $c);
	    return;
    }

    # App uses FlickrAuth
    if($a->{version} eq "flickr") {
	    # FlickrAuth does not support a redirect URL unfortunately
	    my $url = addCgiParam($a->{authorize}, $a->{authorizeParams});
	    $url = signFlickr($url);
	    sendRedirect($url, $callbackURL, $appL, $self, $c);
	    return;
    }

    # Else assume App uses OAuth 1.0 or 1.0a
    my $oauthData = {
	    protocol => "oauth 1.0a",
	    app => $app,
	    type => "Request",
	    params => {
		    request_url => $a->{request},
		    request_method => 'GET',
	    },
    };

    $oauthData->{params}->{callback} = $callbackURL if $a->{version} eq "1.0a";
    $oauthData->{params}->{callback} = "http://www.north-winds.org/photocatalog/cgi/endRedirect.cgi" if $a->{version} eq "1.0a" && $a->{doubleRedirect};

    my $resp;
    if(defined($a->{requestParams})) {
	    $oauthData->{params}->{request_method} = 'POST';
	    $oauthData->{params}->{extra_params} = $a->{requestParams};
	    $resp = $ua->request(POST $a->{request}, Authorization => requestSign($c, $oauthData, $ua), Content => [ %{$a->{requestParams}} ]);
    } else {
	    $resp = $ua->request(GET $a->{request}, Authorization => requestSign($c, $oauthData, $ua));
    }
    #$c->response->body(Dumper($a));
    #return;

    if(!$resp->is_success) {
	    errorResponse($c, "Failed to request token", $resp->status_line . ", " . $resp->content);
	    return;
    }

    #print "Content-Type: text/plain\r\n\r\n";
    #print $resp->status_line, "\n", $resp->content, "\n";
    my $tokenCgi = new CGI($resp->content);
    $token = $tokenCgi->param('oauth_token');
    $tokenSecret = $tokenCgi->param('oauth_token_secret');
    my $callbackConfirmed = $tokenCgi->param('oauth_callback_confirmed');
    if($a->{version} eq "1.0a" && $callbackConfirmed ne "true") {
	    errorResponse($c, "Problem with callback", $resp->content, 500);
	    return;
    }

    my $xc = loadXPath($self);
    my $parser = new XML::LibXML;
    my $doc = $parser->parse_file($self->{configFile});
    my $sourceNode = getNode($xc, $doc, '/settings/sources/source[id/text() = "'.$source->{id}.'"]');
    errorResponse($c, "Failed to locate source", "in $self->{configFile}")
	if !defined $sourceNode;

    my $textNode = $doc->createTextNode($tokenSecret);
    my $tokenSecretNode = getNode($xc, $sourceNode, 'tokenSecret');
    if(defined($tokenSecretNode)) {
	    if(defined($tokenSecretNode->firstChild)) {
		    $tokenSecretNode->replaceChild($textNode,
					     $tokenSecretNode->firstChild);
	    } else {
		    $tokenSecretNode->appendChild($textNode);
	    }
    } else {
	    $tokenSecretNode = $doc->createElement('tokenSecret');
	    $tokenSecretNode->appendChild($textNode);
	    $sourceNode->appendTextNode("    ");
	    $sourceNode->appendChild($tokenSecretNode);
	    $sourceNode->appendTextNode("\n\t");
    }

    $doc->toFile($self->{configFile}, 0);

    #print "Location: https://www.google.com/accounts/OAuthAuthorizeToken?oauth_token=$token\r\n\r\n";
    #print "Location: https://www.google.com/latitude/apps/OAuthAuthorizeToken?oauth_token=$token&domain=www.north-winds.org&location=all&granularity=best\r\n\r\n";
    #print "Location: https://api.twitter.com/oauth/authorize?oauth_token=$token\r\n\r\n";
    my $params = { oauth_token => $token, %{$a->{authorizeParams}} };
    $params->{oauth_callback} = $callbackURL if $a->{version} ne "1.0a";
    $params->{oauth_callback} = "http://www.north-winds.org/photocatalog/cgi/endRedirect.cgi" if $a->{version} ne "1.0a" && $a->{doubleRedirect};
    my $authorizeURL = addCgiParam($a->{authorize}, $params);
    sendRedirect($authorizeURL, $callbackURL, $appL, $self, $c);

    $c->response->body('Matched LifeLogger::Controller::OAuth in OAuth.');
}


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
		next if !defined $params->{$_};
		$query .= $sep . escapeCgiParam($_) . "=" . escapeCgiParam($params->{$_});
		$sep = "&";
	}

	return $baseURL . $query . $fragment;
}

sub sendRedirect {
	my($url, $callbackURL, $appL, $self, $c) = @_;

	if($a->{doubleRedirect}) {
		$url = addCgiParam('http://www.north-winds.org/photocatalog/cgi/startRedirect.cgi', { service => $appL, redirect_url => $url, return_to => $callbackURL, debug => $self->{debug} });
	}
	#print "Location: $url\r\n\r\n";
	$c->response->redirect($url);
}



=head1 AUTHOR

Loren M. Lang,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
