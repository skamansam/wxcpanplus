#!/usr/bin/perl -w
#this test is used internally. It is used to detect the information returned 
# by CPANPLUS. Think of this as a learning experience.

use CPANPLUS::Backend;
use CPANPLUS::Module;
use CPANPLUS::Module::Author;
use CPANPLUS::Config;
use CPANPLUS::Configure;
use CPANPLUS::Error;
use Data::Dumper;
use Storable qw/retrieve/;

#my $cb=CPANPLUS::Backend->new();
#my $conf=$cb->configure_object();
#print Dumper($conf->list_custom_sources);


