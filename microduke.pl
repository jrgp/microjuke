#!/usr/bin/env perl

## Maintain settings and so on
package MicroJuke::Conf;

use warnings;
use strict;

my $dir = $ENV{HOME}.'/.microjuke/';

sub init {
	unless (-d $dir) {
		print "Error making data dir folder '$dir`: $! \n" unless mkdir($dir);
	}
}

sub getDir {
	$dir;
}

1;

## Maintain play state
package MicroJuke::Play;

use warnings;
use strict;

use GStreamer -init;
use Glib qw(TRUE FALSE);
use Storable qw(store_fd fd_retrieve);
use POSIX qw(floor);

sub new {
	my ($class) = @_;
	my $self = {};
	bless $self, $class;
	$self->{all_songs} = ();
	$self->{files} = {};
	$self->{gstate} = {
		playing => 0,
		playing_what => -1
	};
	$self->{loop} = Glib::MainLoop -> new();
	$self->{play} = GStreamer::ElementFactory -> make("playbin", "play");

	$self;
}

sub reloadSongList {
	my $self = shift;
	my $path = MicroJuke::Conf::getDir().'songs.dat';
	return unless -e $path && -r $path;
	open(H, '<'.$path);
	my $songs = fd_retrieve(\*H);
	close H;
	$self->{all_songs} = $songs;
	$self->{gui}->filterSongs('');

	$self->{gui}->{w}->{sb}->pop($self->{gui}->{w}->{sbID});
	$self->{gui}->{w}->{sb}->push($self->{gui}->{w}->{sbID}, scalar(@{$self->{all_songs}}).' songs');
}

sub getProgress {
	my $self = shift;
	my $gst = GStreamer::Query::Position->new ('time');
	my ($progress, $duration, $pfield, $dfield);
	if ($self->{play}->query($gst)) {
		($pfield, $progress) = $gst->position('time');
		$progress = MicroJuke::GUI::seconds2minutes(floor($progress / 1000000000));
	}

	my $dst = GStreamer::Query::Duration->new ('time');
	if ($self->{play}->query($dst)) {
		($dfield, $duration) = $dst->duration('time');
		$duration = MicroJuke::GUI::seconds2minutes(floor($duration / 1000000000));
	}

	return 0 if !$progress || !$duration;

	$self->{gui}->{w}->{np_timer}->set_text("$progress of $duration");

	return 1;
}

sub busCallBack {
	my ($self, $bus, $message) = @_;

	if ($message -> type & "error") {
		$self->{loop} -> quit();
	}

	elsif ($message -> type & "eos") {
		$self->{loop}->quit();
		$self->playSong($self->{gstate}->{playing_what} + 1);
	}

	return 1;
}

sub playSong {
	my ($self, $index) = @_;

	unless (defined $self->{files}->{$index}) {
		print "No songs?\n";
		return;
	}

	my $file = $self->{files}->{$index};

	$self->{gstate}->{playing_what} = $index;
      	$self->{gstate}->{playing} = 1;

	$self->{play}->set_state('null');

	my ($artist, $title, $album) = (
		$self->{gui}->{w}->{pl}->{data}[$index][2],
		$self->{gui}->{w}->{pl}->{data}[$index][1],
		$self->{gui}->{w}->{pl}->{data}[$index][3]
	);


	$self->{gui}->{w}->{npl}->set_text("[$artist] $title");

	$self->{play} -> set(uri => Glib::filename_to_uri($file, "localhost"));
	$self->{play} -> get_bus() -> add_watch(sub {
			my ($bus, $message, $self) = @_;
			$self->busCallBack($bus, $message);
		}, $self
	);
	$self->{play} -> set_state("playing");

	Glib::Source->remove ($self->{gui}->{w}->{periodic_time_dec}) if $self->{gui}->{w}->{periodic_time_dec};
	$self->{gui}->{w}->{periodic_time_dec} = Glib::Timeout->add (1000, sub{
		my $self = shift;
		$self->getProgress();
	}, $self);

	$self->{gui}->{w}->{main}->set_title("MicroJuke - [$artist] $title");
}

1;

## Keep track of the GUI
package MicroJuke::GUI;

use strict;
use warnings;

use Gtk2 qw(-init);
use Glib qw(TRUE FALSE);
use Gtk2::SimpleMenu;
use Gtk2::SimpleList;
use Data::Dumper;
use POSIX qw(floor);
use Data::Dumper;

sub new {
	my ($class, $play) = @_;
	my $self = {};
	bless $self, $class;
	$self->{play} = $play;
	$self->{play}->{gui} = $self;
	$self->init_gui();
	$self;
}

sub seconds2minutes {
	my $secs = shift;
	return sprintf('%d:%02d', floor($secs / 60), floor($secs % 60));
}

sub toolong {
	my $str = shift;
	return '' unless defined $str;
	return length($str) > 30 ? substr ($str, 0, 29).'..' : $str;
}

sub plActCallBack {
	my ($self, $widget, $event) = @_;
	my $p = $event;
	my ($index) = $p->get_indices;
	$self->{play}->playSong($index);
}

sub filterSongs {
	my ($self, $query) = @_;
	my @fsongs;

	if ($query eq '') {
		@fsongs = @{$self->{play}->{all_songs}};
		$self->{w}->{s_status}->set_text('');
	}
	else {
		$query = quotemeta($query);
		@fsongs =
		grep (
			$_->[0] =~ /$query/i ||
			$_->[1] =~ /$query/i ||
			$_->[3] =~ /$query/i 
		, @{$self->{play}->{all_songs}});
		my $nf = scalar @fsongs;
		my $ent = scalar @{$self->{play}->{all_songs}};
		$self->{w}->{s_status}->set_text($nf == 0 ? 'No matches' : "Showing $nf/$ent songs");
	}

	$self->{play}->{files} = {};
	@{$self->{w}->{pl}->{data}} = ();
	
	my $i = 0;
	for (@fsongs) {
		push @{$self->{w}->{pl}->{data}}, [
			toolong($_->[2]),
			toolong($_->[3]),
			toolong($_->[0]),
			toolong($_->[1]),
			$_->[5],
		];
		$self->{play}->{files}->{$i} = $_->[4];
		$i++;
	}
}

sub searchCallBack {
	my ($self, $widget, $event) = @_;
	my $query = $widget->get_text();
	$query  =~ s/^\s+|\s+$//g ;
	$self->filterSongs($query);
}

sub init_gui {
	my $self = shift;
	$self->{w} = ();
	$self->{w}->{main} = new Gtk2::Window 'toplevel';
	$self->{w}->{mv} = Gtk2::VBox->new;
	$self->{w}->{main}->add($self->{w}->{mv});

	my $menu_tree = [
		_File => {
			item_type => '<Branch>',
			children => [
				'_Parse Library' => {
					callback => sub{
						my ($sc, $state) = $self->{play}->{play}->get_state(4);
						if ($state ne 'null') {
							$self->{play}->{play}->set_state('null');
						} 
						Glib::Idle->add(sub {
								my $self = shift;
								$self->{play}->reloadSongList();
								0;
							}, $self
						);
					}
				},
				_Quit => {
					callback => sub{
						$self->die;
					},
					callback_action => 0,
				},
			]
		},
		_Playback => {
			item_type => '<Branch>',
			children => [
				'_Play\/Pause' => {
					callback => sub {
						my ($sc, $state) = $self->{play}->{play}->get_state(4);
						if ($state eq 'paused') {
							$self->{play}->{play}->set_state('playing');
						} 
						elsif ($state eq 'playing') {
							$self->{play}->{play}->set_state('paused');
						}
					},
				},
				'_Stop' => {
					callback => sub {
						$self->{play}->{play}->set_state('null');
						Glib::Source->remove ($self->{w}->{periodic_time_dec}) if $self->{w}->{periodic_time_dec};
						$self->{w}->{np_timer}->set_text('');
						$self->{w}->{npl}->set_text('Nothing playing');
						$self->{w}->{main}->set_title('MicroJuke');
					}
				},
				'_Next' => {
					callback => sub {
						$self->{play}->playSong($self->{play}->{gstate}->{playing_what} + 1);
					},
					accelerator => '<ctrl>N'
				},
				'_Previous' => {
					callback => sub {
						$self->{play}->playSong($self->{play}->{gstate}->{playing_what} - 1);
					}
				},
			]

		}
	];

	$self->{w}->{menu} = Gtk2::SimpleMenu->new(menu_tree => $menu_tree, default_callback => sub {}, user_data => 'user_data');

	$self->{w}->{menu}->get_widget('/File')->activate;

	$self->{w}->{pl} = Gtk2::SimpleList->new(
		'Track' => 'text',
		'Title' => 'text',
		'Artist' => 'text',
		'Album' => 'text',
		'Time' => 'text',
	);

	$self->{w}->{pl}->columns_autosize();

	map {$_->set_sizing ('autosize')} $self->{w}->{pl}->get_columns;
	map {$_->set_resizable (TRUE)} $self->{w}->{pl}->get_columns;
	map {$_->set_expand (FALSE)} $self->{w}->{pl}->get_columns;

	$self->{w}->{pl}->signal_connect('row-activated' => sub {
		my ($widget, $event, $col, $self) = @_;
		$self->plActCallBack($widget, $event);
		return 1;
	}, $self);

	# Player list
	$self->{w}->{plc} = Gtk2::ScrolledWindow->new (undef, undef);
	$self->{w}->{plc}->set_policy ('automatic', 'always');
	$self->{w}->{plc}->set_size_request (500,300);

	$self->{w}->{mv}->pack_start($self->{w}->{menu}->{widget}, 0, 0, 0);

	# Currently playing shit
	$self->{w}->{np} = Gtk2::HBox->new;
	$self->{w}->{mv}->pack_start($self->{w}->{np}, 0, 0, 0);
	$self->{w}->{npl} = Gtk2::Label->new('Nothing playing');
	$self->{w}->{np}->pack_start($self->{w}->{npl}, 0, 0, 1);
	$self->{w}->{np_timer} = Gtk2::Label->new();
	$self->{w}->{np}->pack_end($self->{w}->{np_timer}, 0, 0, 1);

	# Search
	$self->{w}->{search} = Gtk2::HBox->new;
	$self->{w}->{mv}->pack_start($self->{w}->{search}, 0, 0, 0);

	$self->{w}->{s_label} = Gtk2::Label->new('Filter: ');
	$self->{w}->{search}->pack_start($self->{w}->{s_label}, 0, 0, 1);

	$self->{w}->{s_entry} = Gtk2::Entry->new();
	$self->{w}->{search}->pack_start($self->{w}->{s_entry}, 0, 0, 0);

	$self->{w}->{s_status} = Gtk2::Label->new();
	$self->{w}->{search}->pack_start($self->{w}->{s_status}, 0, 0, 1);

	$self->{w}->{s_entry}->signal_connect('key-release-event', sub {
		my ($widget, $event, $self) = @_;
		$self->searchCallBack($widget, $event);
		return 0;
	}, $self);

	# Add player list
	$self->{w}->{plc}->add($self->{w}->{pl});
	$self->{w}->{mv}->add($self->{w}->{plc});

	# Status bar
	$self->{w}->{sb} = Gtk2::Statusbar->new();
	$self->{w}->{sbID} = $self->{w}->{sb}->get_context_id('se');
	$self->{w}->{sb}->push($self->{w}->{sbID}, '');
	$self->{w}->{mv}->pack_end($self->{w}->{sb}, 0, 0, 0);

	# Finalize
	$self->{w}->{main}->show_all;
	$self->{w}->{main}->set_title('MicroJuke');

	# Load intiial song list
	Glib::Idle->add(
		sub{
			my $self = shift;
			$self->{play}->reloadSongList(shift);
			0;
		},
		$self
	);

	# Prepare for dying like a twat
	$self->{w}->{main}->signal_connect(delete_event => sub{
		$self->die;
	}, $self);

	Gtk2->main;
}

sub die {
	my $self = shift;
	$self->{play}->{play}->set_state('null');
	Glib::Source->remove ($self->{w}->{periodic_time_dec}) if $self->{w}->{periodic_time_dec};
	Gtk2->main_quit;
}

1;

## Start us up
package main;

use warnings;
use strict;

MicroJuke::Conf::init();

my $play = MicroJuke::Play->new;
my $gui = MicroJuke::GUI->new($play);

1;
