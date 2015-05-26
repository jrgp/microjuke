MicroJuke
=======

**A Perl/GTK desktop music player.**

![MicroJuke Screenshot](http://jrgp.us/screenshots/perl_music/13.png)

By Joe Gillotti <joe@u13.net>, released under the GPL

NOTE: This is ***extremely*** beta. I've been listening to it a lot lately, but it 
really lacks polish in its current state. (1/1/2012)

## Features 
- Automatically recursively parse and construct your song library
- Quickly find and play the thousands of tracks in your library
- Scrobble plays to last.fm
- Desktop song change notifications
- Plugins to add hooks for actions such as song changing
- "remote control" unix domain socket interface for other apps, such as `microjuke-client.pl`

## Start Here 
1. Install dependencies (as below).
2. Symlink your music library to $HOME/Music or store your music there. This is hardcoded unfortunately
3. Run `perl microjuke.pl` or make a shortcut to it

####For last.fm:

1. go to File -> Plugins. Tick the Last.FM box
2. restart microjuke
3. go to Last.FM > Authenticate as different user
4. It will open your web browser to last.fm's app auth page
5. Log in / click allow access. 

## Dependencies 

Necessary dependencies and perl modules are:

- Gstreamer
- Glib
- Gtk2
- Gtk2::SimpleMenu
- Gtk2::SimpleList
- MP3::Info
- LWP

The following are optional. On systems that do not provide packages for them, install
vorbis-tools and flac, for potentially slightly slower performance when parsing

- Ogg::Vorbis::Header
- Audio::FLAC::Header
- MP4::Info
- Audio::WMA

### How to install dependencies 

Ubuntu/Debian (Verified 5/25/15 on Debian 8):

```apt-get install libgstreamer-perl libgstreamer-interfaces-perl  libgtk2-perl libmp3-info-perl libogg-vorbis-decoder-perl libogg-vorbis-header-pureperl-perl  libaudio-flac-header-perl gstreamer0.10-plugins-bad gstreamer0.10-plugins-base gstreamer0.10-plugins-good gstreamer0.10-plugins-ugly libgtk2-notify-perl xdg-utils libxml-simple-perl libmp4-info-perl libaudio-wma-perl```

Fedora (you may need to enable RPMForge):

```yum install perl-Gtk2 perl-MP3-Info perl-GStreamer perl-libwww-perl.noarch vorbis-tools flac perl-Gtk2-Notify xdg-utils perl-XML-Simple```

FreeBSD - install these ports/packages:

```p5-Gtk2 p5-Glib2 p5-GStreamer gstreamer-plugins-bad gstreamer-plugins-good gstreamer-plugins-ugly p5-MP3-Info p5-audio-flac-header p5-Ogg-Vorbis-Header```

## TODO

- cleaner UI, with album art displayed
- more plugins
- perl-gtk2 people need to move faster and get better OS X support
- debug output to part of the UI instead of just stdout
- python rewrite? :(
