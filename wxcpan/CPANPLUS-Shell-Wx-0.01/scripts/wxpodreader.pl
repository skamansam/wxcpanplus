#!/usr/bin/perl -w

#wxcpan.pl:
#    This is a program which calls the appropriate methods to invoke
#    the wxCPAN PODReader component.
use Cwd;

my $dir=cwd;
#print $dir;

use lib cwd().'/lib';

use Wx qw[:allclasses];
use CPANPLUS::Shell::Wx::PODReader;

local *Wx::App::OnInit = sub{1};
my $app = Wx::App->new();
Wx::InitAllImageHandlers();

my $frame_podreader = CPANPLUS::Shell::Wx::PODReader::Frame->new();

$app->SetTopWindow($frame_podreader);
$frame_podreader->Show(1);
$app->MainLoop();