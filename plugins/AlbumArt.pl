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

package MicroJuke::Plugin::AlbumArt;

use strict;
use warnings;

use LWP::UserAgent;
use XML::Simple;
use URI::Escape;
use File::Basename;
use Data::Dumper;


use threads;
use Thread::Queue; 

use constant apiKey => 'e40c04743632809d8176349ed86d2ade';
use constant secretKey => 'c91395a441ec56416536ab1e83a3c82a';

my $q = Thread::Queue->new;

threads->create(sub {
	while (my $item = $q->dequeue()) {
		my ($album, $artist) = @{$item};
		saveArtForAlbum($artist, $album);
	}
})->detach;

sub new {
	print "Album Art module loaded\n";

	my $path = MicroJuke::Conf::getVal('dir').'covers/';

	unless (-d $path) {
		mkdir $path || warn "Couldn't make folder for cover art! $!\n";
	}

	my $self = $_[1];
	bless $self;
}

########################
### Events we care about
#######################

sub onSongStart {
	my $self = shift;

	my $p = genLocalPath ($self->{play}->{gstate}->{artist}, $self->{play}->{gstate}->{album});

	return if -e $p;
	
	$q->enqueue([$self->{play}->{gstate}->{album}, $self->{play}->{gstate}->{artist}]);
}

########################
## Stuff we use internally to get stuff done
########################

# Called statically
sub genLocalPath {
	my ($artist, $album) = @_;

	return '' unless defined $artist && defined $album;

	$artist =~ s/\s+/-/g;
	$artist =~ s/\.+/_/g;
	$artist =~ s/\/+/_/g;
	$artist =~ s/\\+/_/g;
	$album =~ s/\s+/-/g;
	$album =~ s/\.+/_/g;
	$album =~ s/\/+/_/g;
	$album =~ s/\\+/_/g;

	# Extensionless
	my $path = MicroJuke::Conf::getVal('dir').'covers/'.$artist.'/'.$album;
	$path;
}

sub saveArtForAlbum {
	my ($artist, $album) = @_;
	my $local_path = genLocalPath($artist, $album);
	my $local_dir = dirname($local_path);
	return if -e $local_path;
	unless (-d $local_dir) {
		unless (mkdir $local_dir) {
			warn "Couldn't create folder for this artist\n";
			return 0;
		}
	}
	my $calls = [
		['album', $album],
		['api_key', apiKey],
		['artist', $artist],
		['method', 'album.getinfo'],
	];
	my @fields;
	for (@{$calls}) {
		push @fields, $_->[0].'='.uri_escape($_->[1]);
	}
	my $ua = LWP::UserAgent->new;
	$ua->agent("MicroJuke");
	my $req = HTTP::Request->new(GET => 'http://ws.audioscrobbler.com/2.0/?'.join('&', @fields));
	my $res = $ua->request($req);
	unless ($res->is_success) {
		warn "Couldn't get album info from Last.FM:". $res->status_line."\n";
		return 0;
	}
	my $ref = XMLin $res->content;
	my %sizes;
	for (@{$ref->{album}->{image}}) {
		$sizes{$_->{size}} = $_->{content};
	}
	my $url = undef;
	if (defined $sizes{extralarge}) {
		$url = $sizes{extralarge};
	}
	else {
		$url = shift(@{values(%sizes)});
	}
	return unless $url;
	my $ireq = HTTP::Request->new(GET => $url);
	my $ires = $ua->request($ireq);
	unless ($ires->is_success) {
		warn "Couldn't get album art from lastfm:". $ires->status_line."\n";
		return 0;
	}
	open H, ">$local_path";
	print H $ires->content;
	close H;
	1;
}

sub checkArt {
	my ($artist, $album) = @_;
	return -e genLocalPath($artist, $album);
}


1;
