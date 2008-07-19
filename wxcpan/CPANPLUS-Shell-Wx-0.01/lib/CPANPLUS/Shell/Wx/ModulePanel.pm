package CPANPLUS::Shell::Wx::ModulePanel;
use Wx qw[:everything];
use base qw(Wx::Panel);
use Wx::Event qw(EVT_CONTEXT_MENU EVT_WINDOW_CREATE EVT_BUTTON 
		EVT_TREE_SEL_CHANGED EVT_TREE_ITEM_ACTIVATED EVT_RIGHT_DOWN
		EVT_TREE_ITEM_RIGHT_CLICK);
use Wx::ArtProvider qw/:artid :clientid/;

#since we want to route calls from here to the module tree,
our $AUTOLOAD;

use Data::Dumper;
use YAML qw/LoadFile Load/;
use File::Spec;
use File::Path;
use Storable;

use threads;
use LWP::Simple;
use Wx::Locale gettext => '_T';

use CPANPLUS::Shell::Wx::util;

sub new{
	my( $self, $parent, $id, $pos, $size, $style, $name ) = @_;
	$parent = undef              unless defined $parent;
	$id     = -1                 unless defined $id;
	$pos    = wxDefaultPosition  unless defined $pos;
	$size   = wxDefaultSize      unless defined $size;
	$name   = ""                 unless defined $name;
	$style  = wxTAB_TRAVERSAL    unless defined $style;

	$self = $self->SUPER::new( $parent, $id, $pos, $size, $style, $name );
	print "New ModulePanel\n";
	return $self;
}

#initialize all the children. This was the OnWindowCreate Handler
sub Init {
	my $self = shift;

	#get references so we can access them easier
	$self->{parent}=$self->GetParent();		#Wx::Window::FindWindowByName('main_window');
	$self->{mod_tree}=Wx::Window::FindWindowByName('tree_modules');
	$self->{mod_tree}->Init();
	#show info on what we are doing
	Wx::LogMessage _T("Showing "),$self->{'show'},_T(" by "),$self->{'sort'};

	#populate tree with default values
	#$self->{mod_tree}->Populate();

	#print Dumper $self->{mod_tree};
	#for testing purposes, insert test values 
	my @testMods=qw/Alter CPAN Cache::BerkeleyDB CPANPLUS Module::NoExist Muck Acme::Time::Baby Wx/;
		foreach $item (sort(@testMods)){
			$self->{mod_tree}->AppendItem($self->{mod_tree}->GetRootItem(),$item,$self->{mod_tree}->_get_status_icon($item));
		}
		
	#my $cMenu=$self->{mod_tree}->GetContextMenu();
	$self->{mod_tree}->SetInfoHandler(\&HandleContextInfo);
	
	_uShowErr;
}

# Here, we reroute the calls to ModuleTree
sub AUTOLOAD{
	my $self=shift;
	my @ops=@_;
	my $type = ref($self) or return undef;
	my $func=$AUTOLOAD;
	$func =~ s/.*:://;
	if ($self->{mod_tree}->can($func)){
		@ops=map( ((defined($_))?$_:'undef'),@ops);
		my $param=join(',',@ops);
		my $estr="\$self->{mod_tree}->$func($param);";
		eval($estr);
		print $@ if $@;
	}else{
		Wx::LogError("Sorry! $func() does not exist!");
	}
}

sub HandleContextInfo{
	my ($self,$menu,$cmd_event,$modName)=@_;
	my $modtree=Wx::Window::FindWindowByName('tree_modules');
	
	$modtree->_get_more_info($self->{cpan}->parse_tree(module=>$modName));
}

#accessors (should be obvious)
sub SetStatus{$_[0]->{statusBar}=$_[1];}		#any widget that has SetStatusText($txt) method
sub GetStatus{return $_->{statusbar};}
sub SetPODReader{$_[0]->{PODReader}=$_[1];}		#must be a CPANPLUS::Shell::Wx::PODReader
sub GetPODReader{return $_->{statusbar};}
sub SetImageList{								#must be a Wx::ImageList
	$_[0]->{imageList}=$_[1];
	$_[0]->{mod_tree}->SetImageList($_[1]);
	Wx::Window::FindWindowByName('info_prereqs')->AssignImageList($_[1]->{imageList});
}
sub GetImageList{return $_->{imageList};}
sub SetModuleTree{$_[0]->{mod_tree}=$_[1];}		#must be a CPANPLUS::Shell::Wx::ModuleTree
sub GetModuleTree{return $_->{mod_tree};}
sub SetCPP{										#must be a CPANPLUS::Backend
	my $self=shift;
	my $cpp=shift;
	$self->{cpan}=$cpp;
	$self->{config}=$cpp->configure_object;
	$self->{mod_tree}->{cpan}=$cpp if $self->{mod_tree};
	$self->{mod_tree}->{config}=$cpp->configure_object if $self->{mod_tree};
}
sub GetCPP{return $_[0]->{cpan};}
sub SetConfig{$_[0]->{config}=$_[1];}			#must be a CPANPLUS::Backend::Configure
sub GetConfig{return $_[0]->{config};}

1;