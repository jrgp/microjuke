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

package MicroJuke::Plugin::Client;

use strict;
use warnings;
use threads;
use threads::shared;
use IO::Socket::UNIX qw(SOCK_STREAM SOMAXCONN);

# Temporarily store the desired action from the remote control here
my $action :shared;
$action = '';

sub new {
	print "Client control module loaded\n";
	my $self = $_[1];
	bless $self;

	# Communicate with our remote controller via a UNIX domain socket.
	# As we're going to be listneing for connections, do so via a thread so we
	# don't block the interface and freeze the UI.
	#
	# Unfortunately this means we'll need to constanty poll the $action variable
	# to see if there's something new to be done to the player itself. This might be
	# resource intensive. 
	#
	threads->create(sub {
		
		my $socket_path = MicroJuke::Conf::getVal('dir').'.control_socket';

		# If the file already exists, kill it. Otherwise we may have a hard time 
		# listening for connections on it. 
		unlink($socket_path);

		# "Reckoner" is a badass Radiohead song, btw.
		my $reckoner = IO::Socket::UNIX->new(
			Type   => SOCK_STREAM,
			Local  => $socket_path,
			Listen => SOMAXCONN,
		);
		$reckoner->autoflush(1);

		unless ($reckoner) {
			warn "Couldn't make socket $!\n";
			return;
		}

		# Loop looking for connections from the remote control forever
		while (my $client = $reckoner->accept()) {
			chomp(my $line = <$client>);
			close $client;
			if ($line eq 'next') {
				 $action = 'n';
			}
			elsif ($line eq 'prev') {
				 $action = 'p';
			}
			elsif ($line eq 'playpause') {
				 $action = 'pp';
			}
		}
		
	}, $self)->detach;
	
	# Let's enjoy lots of race conditions. Check every 100 (dunno what time measurement that is)
	# to see if we have an action. If we do, do it, and reset it back to null
	Glib::Timeout->add (100, sub {

		my $self = shift;

		# Go to the next song
		if ($action eq 'n') {
			 print "Attempting to play next song..\n";
			 $self->{play}->playSong($self->{play}->{gstate}->{playing_what} + 1);
		}

		# Go to the last song
		elsif ($action eq 'p') {
			 print "Attempting to play last song..\n";
			 $self->{play}->playSong($self->{play}->{gstate}->{playing_what} - 1);
		}

		# Play or pause?
		elsif ($action eq 'pp') {
			 print "Attempting to toggle playback..\n";
			$self->{gui}->playPause();
		}

		# Whatever it is, keep it '' so we don't infinite loop one of the above actions
		$action = '';

		# We never want this to stop checking
		1;

	}, $self);

	# Probably a little pointless
	$self;
}

1;
