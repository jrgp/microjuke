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

use constant apiKey => 'e40c04743632809d8176349ed86d2ade';
use constant secretKey => 'c91395a441ec56416536ab1e83a3c82a';

sub new {
	print "LastFM module loaded\n";
	my $self = $_[1];
	bless $self;
}

sub onSongStart {
	my $self = shift;
}

sub onSongEnd {
	my $self = shift;
	
	# Scrobble-worthy, as per http://www.last.fm/api/scrobbling#scrobble-requests ?
	if ($self->{play}->{gstate}->{duration} > 30) {
		$self->doScrobble();
	}

	print "Just listened to ".$self->{play}->{gstate}->{title}." at ".MicroJuke::GUI::seconds2minutes($self->{play}->{gstate}->{duration})." \n";
	
}

sub doAuth {
	my $self = shift;
}

sub doScrobble {
	my $self = shift;
}

1;
