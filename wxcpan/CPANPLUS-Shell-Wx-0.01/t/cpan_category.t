#!/usr/bin/perl
use Net::FTP;
use Data::Dumper;
my $host='cpan.hexten.net';
my $path='/modules/by-category';
print "Connecting to ftp://$host : $path\n";
my $ftp=Net::FTP->new($host);
die "Unable to create FTP object";
$ftp->login() or die "Cannot change directory!";
$ftp->cwd($path) or die "Cannot get working Directory!";
my %tree=();
_build_ftp_tree($ftp,\%tree);
print Dumper \%tree;

sub _build_ftp_tree{
	my $ftp=shift;
	my $tree_ref=shift;
	my @files=$ftp->ls();
	foreach $f (@files){
		next if ($f eq '.' or 
				 $f eq '..' or 
				 $f=~/\.readme$/i or
				 $f=~/\.meta$/i or
				 $f=~/^checksums$/i
				 );
		my %anon=();
		$tree_ref->{$f}=\%anon; #append this files
		next unless $ftp->cwd($f); #try to cd, if directory
		print "CD: $f";
		_build_ftp_tree($ftp,$tree_ref->{$f}); #build on to tree
	}
	$ftp->cwd('..');
}