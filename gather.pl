#!/usr/bin/perl

use strict;
use warnings;
use MP3::Info;
use Data::Dumper;
use File::Find;
use Storable qw(store_fd fd_retrieve);
use POSIX qw(floor);
use IPC::Open2;

my ($ogg_method, $flac_method);

# These don't always exist
eval "
require Ogg::Vorbis::Header;
require Audio::FLAC::Header;
";

# If that eval fails, opt for using equivalent, but possibly slower, means
if ($@) {
	$ogg_method = -x '/usr/bin/vorbiscomment' ? 'vbc' : '';
	$flac_method = '';
}
else {
	use Ogg::Vorbis::Header;
	use Audio::FLAC::Header;
	$ogg_method = 'module';
	$flac_method = 'module';
}

BEGIN {$| = 1;}

use utf8;

my $dir = $ENV{HOME}.'/.microjuke/';

unless (-d $dir) {
	die "Error making data dir folder '$dir` \n" unless mkdir($dir);
}

unless (-w $dir) {
	die "Invalid permissions on data dir '$dir`;\n";
}

sub seconds2minutes {
	my $secs = shift;
	return sprintf('%d:%02d', floor($secs / 60), floor($secs % 60));
}

if (scalar @ARGV != 1) {
	print "USAGE: $0 pathtofolder\n";
	exit 1;
}

my ($folder) = @ARGV;

die "Folder '$folder` nonexistent\n" unless (-d $folder);

my @songs;

my $num_parsed = 0;
find(\&parse, ($folder));
sub parse {
	my ($artist, $album, $title, $time, $tracknum);
	return if (! -f $File::Find::name);
	if ($_ =~ m/\.mp3$/) {
		my $mp3 = new MP3::Info $File::Find::name;
		unless ($mp3) {
			print "Fucked up: ".$File::Find::name."\n";
			return;
		}
		return unless defined $mp3->artist && defined $mp3->album && defined $mp3->title;
		return unless $mp3->artist ne '' && $mp3->album ne '' && $mp3->title ne '';
		($artist, $album, $title, $time, $tracknum) = (
			$mp3->artist, $mp3->album, $mp3->title, $mp3->time,
			defined $mp3->tracknum && $mp3->tracknum =~ /^(\d+)$/ ? $1 : 0
		);
	}
	elsif ($_ =~ m/\.ogg$/) {
		my $oggi = ();
		if ($ogg_method eq 'vbc') {
			my $pid = open2(my $std, undef,  '/usr/bin/vorbiscomment', $File::Find::name);
			my $parsed = '';
			while (<$std>) {
				$parsed .= $_;
			}
			waitpid $pid, 0;
			my %fields = (
				TITLE => 'title',
				ARTIST => 'artist',
				TRACKNUMBER => 'tracknum',
				ALBUM => 'album',
			);
			for (split /\n/, $parsed) {
				chomp;
				if (m/^([A-Z]+)=([^\$]+)$/i && defined $fields{uc($1)}) {
					$oggi->{$fields{uc($1)}} = $2;
				}
			}
		}
		elsif ($ogg_method eq 'module') {
			my $ogg = Ogg::Vorbis::Header->new($File::Find::name);
			unless ($ogg) {
				print "Fucked up: ".$File::Find::name."\n";
				return;
			}
			$oggi->{time} = seconds2minutes(floor($ogg->info->{length}));
			my %fields = (
				TITLE => 'title',
				ARTIST => 'artist',
				TRACKNUMBER => 'tracknum',
				ALBUM => 'album',
			);
			for my $key ($ogg->comment_tags) {
				my $keyu = uc $key;
				if (defined $fields{$keyu}) {
					($oggi->{$fields{$keyu}}) = ($ogg->comment($key));
				}
			}
			for (keys %{$oggi}) {
				$oggi->{$_} =~ s/^\s+|\s+$//g ;
			}
		}
		return unless defined $oggi->{artist} && defined $oggi->{album} && defined $oggi->{title};
		return unless $oggi->{artist} ne '' && $oggi->{album} ne '' && $oggi->{title} ne '';
		($artist, $album, $title, $time, $tracknum) = (
			$oggi->{artist}, $oggi->{album}, $oggi->{title}, $oggi->{time},
			defined $oggi->{tracknum} && $oggi->{tracknum} =~ /^(\d+)$/ ? $1 : 0
		);
	}
	elsif ($_ =~ m/\.flac$/) {
		my $flaci = ();
		if ($flac_method eq 'module') {
			my $flac = Audio::FLAC::Header->new($File::Find::name);
			unless ($flac) {
				print "Fucked up: ".$File::Find::name."\n";
				return;
			}
			my $info = $flac->tags();
			$flaci->{time} = seconds2minutes(($flac->{trackLengthMinutes}*60) + $flac->{trackLengthSeconds});
			for my $key (qw(ARTIST ALBUM TITLE TRACKNUMBER)) {
				next unless defined $info->{$key};
				if ($key eq 'ARTIST') {
					$flaci->{artist} = $info->{$key};
				}
				elsif ($key eq 'ALBUM') {
					$flaci->{album} = $info->{$key};
				}
				elsif ($key eq 'TITLE') {
					$flaci->{title} = $info->{$key};
				}
				elsif ($key eq 'TRACKNUMBER') {
					$flaci->{tracknum} = $info->{$key};
				}
			}
		}
		return unless defined $flaci->{artist} && defined $flaci->{album} && defined $flaci->{title};
		return unless $flaci->{artist} ne '' && $flaci->{album} ne '' && $flaci->{title} ne '';
		($artist, $album, $title, $time, $tracknum) = (
			$flaci->{artist}, $flaci->{album}, $flaci->{title}, $flaci->{time},
			defined $flaci->{tracknum} && $flaci->{tracknum} =~ /^(\d+)$/ ? $1 : 0
		);
	}
	else {
		return;
	}

	print "Inserting $artist - $album - $title\n";

	# Attempt getting tracknumber from file prefix
	if (!$tracknum && m/^(\d+)[\.\-]? /) {
		$tracknum = $1;
	}

	push @songs, [$artist, $album, $tracknum, $title, $File::Find::name, $time];
	$num_parsed++;
}

open(H, '>'.$dir.'songs.dat');
store_fd \@songs, \*H;
close H;
print "Parsed $num_parsed Files\n";

