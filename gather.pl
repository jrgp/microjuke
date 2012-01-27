#!/usr/bin/perl

# Joe Gillotti - 1/26/2012 - BSD License

# install:
# sudo apt-get install libgstreamer-perl libgstreamer-interfaces-perl  libgtk2-perl libmp3-info-perl libogg-vorbis-header-perl libaudio-flac-header-perl
# -or-
# yum install perl-Gtk2 perl-MP3-Info perl-GStreamer

use strict;
use warnings;
use MP3::Info;
use Ogg::Vorbis::Header;
use Audio::FLAC::Header;
use Data::Dumper;
use File::Find;
use Storable qw(store_fd fd_retrieve);
use POSIX qw(floor);

sub seconds2minutes {
	my $secs = shift;
	my $mins = floor($secs / 60);
	$secs  = floor($secs % 60); 
	return "$mins:$secs";
}

my $action = shift;

die "Tell me what to do!\n" unless $action;

my @songs;

if ($action eq 'parse') {
	my $num_parsed = 0;
	find(\&parse, qw(/mnt/nfs/aero_more/Music/));
	sub parse {
		my ($artist, $album, $title, $time, $tracknum);
		return if (! -f $File::Find::name);
		if ($_ =~ m/\.mp3$/) {
			my $mp3 = new MP3::Info $File::Find::name;
			return unless defined $mp3->artist && defined $mp3->album && defined $mp3->title;
			return unless $mp3->artist ne '' && $mp3->album ne '' && $mp3->title ne '';
			($artist, $album, $title, $time, $tracknum) = (
				$mp3->artist, $mp3->album, $mp3->title, $mp3->time,
				defined $mp3->tracknum && $mp3->tracknum =~ /^(\d+)$/ ? $1 : 0
			);
			print "mp3 - $artist, $album, $title\n";
		}
		elsif ($_ =~ m/\.ogg$/) {
			my $ogg = Ogg::Vorbis::Header->new($File::Find::name);
			my $oggi = ();
			$oggi->{time} = seconds2minutes(floor($ogg->info->{length}));
			for my $key ($ogg->comment_tags) {
				if ($key eq 'ARTIST') {
					($oggi->{artist}) = ($ogg->comment($key));
				}
				elsif ($key eq 'ALBUM') {
					($oggi->{album}) = ($ogg->comment($key));
				}
				elsif ($key eq 'TITLE') {
					($oggi->{title}) = ($ogg->comment($key));
				}
				elsif ($key eq 'TRACKNUMBER') {
					($oggi->{tracknum}) = ($ogg->comment($key));
				}
			}
			for (keys %{$oggi}) {
				$oggi->{$_} =~ s/^\s+|\s+$//g ;
			}
			return unless defined $oggi->{artist} && defined $oggi->{album} && defined $oggi->{title};
			return unless $oggi->{artist} ne '' && $oggi->{album} ne '' && $oggi->{title} ne '';
			($artist, $album, $title, $time, $tracknum) = (
				$oggi->{artist}, $oggi->{album}, $oggi->{title}, $oggi->{time},
				defined $oggi->{tracknum} && $oggi->{tracknum} =~ /^(\d+)$/ ? $1 : 0
			);
			print "ogg - $artist, $album, $title\n";
		}
		elsif ($_ =~ m/\.flac$/) {
	#		my $flac = Audio::FLAC::Header->new($File::Find::name);
	#		my $info = $flac->info();
			return;
		}
		else {
			return;
		}

		push @songs, [$artist, $album, $tracknum, $title, $File::Find::name, $time];
		$num_parsed++;
	}
	open(H, '>songs.dat');
	store_fd \@songs, \*H;
	close H;
	print "Parsed $num_parsed MP3's\n";
}

elsif ($action eq 'sort') {
	
	open(H, '<songs.dat');
	my $songs = fd_retrieve(\*H);
	close H;

	@songs = @{$songs};
	@songs = grep ($_->[0] =~ /pink floyd/i, @songs ) ;
	@songs = grep ($_->[1] =~ /the wall/i, @songs ) ;
	print "$_->[0] - $_->[1] [$_->[2]] $_->[3] \n" for (@songs);
}

else {
	die "Unknown action\n";
}

