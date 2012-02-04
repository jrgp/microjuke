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

## Misc convenient bullshit
package MicroJuke::misc;

use warnings;
use strict;

sub file_contents {
	my ($file, $default) = @_;
	$default = $default || '';
	-e $file || return $default;
	my $cont = '';
	open H, '<'.$file || return $default;
	for (<H>) {
		chomp;
		$cont .= "$_\n";
	}
	close H;
	chomp $cont;
	$cont;
}

## Maintain settings and so on
package MicroJuke::Conf;

use warnings;
use strict;

use File::Basename;
use Cwd;

use constant VERSION => '(SVN)';

my $home = Glib::get_home_dir() || $ENV{HOME};
my $dir = $home.'/.microjuke/';

my %settings = (
	pluginPath => [
		$home.'/.microjuke/plugins/',
		getcwd().'/plugins/',
		'/usr/share/microjuke/plugins/'
	],
	iconPath => [
		$home.'/.microjuke/icons/',
		getcwd().'/icons/'
	],
	dir => $dir
);

sub init {
	unless (-d $dir) {
		print "Error making data dir folder '$dir`: $! \n" unless mkdir($dir);
	}
	$settings{dir} = $dir;
}

sub getVal {
	my $key = shift;
	return defined $settings{$key} ? $settings{$key} : undef;
}

sub findInPaths {
	my ($paths, $file) = @_;
	my $path = undef;
	for (@{$paths}) {
		$_ .= '/' unless m/\/$/;
		if ( -e $_.$file) {
			$path = $_.$file;
			last;
		}
	}
	$path;
}

1;

## Load plugins and register their hooks and whatever else they need to function
package MicroJuke::Plugin;

use warnings;
use strict;

use File::Basename;
use Storable qw(store_fd fd_retrieve);

sub new {
	my $self = {};
	bless $self;

	$self->{loaded} = ();
	$self->{enabled} = {};

	$self->generateEnabled();

	$self;
}

# Fill our list of enabled plugins
sub generateEnabled {
	my $self = shift;
	my $path = MicroJuke::Conf::getVal('dir').'plugins_enabled.dat';
	return unless -e $path && -r $path;
	my $enabled = {};
	eval {
		open(H, '<'.$path) || return 0;
		$enabled = fd_retrieve(\*H) || return 0;
		close H;
	} || return 0;
	for (keys %{$enabled}) {
		$self->{enabled}->{$_} = $enabled->{$_} ? 1 : 0;
	}
	1;
}


# Just get available ones whether they're enabled
sub listAvailable {
	my $self = shift;
	my $pkg;
	my %packages;
	for (@{MicroJuke::Conf::getVal('pluginPath')}) {
		for my $path (glob "$_*.pl") {
			($pkg = basename($path)) =~ s/\.pl$//g;
			my $descript = MicroJuke::misc::file_contents "$_$pkg.txt";
			$packages{$pkg} = {
				path => $path,
				enabled => undef,
				description => $descript
			};
		}
	}
	for (keys %packages) {
		$packages{$_}->{enabled} = exists $self->{enabled}->{$_} && $self->{enabled}->{$_} ? 1 : 0;
	}
	return \%packages;
}

# Save our list of available ones
sub saveEnabled {
	my $self = shift;
	my $path = MicroJuke::Conf::getVal('dir').'plugins_enabled.dat';
	open H, '>'.$path || return 0;
	store_fd ($self->{enabled}, \*H) || return 0;
	close H;
	1;
}

# Find plugin file, load it, start it off by localizing it 
# with our useful pre-existing objects so it can interact and 
# assign events.
sub load {
	my ($self, $plugin) = @_;
	my $path = '';
	for (@{MicroJuke::Conf::getVal('pluginPath')}) {
		if (-e "$_$plugin.pl") {
			$path = "$_$plugin.pl";
			last;
		}
	}
	unless ($path) {
		print "Failed finding file for plugin $plugin\n";
		return 0;
	}
	eval {
		require $path;
		my $package = "MicroJuke::Plugin::$plugin";
		$self->{hooks}->{$plugin} = $package->new({
			gui => $self->{gui},
			play => $self->{play}
		});
		push @{$self->{loaded}}, $plugin;
		return 1;
	} or warn "Couldn't load plugin $plugin:\n $@\n";
}

# Load each of our enabled available plugins
sub loadEnabled {
	my $self = shift;
	for (keys %{$self->{enabled}}) {
		$self->load($_) if $self->{enabled}->{$_};
	}
}

# Same as above, but for all we can find. Each package name has a priority
# so local ones take precedence over global/system-wide ones.
sub loadAll {
	my $self = shift;
	my $pkg;
	my %packages;
	for (@{MicroJuke::Conf::getVal('pluginPath')}) {
		for my $path (glob "$_*.pl") {
			($pkg = basename($path)) =~ s/\.pl$//g;
			$packages{$pkg} = $path;
		}
	}
	for (keys %packages) {
		eval {
			require $packages{$_};
			my $package = "MicroJuke::Plugin::$_";
			$self->{hooks}->{$_} = $package->new({
				gui => $self->{gui},
				play => $self->{play}
			});
			return 1;
		} or warn "Couldn't load plugin $_:\n $@\n";
	}
}

1;

## Maintain play state
package MicroJuke::Play;

use warnings;
use strict;

use GStreamer -init;
use Glib qw(TRUE FALSE);
use Storable qw(store_fd fd_retrieve);
use POSIX qw(floor ceil);

use Data::Dumper;

sub new {
	my $self = {};
	$self->{all_songs} = ();
	$self->{files} = {};
	$self->{gstate} = {
		playing => 0,
		playing_what => -1,
		file => undef,
		scrobbled => 0,
		artist => undef,
		album => undef,
		song => undef,
		duration => undef
	};
	$self->{loop} = Glib::MainLoop -> new();
	$self->{play} = GStreamer::ElementFactory -> make("playbin", "play");

	unless ($self->{play}) {
		die "Cannot open audio playbin\n";
	}

	bless $self;
}

sub reloadSongList {
	my $self = shift;
	my $path = MicroJuke::Conf::getVal('dir').'songs.dat';
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
		$progress = floor($progress / 1000000000);
	}

	my $dst = GStreamer::Query::Duration->new ('time');
	if ($self->{play}->query($dst)) {
		($dfield, $duration) = $dst->duration('time');
		$duration = floor($duration / 1000000000);
	}

	return 0 if !defined $progress || !defined $duration;

      	$self->{gstate}->{duration} = $duration;

	$self->{gui}->{w}->{slider_a}->set_value((($progress/$duration)*100));

	$self->{gui}->{w}->{np_timer}->set_text(MicroJuke::GUI::seconds2minutes($progress).' of '.MicroJuke::GUI::seconds2minutes($duration));

	return 1;
}

sub busCallBack {
	my ($self, $bus, $message) = @_;

	if ($message -> type & "error") {
		$self->{loop} -> quit();
	}

	elsif ($message -> type & "eos") {
		$self->{loop}->quit();
		for (keys %{$self->{plugins}->{hooks}}) {
			if ($self->{plugins}->{hooks}->{$_}->can('onSongEnd')) {
				$self->{plugins}->{hooks}->{$_}->onSongEnd();
			}
		}
		$self->playSong($self->{gstate}->{playing_what} + 1);
	}

	return 1;
}

sub stopPlaying {
	my $self = shift;

      	$self->{gstate}->{artist} = undef;
      	$self->{gstate}->{album} = undef;
      	$self->{gstate}->{title} = undef;
      	$self->{gstate}->{duration} = undef;
	$self->{gstate}->{file} = undef;

	$self->{gui}->{w}->{plb_pause}->hide;
	$self->{gui}->{w}->{plb_play}->show;

	$self->{gui}->{w}->{slider_a}->set_value(0.0);

	$self->{play}->set_state('null');
	Glib::Source->remove ($self->{gui}->{w}->{periodic_time_dec}) if $self->{gui}->{w}->{periodic_time_dec};
	$self->{gui}->{w}->{np_timer}->set_text('');
	$self->{gui}->{w}->{npl}->set_text('Nothing playing');
	$self->{gui}->{w}->{main}->set_title('MicroJuke '.MicroJuke::Conf::VERSION);
}

sub playSong {
	my ($self, $index) = @_;

	unless (defined $self->{files}->{$index}) {
		$index = 0;
	}

	my $file = $self->{files}->{$index};


	$self->{gstate}->{playing_what} = $index;
	$self->{gstate}->{file} = $file;
      	$self->{gstate}->{playing} = 1;

	$self->{gui}->{w}->{slider_a}->set_value(0.0);
	$self->{gui}->{w}->{plb_pause}->show;
	$self->{gui}->{w}->{plb_play}->hide;

	$self->{gui}->jumpToSong();

	$self->{play}->set_state('null');

	my ($artist, $title, $album) = (
		$self->{gui}->{w}->{pl}->{data}[$index][2],
		$self->{gui}->{w}->{pl}->{data}[$index][1],
		$self->{gui}->{w}->{pl}->{data}[$index][3]
	);

      	$self->{gstate}->{artist} = $artist;
      	$self->{gstate}->{album} = $album;
      	$self->{gstate}->{title} = $title;

      	$self->{gstate}->{timeStarted} = time();

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

	$self->{gui}->{w}->{main}->set_title("MicroJuke ".MicroJuke::Conf::VERSION." - [$artist] $title");


	# Go through plugins supporting some action or whatever here
	for my $plugin (keys %{$self->{plugins}->{hooks}}) {
		if ($self->{plugins}->{hooks}->{$plugin}->can('onSongStart')) {
			$self->{plugins}->{hooks}->{$plugin}->onSongStart();
		}
	}
}

1;

## Keep track of the GUI
package MicroJuke::GUI;

use strict;
use warnings;

use File::Basename;

use Gtk2 qw(-init -threads-init);
use Glib qw(TRUE FALSE);
use Gtk2::SimpleMenu;
use Gtk2::SimpleList;
use Data::Dumper;
use POSIX qw(floor);
use Data::Dumper;
Glib::Object->set_threadsafe (TRUE); 

sub new {
	my $self = {};
	$self->{w} = ();
	bless $self;

	# Create this here so plugins can modify it if need be. Plugins are already
	# configured by the time init_gui() is called, so it'd be too late after that.
	$self->{w}->{menu_tree} = [
		_File => {
			item_type => '<Branch>',
			children => [
				
				'Plugins' => {
					callback => sub {
						$self->init_plugin_window;
					}
				},

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
						return unless defined $self->{play}->{play};
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
						$self->{play}->stopPlaying();
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
				'_Jump to current song' => {
					callback => sub {
						$self->jumpToSong();
					}
				},
			]

		},
		_Help => {
			item_type=>'<Branch>',
			children => [
				'_About' => {
					callback => sub {
						$self->show_about();
					}
				},
			]
		}
	];

	$self;
}

sub jumpToSong {
	my $self = shift;
	if ($self->{play}->{gstate}->{playing_what} > -1) {
		my $path = Gtk2::TreePath->new_from_indices($self->{play}->{gstate}->{playing_what});
		$self->{w}->{pl}->scroll_to_cell($path);
		$self->{w}->{pl}->set_cursor($path);
	}
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

	$self->{play}->{files} = {};
	@{$self->{w}->{pl}->{data}} = ();

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
		return if $nf == 0;
	}

	# Sort dem bitches
	@fsongs = sort {
		$a->[0] cmp $b->[0] || # Artist
		$a->[1] cmp $b->[1] || # Album
		$a->[2] <=> $b->[2] # Tracknum
	} @fsongs;
	
	my $i = 0;
	my $realized = 0;
	my ($sc, $state) = $self->{play}->{play}->get_state(4);
	for (@fsongs) {
		my $tn = $_->[2];
		$tn =~ s/^0+//; 
		push @{$self->{w}->{pl}->{data}}, [
			$tn eq '0' ? '' : $tn,
			toolong($_->[3]),
			toolong($_->[0]),
			toolong($_->[1]),
			$_->[5],
		];
		$self->{play}->{files}->{$i} = $_->[4];

		# In this new filter, try to set the current playing index to the proper file 
		if (($state eq 'playing' || $state eq 'paused') && defined $self->{play}->{gstate}->{file} &&
			$self->{play}->{gstate}->{file} eq $_->[4]) {
			$self->{play}->{gstate}->{playing_what} = $i;
			$realized = 1;
		}
		$i++;
	}

	# After filtering, if we haven't found our current song in the new filter, 
	# make the next song just be the beginning of the current filter
	if (!$realized && ($state eq 'playing' || $state eq 'paused')) {
		$self->{play}->{gstate}->{playing_what} = -1;
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
	$self->{w}->{main} = new Gtk2::Window 'toplevel';

	my $icon_path = undef; 
	for (@{MicroJuke::Conf::getVal('iconPath')}) {
		if (-e $_.'64x64.png') {
			$icon_path = $_.'64x64.png';
			last;
		}
	}

	if (!$icon_path && -e '/usr/share/icons/hicolor/16x16/apps/microjuke.png') {
		$icon_path = '/usr/share/icons/hicolor/16x16/apps/microjuke.png';
	}

	$self->{w}->{main}->set_default_icon_from_file($icon_path) if $icon_path;


	$self->{w}->{mv} = Gtk2::VBox->new;
	$self->{w}->{main}->add($self->{w}->{mv});

	$self->{w}->{menu} = Gtk2::SimpleMenu->new(menu_tree => $self->{w}->{menu_tree}, default_callback => sub {}, user_data => 'user_data');

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

	# Playback
	$self->{w}->{playback} = Gtk2::HBox->new;
	$self->{w}->{slider_a} = Gtk2::Adjustment->new(0.0, 0, 101.0, 0.1, 1.0, 1.0);
	$self->{w}->{slider} = Gtk2::HScale->new( $self->{w}->{slider_a});
	$self->{w}->{slider}->set_size_request(200, -1);
	$self->{w}->{slider}->set_draw_value(0);
	$self->{w}->{mv}->pack_start($self->{w}->{playback}, 0, 0, 0);
	$self->{w}->{slider_a}->signal_connect('value-changed', sub {
		my ($widget, $self) = @_;
	#	print Dumper($widget->get_value);
		return 0;
	}, $self);

	# Button bar
	$self->{w}->{playback_btns} = Gtk2::HBox->new;
	$self->{w}->{plb_play} = Gtk2::Button->new_from_stock('gtk-media-play');
	$self->{w}->{plb_pause} = Gtk2::Button->new_from_stock('gtk-media-pause');
	$self->{w}->{plb_previous} = Gtk2::Button->new_from_stock('gtk-media-previous');
	$self->{w}->{plb_next} = Gtk2::Button->new_from_stock('gtk-media-next');
	for (qw(plb_previous plb_play plb_pause plb_next)) {
		$self->{w}->{playback_btns}->add($self->{w}->{$_}) ; 
		$self->{w}->{$_}->set_focus_on_click(0);
	}
	$self->{w}->{playback}->pack_start($self->{w}->{playback_btns}, 0, 0, 0);

	sub playPause {
		my $self = shift;
		return unless defined $self->{play}->{play};
		my ($sc, $state) = $self->{play}->{play}->get_state(4);
		if ($state eq 'paused') {
			$self->{play}->{play}->set_state('playing');
			$self->{w}->{plb_pause}->show;
			$self->{w}->{plb_play}->hide;
		} 
		elsif ($state eq 'playing') {
			$self->{play}->{play}->set_state('paused');
			$self->{w}->{plb_pause}->hide;
			$self->{w}->{plb_play}->show;
		}
		elsif ($state eq 'null' && $self->{play}->{gstate}->{playing_what} == -1) {
			$self->{play}->playSong(0);
			$self->{w}->{plb_pause}->show;
			$self->{w}->{plb_play}->hide;
		}
	}

	$self->{w}->{plb_play}->signal_connect('clicked', sub {
		playPause($self);
	});

	$self->{w}->{plb_pause}->signal_connect('clicked', sub {
		playPause($self);
	});

	$self->{w}->{plb_next}->signal_connect('clicked', sub {
		 $self->{play}->playSong($self->{play}->{gstate}->{playing_what} + 1);
	});

	$self->{w}->{plb_previous}->signal_connect('clicked', sub {
		 $self->{play}->playSong($self->{play}->{gstate}->{playing_what} - 1);
	});

	# Add slider
	$self->{w}->{playback}->pack_end($self->{w}->{slider}, 0, 0, 0);


	# Add player list
	$self->{w}->{plc}->add($self->{w}->{pl});
	$self->{w}->{mv}->add($self->{w}->{plc});

	# Status bar
	$self->{w}->{sb} = Gtk2::Statusbar->new();
	$self->{w}->{sbID} = $self->{w}->{sb}->get_context_id('se');
	$self->{w}->{sb}->push($self->{w}->{sbID}, '');

	# Search
	$self->{w}->{search} = Gtk2::HBox->new;
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

	$self->{w}->{end_vbox} = Gtk2::VBox->new;
	$self->{w}->{end_vbox}->add($self->{w}->{search});
	$self->{w}->{end_vbox}->pack_end($self->{w}->{sb}, 0, 0, 0);
	$self->{w}->{mv}->pack_end($self->{w}->{end_vbox}, 0, 0, 0);

	# Finalize
	$self->{w}->{main}->show_all;
	$self->{w}->{main}->set_title('MicroJuke '.MicroJuke::Conf::VERSION);

	# Make pause button initially unhidden
	$self->{w}->{plb_pause}->hide;

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

	# Start up
	Gtk2->main;
}

sub show_about {
	my $self = shift;
	my $w = Gtk2::AboutDialog->new;
	my $icon_path = MicroJuke::Conf::findInPaths(MicroJuke::Conf::getVal('iconPath'), '64x64.png');
	if ($icon_path) {
		$w->set_logo(Gtk2::Gdk::Pixbuf->new_from_file($icon_path));
	}
	$w->set_license('GPL');
	$w->set_program_name('MicroJuke');
	$w->set_authors('Joe Gillotti');
	$w->set_copyright('(c) 2012 Joe Gillotti');
	$w->set_comments('A simple music player for Unix');
	$w->show_all;
	$w->run;
	$w->destroy;
}

sub openWebBrowser {
	open my $pipe, '-|', '/usr/bin/xdg-open', shift;
	close $pipe;
}

sub die {
	my $self = shift;
	Glib::Source->remove ($self->{w}->{periodic_time_dec}) if $self->{w}->{periodic_time_dec};
	# Properly kill the audio stream otherwise we'll get gstreamer errors upon program close
	if (defined $self->{play}->{play}) {
		$self->{play}->{play}->set_state('null') if $self->{play}->{play}->can('set_state');
	}
	Gtk2->main_quit;
}

sub init_plugin_window {
	my $self = shift;
	$self->{pl_window} = {};
	$self->{pl_window}->{window} = Gtk2::Dialog->new(
		'MicroJuke Plugin Preferences',
		$self->{w}->{main},
		[qw/modal destroy-with-parent/]
	);

	$self->{pl_window}->{ml} = Gtk2::Label->new('Available Plugins');

	$self->{pl_window}->{window}->get_content_area()->pack_start($self->{pl_window}->{ml}, 0, 0, 0);

	# Plugin list
	$self->{pl_window}->{plist} = Gtk2::SimpleList->new(
		'Enabled' => 'bool',
		'Plugin Name' => 'text',
		'Description' => 'text'
	);
	$self->{pl_window}->{plist}->columns_autosize();
	map {$_->set_sizing ('autosize')} $self->{pl_window}->{plist}->get_columns;
	map {$_->set_resizable (TRUE)} $self->{pl_window}->{plist}->get_columns;
	map {$_->set_expand (FALSE)} $self->{pl_window}->{plist}->get_columns;

	# Scrolly fucker that holds plugin list
	$self->{pl_window}->{plist_c} = Gtk2::ScrolledWindow->new (undef, undef);
	$self->{pl_window}->{plist_c}->set_policy ('automatic', 'always');
	$self->{pl_window}->{plist_c}->set_size_request (200,100);
	$self->{pl_window}->{plist_c}->add($self->{pl_window}->{plist});

	# Populate it, like a fucking boss 
	my %available = %{$self->{plugins}->listAvailable};
	for (keys %available) {
		push @{$self->{pl_window}->{plist}->{data}}, [
			$available{$_}->{enabled},
			$_,
			$available{$_}->{description}
		];
	}

	# Little button row thing at the bottom for configuring a highlighted plugin
	$self->{pl_window}->{hbox} = Gtk2::HBox->new;
	$self->{pl_window}->{cbtn} = Gtk2::Button->new('Configure');
	$self->{pl_window}->{hbox}->pack_start($self->{pl_window}->{cbtn}, 0, 0, 0);
	$self->{pl_window}->{cbtn}->set_sensitive(0);

	$self->{pl_window}->{window}->get_content_area()->add($self->{pl_window}->{plist_c});
	$self->{pl_window}->{window}->get_content_area()->pack_end($self->{pl_window}->{hbox}, 0, 0, 0);

	# Events for the list dude
	$self->{pl_window}->{plist}->signal_connect('cursor-changed', sub {
		print "picked one!\n";
	});
	
	$self->{pl_window}->{window}->show_all;

	my $resp = $self->{pl_window}->{window}->run;
	$self->kill_plugin_window($resp);
}

sub kill_plugin_window {
	my ($self, $resp) = @_;

	# Save plugin enabler choices.
	for (@{$self->{pl_window}->{plist}->{data}}) {
		$self->{plugins}->{enabled}->{$_->[1]} = $_->[0];
	}
	$self->{plugins}->saveEnabled();

	$self->{pl_window}->{window}->destroy;
	
	# Fuck memory leaks
	delete $self->{pl_window};
}

# Tack an item onto our main toolbar menu. Accepts the existing menu name and the item to add. 
sub add_menu_item {
	my ($self, $menu_name, $item) = @_;
	my $added = 0;
	for (keys @{$self->{w}->{menu_tree}}) {
		if ($self->{w}->{menu_tree}->[$_] eq $menu_name && ref($self->{w}->{menu_tree}->[$_ + 1]) eq 'HASH') {
			push @{$self->{w}->{menu_tree}->[$_ + 1]->{children}}, $item->{title};
			push @{$self->{w}->{menu_tree}->[$_ + 1]->{children}}, $item->{payload};
			$added = 1;
		}
	}

	# If we didn't stick our value at the end of an existing menu item, 
	# create a new one. Subsequent calls referencing the same menu item
	# will be processed by above.
	unless ($added) {
		push @{$self->{w}->{menu_tree}}, $menu_name , {
			item_type => '<Branch>',
			'children' => [
				$item->{title},
				$item->{payload}
			]
		};	
	}
}

1;

## Start us up
package main;

BEGIN {$| = 1;}

use warnings;
use strict;
use utf8;

MicroJuke::Conf::init();

my $plugins = MicroJuke::Plugin->new;
my $play = MicroJuke::Play->new;
my $gui = MicroJuke::GUI->new;

$play->{plugins} = $plugins;
$play->{gui} = $gui;

$gui->{plugins} = $plugins;
$gui->{play} = $play;

$plugins->{gui} = $gui;
$plugins->{play} = $play;

$plugins->loadEnabled();

# This will block until gtk dies, so call it last
$gui->init_gui();

1;
