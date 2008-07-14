#!/usr/bin/perl -w

use lib '../lib';
use CPANPLUS::Shell::Wx::cpan_connector;
use Data::Dumper;

my $cpan=new CPANPLUS::Shell::Wx::cpan_connector();

my $mod=$cpan->module_tree('CPAN');
print Dumper $mod;
#print Dumper $mod->details();

