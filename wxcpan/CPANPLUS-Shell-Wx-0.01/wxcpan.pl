#!/usr/bin/perl -w

#wxcpan.pl:
#	This is a program which calls the appropriate methods to invoke 
#	the wxCPANPLUS shell.
use Cwd;

my $dir=cwd;
#print $dir;

use lib cwd().'/lib';

use CPANPLUS;


shell(Wx);