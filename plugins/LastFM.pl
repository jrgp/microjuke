#!/usr/bin/perl

# This file is part of MicroJuke (c) 2012 Joe Gillotti.
# 
# MicroJuke is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# MicroJuke is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with MicroJuke.  If not, see <http://www.gnu.org/licenses/>.

package MicroJuke::Plugin::LastFM;

use strict;
use warnings;

use Digest::MD5 qw(md5_hex);
use LWP::UserAgent;
use XML::Simple;
use Data::Dumper;
use URI::Escape;

use constant apiKey => 'e40c04743632809d8176349ed86d2ade';
use constant secretKey => 'c91395a441ec56416536ab1e83a3c82a';

use Data::Dumper;

sub new {
	print "LastFM module loaded\n";
	my $self = $_[1];

	$self->{gui}->add_menu_item('_LastFM', {
		title => 'Authenticate as a different user',
		payload => {
			callback => sub {
				$self->beginAuth();
			}
		}
	});

	bless $self;
	$self->{state} = {
		authkey => $self->loadKey()
	};
	$self;
}

######################################
## Events we care about 
######################################

sub onSongStart {
	my $self = shift;
	Glib::Idle->add(sub {
			shift->updateNowPlaying();
			0;
		}, $self
	);
}

sub onSongEnd {
	my ($self) = shift;
	
	my $gstate = {};

	# Main gstate variable is changed almost immediately, so the next song
	# in the list will get scrobbled instead....let's make a stagnant copy of it
	for (keys %{$self->{play}->{gstate}}) {
		$gstate->{$_} = $self->{play}->{gstate}->{$_};
	}

	# Scrobble-worthy, as per http://www.last.fm/api/scrobbling#scrobble-requests ?
	if ($self->{play}->{gstate}->{duration} > 30) {
		Glib::Idle->add(sub {
				my ($self, $gstate) = @{$_[0]};
				$self->doScrobble($gstate);
				0;
			}, [$self, $gstate]
		);
	}

	print "Just listened to ".$self->{play}->{gstate}->{title}." at ".MicroJuke::GUI::seconds2minutes($self->{play}->{gstate}->{duration})." \n";
	
}

######################################
## Dummy guys referred to above
######################################

sub doScrobble {
	my ($self, $gstate) = @_;
	my $calls = [
		['album', $gstate->{album}],
		['api_key', apiKey],
		['artist', $gstate->{artist}],
		['method', 'track.scrobble'],
		['sk', $self->{state}->{authkey}],
		['timestamp', $gstate->{timeStarted}],
		['track', $gstate->{title}],
	];
	my @fields;
	for (@{$calls}) {
		push @fields, $_->[0].'='.uri_escape($_->[1]);
	}
	my $ua = LWP::UserAgent->new;
	$ua->agent("MicroJuke");
	my $req = HTTP::Request->new(POST => 'http://ws.audioscrobbler.com/2.0/');
	$req->content_type('application/x-www-form-urlencoded');
	$req->content(join('&', @fields).'&api_sig='.$self->signCalls($calls));
	my $res = $ua->request($req);
	my $ref = XMLin $res->content;
	if ($ref->{status} ne 'ok') {
		print Dumper($ref);
	}
}

sub updateNowPlaying {
	my $self = shift;
	my $calls = [
		['album', $self->{play}->{gstate}->{album}],
		['api_key', apiKey],
		['artist', $self->{play}->{gstate}->{artist}],
		['method', 'track.updateNowPlaying'],
		['sk', $self->{state}->{authkey}],
		['track', $self->{play}->{gstate}->{title}],
	];
	my @fields;
	for (@{$calls}) {
		push @fields, $_->[0].'='.uri_escape($_->[1]);
	}
	my $ua = LWP::UserAgent->new;
	$ua->agent("MicroJuke");
	my $req = HTTP::Request->new(POST => 'http://ws.audioscrobbler.com/2.0/');
	$req->content_type('application/x-www-form-urlencoded');
	$req->content(join('&', @fields).'&api_sig='.$self->signCalls($calls));
	my $res = $ua->request($req);
	my $ref = XMLin $res->content;
	if ($ref->{status} ne 'ok') {
		print Dumper($ref);
	}
}

######################################
## Store the last fm key
######################################

sub loadKey {
	my $self = shift;
	my $path = MicroJuke::Conf::getVal('dir').'lastfmkey';
	unless ( -e $path) {
		return '';
	}
	open my $h, "<$path";
	my $key = <$h>;
	close $h;
	$key;
}

sub saveKey {
	my ($self, $key) = @_;
	my $path = MicroJuke::Conf::getVal('dir').'lastfmkey';
	open my $h, ">$path";
	print $h $key;
	close $h;
}

######################################
## Last.FM protocol Authentication and API logic
######################################

sub signCalls {
	my ($self, $params) = @_;
	my $string = '';
	$string .= $_->[0].$_->[1] for (@{$params});
	$string .= secretKey;
	md5_hex $string;
}

sub beginAuth {
	my $self = shift;
	return unless $self->getAuthToken();
	$self->getWebServiceSession();
}

# Step 1
sub getAuthToken {
	my $self = shift;

	# Get auth token
	my $ua = LWP::UserAgent->new;
	$ua->agent("MicroJuke");
	my $req = HTTP::Request->new(GET => 'http://ws.audioscrobbler.com/2.0/?method=auth.gettoken&api_key='.apiKey);
	my $res = $ua->request($req);
	unless ($res->is_success) {
		print "Couldn't get auth token from LastFM:". $res->status_line."\n";
		return 0;
	}
	my $ref = XMLin $res->content;
	return 0 if !defined $ref->{status};
	if ($ref->{status} ne 'ok') {
		print "Failed getting auth token\n";
		return 0;
	}
	$self->{state}->{token} = $ref->{token};
	1;
}

# Step 2
sub passTheUser {
	my $self = shift;
	MicroJuke::GUI::openWebBrowser('http://www.last.fm/api/auth/?api_key='.apiKey.'&token='.$self->{state}->{token});
}

# Step 3 
sub getWebServiceSession {
	my $self = shift;
	my $sig = $self->signCalls([
		['api_key', apiKey],
		['method', 'auth.getSession'],
		['token', $self->{state}->{token}],
	]);
	my $ua = LWP::UserAgent->new;
	$ua->agent("MicroJuke");
	my $req = HTTP::Request->new(GET => 'http://ws.audioscrobbler.com/2.0/?method=auth.getSession&api_key='.apiKey.'&token='.$self->{state}->{token}.'&api_sig='.$sig);
	my $res = $ua->request($req);
	my $ref = XMLin $res->content;
	if ($ref->{status} ne 'ok') {
		if ($ref->{error}->{code} == 14) {
			$self->passTheUser;
			my $dialog = Gtk2::MessageDialog->new (
				$self->{gui}->{w}->{main},
				'destroy-with-parent',
				'question', 
				'ok-cancel', 
				"I am sending you to Last.FM's auth page. Click OK when finished, or Cancel if you no longer care."
			);
			my $resp = $dialog->run;

			# They clicked okay, hopefully after they clicked "Allow Access" in last.fm. Run this function again
			# and if they really did click "Allow Access" we'll be peachy clean
			if ($resp eq 'ok' ) {
				$dialog->destroy;
				$self->getWebServiceSession();
			}

			# User doesn't give a care about last.fm, apparently. Kill window and don't attempt to check
			# if we authed again.
			else {
				$dialog->destroy;
			}
			return;
		}
		else {
			print Dumper($ref);
			print "Error code: ".$ref->{error}->{code}."\n";
			return;
		}
	}

	$self->{state}->{authkey} = $ref->{session}->{key};
	$self->{state}->{username} = $ref->{session}->{name};

	$self->saveKey($ref->{session}->{key});
}

1;
