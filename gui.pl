#!/usr/bin/env perl

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

my $w = ();

my $files = {};

my $gstate = {
	playing => 0,
	playing_what => -1
};

my $loop = Glib::MainLoop -> new();
my $play = GStreamer::ElementFactory -> make("playbin", "play");

sub my_bus_callback {
	my ($bus, $message, $loop) = @_;

	if ($message -> type & "error") {
		warn $message -> error;
		$loop -> quit();
	}

	elsif ($message -> type & "eos") {
		$loop -> quit();
		print "Gonna try next song\n";
		playSong($gstate->{playing_what} + 1);
	}
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

	#my ($suc, $state) = $play->get_state(4);
	#if ($state eq 'playing') {
		$play->set_state('null');
	#}

	my ($artist, $title, $album) = (
		$w->{pl}->{data}[$index][2],
		$w->{pl}->{data}[$index][1],
		$w->{pl}->{data}[$index][3]
	);

	$w->{sb}->pop($w->{sbID});
	$w->{sb}->push($w->{sbID}, "[$artist] $title");

	$play -> set(uri => Glib::filename_to_uri($file, "localhost"));
	$play -> get_bus() -> add_watch(\&my_bus_callback, $loop);
	$play -> set_state("playing");
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

$w->{plc} = Gtk2::ScrolledWindow->new (undef, undef);
$w->{plc}->set_policy ('automatic', 'always');
$w->{plc}->set_size_request (500,300);

$w->{mv}->pack_start($w->{menu}->{widget}, 0, 0, 0);
$w->{plc}->add($w->{pl});
$w->{mv}->add($w->{plc});

$w->{sb} = Gtk2::Statusbar->new();
$w->{sbID} = $w->{sb}->get_context_id('se');
$w->{sb}->push($w->{sbID}, 'Nothing playing.');
$w->{mv}->pack_end($w->{sb}, 0, 0, 0);

$w->{sbl} = Gtk2::Label->new('Nothing playing.');
$w->{sbl}->set_justify('center');
#$w->{sb}->pack_start($w->{sbl}, 0, 0, 0);

$w->{main}->show_all;

sub toolong {
	my $str = shift;
	return '' unless defined $str;
	return length($str) > 30 ? substr ($str, 0, 29).'..' : $str;
}

sub reloadSongList {
	my $w = shift;
	open(H, '<songs.dat');
	my $songs = fd_retrieve(\*H);
	close H;

	$files = {};
	@{$w->{pl}->{data}} = ();
	
	my @songs = @{$songs};
	#@songs = grep ($_->[0] =~ /live/i, @songs ) ;
	#@songs = grep ($_->[1] =~ /copper/i, @songs ) ;
	my $i = 0;
	for (@songs) {
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


Glib::Idle->add(
	sub{
		reloadSongList(shift);
		0;
	},
	$w
);

Gtk2->main;
