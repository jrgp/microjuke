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

use strict;
use warnings;
use IO::Socket::UNIX qw(SOCK_STREAM SOMAXCONN);

# Our options. Should be self explanatory as to their use
my %acts = (
	'--play-pause' => 'playpause',
	'--next' => 'next',
	'--previous' => 'prev',
	'--prev' => 'prev',
);

# Get whatever was passed
my $command = shift @ARGV;

# Nothing passed? Motherfucker. Show usage.
defined $command || usage();

# Something incorrect passed? Even worse. Motherfucker...
defined $acts{$command} || usage();

# Connect to socket created by running MicroJuke
my $client = IO::Socket::UNIX->new(
	Peer => $ENV{HOME}.'/.microjuke/.control_socket',
        Type => SOCK_STREAM )
or die "Couldn't connect to socket: $!\nTry actually running microjuke?\n";

# Send it our command
print $client $acts{$command}."\n";

# Flush that shit
$client->flush;

# Close connection
$client->close;

exit 0;

# When we get called retarded
sub usage {
	print STDERR "Usage: $0 [OPTION]\nOptions\n";
	for(keys %acts) {
		print STDERR "\t$_\n";
	}
	exit 1;
}
