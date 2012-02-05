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

package MicroJuke::Plugin::Notifications;

use strict;
use warnings;

my $have_notify;

BEGIN {
	eval {
		require Gtk2::Notify;
		Gtk2::Notify->import();
	};
	if ($@) {
		$have_notify = 0;
	}
	else {
		$have_notify = 1;
	}

}

sub new {
	print "Notifications module loaded\n";
	my $self = $_[1];
	bless $self;

	if ($have_notify == 0) {
		warn "I don't have LibNotify. Notifications won't work. :P\n";
	}
	else {
		Gtk2::Notify->init('MicroJuke');
	}

	$self;
}

sub onSongStart {
	my $self = shift;
	return unless $have_notify;

	my $icon = '';

	# Attempt using our album art library. Using eval
	# because it might not be loaded. 
	eval {
		if (
			MicroJuke::Plugin::AlbumArt::checkArt($self->{play}->{gstate}->{artist},
				$self->{play}->{gstate}->{album})
			) {
			$icon = MicroJuke::Plugin::AlbumArt::genLocalPath(
				$self->{play}->{gstate}->{artist},
				$self->{play}->{gstate}->{album}
			);
		}
	};

	warn "Couldn't put album art in notif; album art module might be disabled.\n" if $@;

	eval {
		my $notif = Gtk2::Notify->new(
			"Now playing",
			$self->{play}->{gstate}->{title}." by ".$self->{play}->{gstate}->{artist},
			$icon
		);
		$notif->show;

	};

	warn "Couldn't prop notif: $! $@\n" if $@;
}

1;
