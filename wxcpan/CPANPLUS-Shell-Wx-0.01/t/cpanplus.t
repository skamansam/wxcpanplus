#!/usr/bin/perl -w
#this test is used internally. It is used to detect the information returned 
# by CPANPLUS. Think of this as a learning experience.
use Cwd;
my $dir=cwd;
print $dir;
use lib cwd().'../lib';

use CPANPLUS::Backend;
use CPANPLUS::Module;
use CPANPLUS::Module::Author;
use CPANPLUS::Config;
use CPANPLUS::Configure;
use CPANPLUS::Error;
use CPANPLUS::Shell::Wx::ModulePanel;

use Data::Dumper;
use Storable qw/retrieve/;

my $cb=CPANPLUS::Backend->new();
my $conf=$cb->configure_object();
#print Dumper($conf->list_custom_sources);

#my $modName='Alter-0.04';
#my $mod=$cb->parse_module(module=>$modName);
#print Dumper $mod;
#print $mod->fetch();

$frame=TestFrame->new();
print $frame;	
$frame->Show(1) if ($frame);

package TestFrame;

use Wx qw[:everything wxHORIZONTAL wxEXPAND];
use base qw(Wx::Frame);
use strict;
use lib '../lib';
use CPANPLUS::Shell::Wx::ModulePanel;
use CPANPLUS::Shell::Wx::util;
use Data::Dumper;
sub new {
print Dumper @INC;
	my( $self, $parent, $id, $title, $pos, $size, $style, $name ) = @_;
	$parent = undef              unless defined $parent;
	$id     = -1                 unless defined $id;
	$title  = ""                 unless defined $title;
	$pos    = wxDefaultPosition  unless defined $pos;
	$size   = wxDefaultSize      unless defined $size;
	$name   = ""                 unless defined $name;

	$style = wxDEFAULT_FRAME_STYLE 
		unless defined $style;

	print "PATH: "._uGetInstallPath('CPANPLUS::Shell::Wx::ModulePanel.pm');
	$self = $self->SUPER::new( $parent, $id, $title, $pos, $size, $style, $name );
	$self->{embed} = CPANPLUS::Shell::Wx::ModulePanel->new($self, -1);
	print Dumper $self->{embed};
	$self->SetTitle("PODReader");
	$self->SetSize(Wx::Size->new(520, 518));

	$self->{sizer_1} = Wx::BoxSizer->new(wxHORIZONTAL);
	$self->{sizer_1}->Add($self->{embed}, 1, wxEXPAND, 0);
	$self->SetSizer($self->{sizer_1});
	$self->Layout();

	return $self;

}
