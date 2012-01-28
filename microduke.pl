#!/usr/bin/env perl

BEGIN {$| = 1; }

# Joe Gillotti - 1/26/2012

use strict;
use warnings;

use Glib;
use Gtk2 qw(-init);
use Glib qw(TRUE FALSE);
use Gtk2::SimpleMenu;
use Gtk2::SimpleList;
use Data::Dumper;
use GStreamer -init;
use Storable qw(store_fd fd_retrieve);
use POSIX qw(floor mkfifo);
use Fcntl;
use Gtk2::Helper;

my $dir = $ENV{HOME}.'/.microjuke/';

unless (-d $dir) {
	die "Error making data dir folder '$dir` \n" unless mkdir($dir);
}

unless (-w $dir) {
	die "Invalid permissions on data dir '$dir`;\n";
}

my @global_songs;

my $w = ();

my $files = {};

my $gstate = {
	playing => 0,
	playing_what => -1
};

my $loop = Glib::MainLoop -> new();
my $play = GStreamer::ElementFactory -> make("playbin", "play");

sub seconds2minutes {
	my $secs = shift;
	return sprintf('%d:%02d', floor($secs / 60), floor($secs % 60));
}

sub getProgress {
	my $gst = GStreamer::Query::Position->new ('time');
	my ($progress, $duration, $pfield, $dfield);
	if ($play->query($gst)) {
		($pfield, $progress) = $gst->position('time');
		$progress = seconds2minutes(floor($progress / 1000000000));
	}

	my $dst = GStreamer::Query::Duration->new ('time');
	if ($play->query($dst)) {
		($dfield, $duration) = $dst->duration('time');
		$duration = seconds2minutes(floor($duration / 1000000000));
	}

	$w->{np_timer}->set_text("$progress of $duration");

	return 1;
}


sub my_bus_callback {
	my ($bus, $message, $loop) = @_;

	if ($message -> type & "error") {
		warn $message -> error;
		$loop -> quit();
	}

	elsif ($message->type & "application") {
		print "something\n";
	}

	elsif ($message -> type & "eos") {
		$loop -> quit();
		print "Gonna try next song\n";
		playSong($gstate->{playing_what} + 1);
	}


	return 1;
}

sub playSong {
	my $index = shift;

	unless (defined $files->{$index}) {
		print "No songs?\n";
		return;
	}

	my $file = $files->{$index};

	$gstate->{playing_what} = $index;
      	$gstate->{playing} = 1;

	$play->set_state('null');

	my ($artist, $title, $album) = (
		$w->{pl}->{data}[$index][2],
		$w->{pl}->{data}[$index][1],
		$w->{pl}->{data}[$index][3]
	);

	#$w->{sb}->pop($w->{sbID});
	#$w->{sb}->push($w->{sbID}, "[$artist] $title");

	$w->{npl}->set_text("[$artist] $title");

	$play -> set(uri => Glib::filename_to_uri($file, "localhost"));
	$play -> get_bus() -> add_watch(\&my_bus_callback, $loop);
	$play -> set_state("playing");

	Glib::Source->remove ($w->{periodic_time_dec}) if $w->{periodic_time_dec};
	$w->{periodic_time_dec} = Glib::Timeout->add (1000, sub{getProgress();});


	$w->{main}->set_title("MicroJuke - [$artist] $title");
}

sub pl_rl_callback {
	my ($widget, $event) = @_;
	my $p = $event;
	my ($index) = $p->get_indices;
	my $file = $files->{$index};

	playSong($index);
	
	return 0;
}

my $menu_tree = [
	_File => {
		item_type => '<Branch>',
		children => [
			'_Parse Library' => {
				callback => sub{
					my ($sc, $state) = $play->get_state(4);
					if ($state ne 'null') {
						$play->set_state('null');
					} 
					Glib::Idle->add(
						sub{
							reloadSongList(shift);
							0;
						},
						$w
					);
				}

			},
			_Quit => {
				callback => sub{Gtk2->main_quit;},
				callback_action => 0,
			},
		]
	},
	_Playback => {
		item_type => '<Branch>',
		children => [
			'_Play\/Pause' => {
				callback => sub {
					my ($sc, $state) = $play->get_state(4);
					if ($state eq 'paused') {
						$play->set_state('playing');
					} 
					elsif ($state eq 'playing') {
						$play->set_state('paused');
					}
				},
			},
			'_Stop' => {
				callback => sub {
					$play->set_state('null');
					Glib::Source->remove ($w->{periodic_time_dec}) if $w->{periodic_time_dec};
					$w->{np_timer}->set_text('');
					$w->{npl}->set_text('Nothing playing');
					$w->{main}->set_title('MicroJuke');
				}
			},
			'_Next' => {
				callback => sub {
					playSong($gstate->{playing_what} + 1);
				},
				accelerator => '<ctrl>N'
			},
			'_Previous' => {
				callback => sub {
					playSong($gstate->{playing_what} - 1);
				}
			},
		]

	}
];

$w->{main} = new Gtk2::Window 'toplevel';
$w->{main}->signal_connect(delete_event => sub{Gtk2->main_quit;});
$w->{mv} = Gtk2::VBox->new;
$w->{main}->add($w->{mv});

$w->{menu} = Gtk2::SimpleMenu->new(menu_tree => $menu_tree, default_callback => sub {}, user_data => 'user_data');

$w->{menu}->get_widget('/File')->activate;

$w->{pl} = Gtk2::SimpleList->new(
	'Track' => 'text',
	'Title' => 'text',
	'Artist' => 'text',
	'Album' => 'text',
	'Time' => 'text',
);

$w->{pl}->columns_autosize();

map { $_->set_sizing ('autosize') } $w->{pl}->get_columns;
map { $_->set_resizable (TRUE) } $w->{pl}->get_columns;
map { $_->set_expand (FALSE) } $w->{pl}->get_columns;


$w->{pl}->signal_connect('row-activated' => sub {
	my ($widget, $event) = @_;
	pl_rl_callback($widget, $event);
	return 1;
});

#$w->{pl}->signal_connect('button-press-event' => sub {
#	my ($widget, $event) = @_;
#	pl_rl_callback($widget, $event);
#	return 0;
#});

# Player list
$w->{plc} = Gtk2::ScrolledWindow->new (undef, undef);
$w->{plc}->set_policy ('automatic', 'always');
$w->{plc}->set_size_request (500,300);

$w->{mv}->pack_start($w->{menu}->{widget}, 0, 0, 0);

# Currently playing shit
$w->{np} = Gtk2::HBox->new;
$w->{mv}->pack_start($w->{np}, 0, 0, 0);
$w->{npl} = Gtk2::Label->new('Nothing playing');
$w->{np}->pack_start($w->{npl}, 0, 0, 1);
$w->{np_timer} = Gtk2::Label->new();
$w->{np}->pack_end($w->{np_timer}, 0, 0, 1);

# Search
$w->{search} = Gtk2::HBox->new;
$w->{mv}->pack_start($w->{search}, 0, 0, 0);

$w->{s_label} = Gtk2::Label->new('Filter: ');
$w->{search}->pack_start($w->{s_label}, 0, 0, 1);

$w->{s_entry} = Gtk2::Entry->new();
$w->{search}->pack_start($w->{s_entry}, 0, 0, 0);

$w->{s_status} = Gtk2::Label->new();
$w->{search}->pack_start($w->{s_status}, 0, 0, 1);

$w->{s_entry}->signal_connect('key-release-event', sub {
	my ($widget, $event) = @_;
	search_callback($widget, $event);
	return 0;
});


sub search_callback {
	my ($widget, $event) = @_;
	my $query = $widget->get_text();
	$query  =~ s/^\s+|\s+$//g ;
	filterSongs($query);
}

# Add player list
$w->{plc}->add($w->{pl});
$w->{mv}->add($w->{plc});

# Status bar
$w->{sb} = Gtk2::Statusbar->new();
$w->{sbID} = $w->{sb}->get_context_id('se');
$w->{sb}->push($w->{sbID}, '');
$w->{mv}->pack_end($w->{sb}, 0, 0, 0);


# Finalize
$w->{main}->show_all;

sub toolong {
	my $str = shift;
	return '' unless defined $str;
	return length($str) > 30 ? substr ($str, 0, 29).'..' : $str;
}

sub filterSongs {
	my $query = shift;

	my @fsongs;

	if ($query eq '') {
		@fsongs = @global_songs;
		$w->{s_status}->set_text('');
	}
	else {
		@fsongs =
		grep (
			$_->[0] =~ /$query/i ||
			$_->[1] =~ /$query/i ||
			$_->[3] =~ /$query/i 
		, @global_songs);
		my $nf = scalar @fsongs;
		my $ent = scalar @global_songs;
		$w->{s_status}->set_text($nf == 0 ? 'No matches' : "Showing $nf/$ent songs");
	}

	$files = {};
	@{$w->{pl}->{data}} = ();
	
	my $i = 0;
	for (@fsongs) {
		push @{$w->{pl}->{data}}, [
			toolong($_->[2]),
			toolong($_->[3]),
			toolong($_->[0]),
			toolong($_->[1]),
			$_->[5],
		];
		$files->{$i} = $_->[4];
		$i++;
	}
}

sub reloadSongList {
	my $w = shift;
	my $path = $dir.'songs.dat';
	return unless -e $path && -r $path;
	open(H, '<'.$path);
	my $songs = fd_retrieve(\*H);
	close H;
	@global_songs = @{$songs};
	filterSongs('');

	$w->{sb}->pop($w->{sbID});
	$w->{sb}->push($w->{sbID}, scalar(@global_songs).' songs');
}

Glib::Idle->add(
	sub{
		reloadSongList(shift);
		0;
	},
	$w
);

$w->{main}->set_title('MicroJuke');

Gtk2->main;
