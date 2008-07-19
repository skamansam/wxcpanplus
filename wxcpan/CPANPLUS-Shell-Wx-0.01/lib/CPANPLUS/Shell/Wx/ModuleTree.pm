#TODO make the moduletree a TreeCtrl and this module a panel
package CPANPLUS::Shell::Wx::ModuleTree;

use Wx qw/wxPD_APP_MODAL wxPD_APP_MODAL wxPD_CAN_ABORT 
		wxPD_ESTIMATED_TIME wxPD_REMAINING_TIME wxLIST_AUTOSIZE 
		wxVSCROLL wxALWAYS_SHOW_SB wxUPDATE_UI_RECURSE /;
use Wx::Event qw(EVT_CONTEXT_MENU EVT_WINDOW_CREATE EVT_BUTTON 
		EVT_TREE_SEL_CHANGED EVT_TREE_ITEM_ACTIVATED EVT_RIGHT_DOWN
		EVT_TREE_ITEM_RIGHT_CLICK);
use Wx::ArtProvider qw/:artid :clientid/;

use Data::Dumper;
use YAML qw/LoadFile Load/;
use File::Spec;
use File::Path;
use Storable;

use threads;
use LWP::Simple;
use Wx::Locale gettext => '_T';

use CPANPLUS::Shell::Wx::util;

#the base class
use base 'Wx::TreeCtrl';

BEGIN {
	use vars qw( @ISA $VERSION);
	@ISA     = qw( Wx::TreeCtrl);
	$VERSION = '0.01';
}

#use some constants to better identify what's going on,
#so we can do stuff like:
# 	$self->{'sort'}=(SORTBY)[CATEGORY]; #sort by category 

use constant SORTBY => (_T("Author"), _T("Name"), _T("Category"));
use constant {AUTHOR=>0,NAME=>1,CATEGORY=>2};
use constant SHOW => (_T("Installed"),_T("Updated"),_T("New"),_T("All"))   ; 
use constant {INSTALLED=>0,UPDATES=>1,NEW=>2,ALL=>3};
use constant MAX_PROGRESS_VALUE => 100000; #the max value of the progressdialogs


sub new {
	my $class = shift;
	my $self  = $class->SUPER::new();    # create an 'empty' TreeCtrl object

	#set default behavior
	$self->{'sort'}=(SORTBY)[CATEGORY]; #DEFAULT: sort by category 
#	$self->{'sort'}=(SORTBY)[AUTHOR];   #sort by author
#	$self->{'sort'}=(SORTBY)[NAME];   #sort by module name
	$self->{'show'}=(SHOW)[INSTALLED];
#	$self->{'show'}=(SHOW)[UPDATES];  #DEFAULT: List Updated Modules
#	$self->{'show'}=(SHOW)[NEW];
#	$self->{'show'}=(SHOW)[ALL];

	#this is the thread reference to the info gathering method
	#this is started ad stopped when the listbox's selection is changed
	#threads may be removed in the future or not used at all.
	$self->{_threads}=(); 

	#setup category names for further use.
	#(they will be used to create hashes)
	$self->{catNames}=[
		_T("Not In Modulelist"),						_T("Perl Core Modules"),
		_T("Language Extensions"),						_T("Development Support"),
		_T("Operating System Interfaces"),				_T("Networking Devices, IPC"),
		_T("Data Type Utilities"), 						_T("Database Interfaces"), 
		_T("User Interfaces"),							_T("Language Interfaces"), 
		_T("File Names, Systems Locking"), 				_T("String/Language/Text Processing"),
		_T("Options/Arguments/Parameters Processing"),	_T("Internationalization, Locale"),
		_T("Security and Encryption"),					_T("World Wide Web, HTML, HTTP, CGI"),
		_T("Server and Daemon Utilities"),				_T("Archiving and Compression"),
		_T("Images, Pixmaps, Bitmaps"),					_T("Mail and Usenet News"),
		_T("Control Flow Utilities"),					_T("File Handle Input/Output"),
		_T("Microsoft Windows Modules"),				_T("Miscellaneous Modules"),
		_T("Commercial Software Interfaces"),			_T("Bundles"),
		_T("Documentation"),							_T("Pragma"),
		_T("Perl6")];

	#add the root item.It is hidden.
	$self->AddRoot(_T('Modules'));
	
	#create links to events
#	EVT_WINDOW_CREATE( $self, $self, \&OnCreate );			#when the tree is created
	EVT_TREE_SEL_CHANGED( $self, $self, \&OnSelChanged);	#when a user changes the selection
	EVT_TREE_ITEM_ACTIVATED($self, $self, \&ShowPODReader);	#When the user double-clicks an item
	EVT_TREE_ITEM_RIGHT_CLICK( $self, $self, \&ShowPopupMenu );#when the user wants a pop-up menu

	return $self;
}

#this is called when the control is created.
#sub OnCreate {
sub Init {
	my $self = shift;
	my ($event)=@_;

	#get references so we can access them easier
	$self->{parent}=Wx::Window::FindWindowByName('main_window');
	$self->{cpan}=$self->{parent}->{cpan};
	$self->{config}=$self->{cpan}->configure_object();
	
	#$self->AssignImageList($imgList);

#	Wx::Window::FindWindowByName('info_prereqs')->AssignImageList($imgList);
	#show info on what we are doing
	Wx::LogMessage _T("Showing "),$self->{'show'},_T(" by "),$self->{'sort'};

	#go ahead and get the list of categories
	$self->{category_list}=$self->_get_categories();
	
	$self->{statusBar}=Wx::Window::FindWindowByName('main_window_status');
	
	#populate tree with default values
	#$self->Populate();
	
	$self->{podReader}=$self->{parent}->{podReader} || CPANPLUS::Shell::Wx::PODReader::Frame->new($self);

	$self->SetWindowStyle($self->GetWindowStyleFlag()|wxVSCROLL|wxALWAYS_SHOW_SB);
	_uShowErr;
}

###############################
####### PUBLIC METHODS ########
###############################
#these methods are called from outside to display the relevant modules
sub ShowInstalled{shift->_switch_show(INSTALLED)}
sub ShowUpdated{shift->_switch_show(UPDATES)}
sub ShowNew{shift->_switch_show(NEW)}
sub ShowAll{shift->_switch_show(ALL)}
sub SortByAuthor{shift->_switch_sort(AUTHOR)}
sub SortByName{shift->_switch_sort(NAME)}
sub SortByCategory{shift->_switch_sort(CATEGORY)}

#this is called when the user right-clicks on an item in the tree
sub ShowPopupMenu{
	my $self = shift;
	my ($event)=@_;
	
	#we can't do any actions on unknown modules
	return if $self->GetItemImage($event->GetItem()) == 4;
	#create the menu
	$self->{menu}= CPANPLUS::Shell::Wx::ModuleTree::Menu->new($self,$event->GetItem());
	#show the menu
	$self->PopupMenu($self->{menu},$event->GetPoint());
}


#this method shows the PODReader tab and displays the documentation for the selected module
sub ShowPODReader{
	my $self     = shift;
	my ($event)  = @_;
	$self->{podReader}=CPANPLUS::Shell::Wx::PODReader::Frame->new($self) unless $self->{podReader};	
	$self->{podReader}->Show(1) if ($self->{podReader} && $self->{podReader}->isa('Wx::Frame'));
	$self->{podReader}->Search($self->{thisName});
	Wx::Window::FindWindowByName('nb_main')->ChangeSelection(3);
	
}
#this method calls the other methods to populate the tree
sub Populate{
	my $self = shift;
	
	$self->OnSelChanged();		#clear all values in Info pane
	$self->DeleteAllItems();	#clear all items in tree

	#add the root item with the name of what we are showing
	my $root=$self->AddRoot($self->{'show'});
	
	#tell the user we are populating the list
	$self->{statusBar}->SetStatusText(_T("Populating List..").$self->{'show'}._T(" By ").$self->{'sort'});

	#call the appropriate method for displaying the modules
	if ($self->{'sort'} eq (SORTBY)[AUTHOR]){
		$self->_show_installed_by_author() if ( $self->{'show'} eq (SHOW)[INSTALLED]);
		$self->_show_updates_by_author() if ( $self->{'show'} eq (SHOW)[UPDATES]);
		$self->_show_new_by_author() if ( $self->{'show'} eq (SHOW)[NEW]);
		$self->_show_all_by_author() if ( $self->{'show'} eq (SHOW)[ALL]);
	}
	if ($self->{'sort'} eq (SORTBY)[NAME]){
		$self->_show_installed_by_name() if ( $self->{'show'} eq (SHOW)[INSTALLED]);		
		$self->_show_updates_by_name() if ( $self->{'show'} eq (SHOW)[UPDATES]);
		$self->_show_new_by_name() if ( $self->{'show'} eq (SHOW)[NEW]);
		$self->_show_all_by_name() if ( $self->{'show'} eq (SHOW)[ALL]);
	}
	if ($self->{'sort'} eq (SORTBY)[CATEGORY]){
		$self->_show_installed_by_category() if ( $self->{'show'} eq (SHOW)[INSTALLED]);
		$self->_show_updates_by_category() if ( $self->{'show'} eq (SHOW)[UPDATES]);
		$self->_show_new_by_category() if ( $self->{'show'} eq (SHOW)[NEW]);
		$self->_show_all_by_category() if ( $self->{'show'} eq (SHOW)[ALL]);
	}

	#show any errors generated by CPANPLUS
	_uShowErr;
}

#update only info tab in the lower notebook and clear other items
sub OnSelChanged{
	my $self=shift;
	#set global variable for name of what the user selected
	$self->{thisName}=$self->GetItemText($self->GetSelection());
	#set global variable for CPANPLUS::Module object of what the user selected
	$self->{thisMod}=$self->_get_mod($self->{thisName});
	#reset all info in Info pane
	$self->_info_reset();
	#return if we can't get an object reference
	return unless $self->{thisMod};
	#display info
	$self->_info_get_info();
}

#this method check to see which prerequisites have not been met
# We only want recursion when a prereq is NOT installed.
#returns a list of prerequisites, in reverse install order
# i.e. $list[-1] needs to be installed first
sub CheckPrerequisites{
	my $self=shift;
	my $modName=shift;
	my $version=shift||'';
	my $pre=$self->GetPrereqs($modName,$version);
#	print Dumper $pre; 
	return;
	my @updates=();
	foreach $name (@$pre){
		my $mod=$self->_get_mod($name);
		next unless $mod;
		if ($mod->installed_version && $mod->installed_version >= $pre->{$key}){
			$self->{statusBar}->SetStatusText($mod->name." v".$mod->installed_version._T(" is sufficient."));
		}else{
			$self->{statusBar}->SetStatusText($mod->name." v".$mod->installed_version._T(" needs to be updated to ").$name);
			push (@updates,$name);
			push (@updates,$self->CheckPrerequisites($name));
		}
	}
	return @updates;
}
#Get module.yml from search.cpan.org and get prereqs from there.
#store in $HOME/.cpanplus/authors/X/XX/.../module.yml
sub _info_get_prereqs{	
	my $self=shift;
	my $mod=shift||$self->{thisMod};
	my $version=shift||'';
	#print "_info_get_prereqs($mod)\n";
	return unless $mod;
	#set up variables for retrieveing and setting data
	$self->{thisPrereq}=[];
	
	#get correct control and clear all items
	my $preTree=Wx::Window::FindWindowByName('info_prereqs');
	$preTree->DeleteAllItems();
	my $root=$preTree->AddRoot('prereqs');

	#append all prerequisites to root item
	$self->_append_prereq($self->_get_modname($mod,$version),$preTree,$root);

	#show any CPANPLUS errors in Log tab
	_uShowErr;
}

#this method fetches the META.yml file from
#search.cpan.org and parses it using YAML.
#It returns the Prerequisites for the given module name
# or the currently selected module, if none given.
# It stores the yml data in the same hierarchy as CPANPLUS
#stores its readme files and other data.
#returns: a list of modules that can be parsed by parse_module()
sub GetPrereqs{
	my $self=shift;
	my $modName=shift || $self->{thisName};
	my $version=shift||'';
	print "GetPrereqs($modName) \n ";
	my $mod=$self->_get_mod($modName,$version);
#	print $modName.(($version)?"-$version":'')."\n";
	print Dumper $mod;
	return unless $mod; #if we can't get a module from the name, return
	
	#set up the directory structure fro storing the yml file
	my $storedDir=File::Spec->catdir($ENV{HOME},".cpanplus","authors","id"); #the top-level directory for storing files
	my $author=$mod->author->cpanid; #get the cpanid of the author
	my @split=split('',$author); #split the author into an array so we can:
	my $dest=File::Spec->catdir($storedDir,$split[0],$split[0].$split[1],$author); #extract the first letters
	my $package=$mod->package_name.'-'.$mod->package_version; #name the file appropriately
	$dest=File::Spec->catfile($dest,"$package.yml");
	my $src="http://search.cpan.org/src/$author/$package/META.yml"; #where we are getting the file from

	my $ymldata=''; #the yaml data
	#if we already have this file, read it. Otherwise, get it from web
	if (-e $dest){
		$ymldata=LoadFile($dest);		
	}else{
		mkpath($dest,0,0775) unless (-d $dest);
		my $yml=getstore($src,$dest) ;
		$yml=get($src);
		$ymldata=Load($yml);		
	}

	#return the prequisites
	my $reqs=$ymldata->{'requires'}||{};
	my @ret=();
	foreach $modName (keys(%$reqs)){
		$name=$self->_get_mod($modName,{version=>$reqs->{$modName}});
#		print "$name-".$reqs->{$key}."\n";
		push(@ret,"$name");
	}

	return \@ret;
}

#appends prequisites the given tree.
#parameters: 
#	$module_name, $treeCtrl, $parentNodeInTree = $treeCtrl->GetRootItem
sub _append_prereq{
	my $self=shift;
	my $modName=shift;
	my $preTree=shift;
	my $parentNode=shift || $preTree->GetRootItem();	
	#set up variables for retrieveing and setting data
	print "_append_prereq($modName)\n";

	my $pre=$self->GetPrereqs($modName);
	#print Dumper $pre;
	foreach $mod (@$pre){
		push (@{$self->{thisPrereq}},$mod) unless ( grep($mod,@{$self->{thisPrereq}}) );
		my $pNode=$preTree->AppendItem($parentNode,$mod,$self->_get_status_icon($mod));
		$self->_append_prereq($mod,$preTree,$pNode);
	}
}

#this method returns a module for the given name.
# it is OK to pass an existing module ref, as it will
# simply return the ref. You can use this to validate 
# all modules and names. You can pass an optional 
# boolean denoting whether you would like to return the name
# so parse_module can understand it.
sub _get_mod{
	my ($self,$mod,$options)=@_;
	print 'usage: $tree->_get_mod($modObject|$name '.
		'[,{[version=>$version,] [mod=>$modObject,] [getname=>0|1]}])'."\n"
		unless ref($options) eq 'HASH';
	
	my $version=$options->{version}?"-".$options->{version}:''; #the version we want
#	my $name=$options->{name};									#the name we want
	$mod=$mod || $options->{mod};								#the moduleObject or name
	$onlyName=$options->{getname} || 0;							#return just the name?
	
#	print "_get_mod($name,$version,$onlyName)\n";
	#if a module ref is passed, return the ref or the package_name
	if (ref($mod) && ($mod->isa('CPANPLUS::Module') or $mod->isa('CPANPLUS::Module::Fake'))){
		if ($version){
			my $modname=$mod->name;
			$modname =~ s/::/-/g;									#parse out the colons in the name
			$mod=$self->{cpan}->parse_module(module=>$modname.$version );
			#return $newMod;
		}
		if ($onlyName){
			return $mod->package_name;
		}else{
			return $mod;
		}
	}
	$mod =~ s/::/-/g;									#parse out the colons in the name
	$mod=$self->{cpan}->parse_module(module=>$mod.$version); #get the module
	return $mod->package_name if ($mod && $onlyName);	#return the name if we want to
	return $mod;										#otherwise, return the module object
}
###############################
####### PRIVATE METHODS #######
###############################
#switch the type to show and populate list
#NOTE: These 2 methods are put here to eliminate repetative code
sub _switch_show{
	my ($self,$type) = @_;
	$self->{'show'}=(SHOW)[$type];
	Wx::LogMessage _T("Showing ").$self->{'show'}._T(" Modules");
	$self->Populate();
	_uShowErr;
}
sub _switch_sort{
	my ($self,$type) = @_;
	$self->{'sort'}=(SORTBY)[$type];
	Wx::LogMessage _T("Sorting by ").$self->{'sort'};
	$self->Populate();
	_uShowErr;
}


sub _get_more_info{
	my $self=shift;
	my $mod=shift||$self->{thisMod};
	return unless $mod;
	
	$self->{statusBar}->SetStatusText(_T("Getting Status for ").$mod->name."...");

	$progress=Wx::ProgressDialog->new(_T("Getting Extended Info..."),
				_T("Updating List of Files..."),
				8,$self,wxPD_APP_MODAL|wxPD_CAN_ABORT|wxPD_ESTIMATED_TIME|wxPD_REMAINING_TIME 
				);	
	$self->_info_get_versions($mod) if $progress->Update(4,_T("Getting Version Information..."));
	$self->_info_get_files($mod)  if $progress->Update(0);
	$self->_info_get_readme($mod) if $progress->Update(1,_T("Getting README..."));
	$self->_info_get_status($mod) if $progress->Update(2,_T("Getting Status for ").$self->{thisName}."...");
	$self->_info_get_prereqs($mod) if $progress->Update(3,_T("Getting Prerequisites for ").$self->{thisName}."...");
	$self->_info_get_contents($mod) if $progress->Update(5,_T("Getting Contents..."));
	$self->_info_get_report_all($mod) if $progress->Update(6,_T("Getting Reports..."));
	$self->_info_get_validate($mod) if $progress->Update(7,_T("Validating Module..."));

	$self->{statusBar}->SetStatusText('');
	$progress->Destroy();
	_uShowErr;

}
#clears all info fields. Optionally takes a tab name to clear only that tab's fields.
sub _info_reset{
	my $self=shift;
	my $context=shift;
	
	Wx::Window::FindWindowByName('info_tab_text')->SetValue($self->{thisName}._T(" may not exist!")) if (!$context || $context eq 'info');
	Wx::Window::FindWindowByName('info_report')->DeleteAllItems() if (!$context || $context eq 'report');
	Wx::Window::FindWindowByName('info_prereqs')->DeleteAllItems() if (!$context || $context eq 'prereqs');
	Wx::Window::FindWindowByName('info_validate')->Clear() if (!$context || $context eq 'validate');
	Wx::Window::FindWindowByName('info_files')->Clear() if (!$context || $context eq 'files');
	Wx::Window::FindWindowByName('info_contents')->Clear() if (!$context || $context eq 'contents');
	Wx::Window::FindWindowByName('info_readme')->Clear() if (!$context || $context eq 'readme');
	Wx::Window::FindWindowByName('info_distributions')->Clear() if (!$context || $context eq 'readme');
	if (!$context || $context eq 'status'){
		Wx::Window::FindWindowByName('info_status_installed')->SetValue(0);
		Wx::Window::FindWindowByName('info_status_uninstall')->SetValue(0);
		Wx::Window::FindWindowByName('info_status_fetch')->SetValue('');
		Wx::Window::FindWindowByName('info_status_signature')->SetValue(0);
		Wx::Window::FindWindowByName('info_status_extract')->SetValue('');
		Wx::Window::FindWindowByName('info_status_created')->SetValue(0);
		Wx::Window::FindWindowByName('info_status_installer_type')->SetValue('');
		Wx::Window::FindWindowByName('info_status_checksums')->SetValue('');
		Wx::Window::FindWindowByName('info_status_checksum_value')->SetValue('');
		Wx::Window::FindWindowByName('info_status_checksum_ok')->SetValue(0);
	}
}

sub _info_get_files{
	my $self=shift;
	my $mod=shift||$self->{thisMod};
	return unless $mod;

	$self->{statusBar}->SetStatusText(_T("Getting File Info..."));
	my $info_files=Wx::Window::FindWindowByName('info_files');
	$info_files->Clear();
	
	my @files=$mod->files();
	my $text=$mod->name._T(" has ").(@files || _T('NO'))._T(" installed files:\n");
	foreach $file (@files){
		$text.="$file\n";
	}
	$text.=_T("There was a problem retrieving the file information for this module.\n").
		("Please see the log for more info.\n") unless @files;
	$info_files->AppendText($text);
	_uShowErr;
}


sub _info_get_info{	
	my $self=shift;
	my $mod=shift||$self->{thisMod};
	#return unless $mod;

	my $info_ctrl=Wx::Window::FindWindowByName('info_tab_text');
	$info_ctrl->Clear();
	$self->{statusBar}->SetStatusText(_T("Getting Info for ").$mod->name."...");

	my $status_info_text='';
	#update info panel
	unless ($mod){
		$info_ctrl->AppendText(_T("No Information Found!"));
	}else{
		my $info=$mod->details();
	 	$status_info_text.=_T("\tAuthor\t\t\t\t").$info->{'Author'}."\n" if $info->{'Author'};
	 	$status_info_text.=_T("\tDescription\t\t\t").$info->{'Description'}."\n" if $info->{'Description'};
	 	$status_info_text.=_T("\tIs Perl Core?\t\t\t").($mod->package_is_perl_core()?_T('Yes'):_T('No'))."\n";
	 	$status_info_text.=_T("\tDevelopment Stage\t").$info->{'Development Stage'}."\n" if $info->{'Development Stage'};
	 	$status_info_text.=_T("\tInstalled File\t\t\t").$info->{'Installed File'}."\n" if $info->{'Installed File'};
	 	$status_info_text.=_T("\tInterface Style\t\t").$info->{'Interface Style'}."\n" if $info->{'Interface Style'};
	  	$status_info_text.=_T("\tLanguage Used\t\t").$info->{'Language Used'}."\n" if $info->{'Language Used'};
	 	$status_info_text.=_T("\tPackage\t\t\t\t").$info->{'Package'}."\n" if $info->{'Package'};
	 	$status_info_text.=_T("\tPublic License\t\t").$info->{'Public License'}."\n" if $info->{'Public License'};
	 	$status_info_text.=_T("\tSupport Level\t\t").$info->{'Support Level'}."\n" if $info->{'Support Level'};
	 	$status_info_text.=_T("\tVersion Installed\t\t").$info->{'Version Installed'}."\n" if $info->{'Version Installed'};
	 	$status_info_text.=_T("\tVersion on CPAN\t\t").$info->{'Version on CPAN'}."\n" if $info->{'Version on CPAN'};
		$status_info_text.=_T("\tComment\t\t\t").($mod->comment || 'N/A')."\n";
		$status_info_text.=_T("\tPath On Mirror\t\t").($mod->path || 'N/A')."\n";
		$status_info_text.=_T("\tdslip\t\t\t\t").($mod->dslip || 'N/A')."\n";
		$status_info_text.=_T("\tIs Bundle?\t\t\t").($mod->is_bundle()?_T('Yes'):_T('No'))."\n";
		#third-party information
		$status_info_text.=_T("\tThird-Party?\t\t\t").($mod->is_third_party()?_T('Yes'):_T('No'))."\n";
	    if ($mod->is_third_party()) {
	        my $info = $self->{cpan}->module_information($mod->name);
	        $status_info_text.=
	              _T("\t\tIncluded In\t\t").$info->{name}."\n".
	              _T("\t\tModule URI\t").$info->{url}."\n".
	              _T("\t\tAuthor\t\t\t").$info->{author}."\n".
	              _T("\t\tAuthor URI\t").$info->{author_url}."\n";
	    }
	    $info_ctrl->AppendText($status_info_text);
		$info_ctrl->ShowPosition(0);
	}	
	$self->{statusBar}->SetStatusText('');
	_uShowErr;

	
}
sub _info_get_versions{	
	my $self=shift;
	my $mod=shift||$self->{thisMod};
	return unless $mod;

	$self->{statusBar}->SetStatusText(_T("Getting Version Info for ").$mod->name."...");
	my $versionList=Wx::Window::FindWindowByName('info_distributions');
	$versionList->Clear();

	my @versions=();
	foreach $m ($mod->distributions()){
		my $v=($m->version || 0.0) if $m;
		push(@versions,$v) unless (grep(/$v/,@versions));
	}
	@versions=sort(@versions);
	my $numInList=@versions;
	$versionList->Append($_) foreach (@versions);
	$versionList->SetValue($versions[-1]);
	#$versionList->SetFirstItem($numInList);
	
	_uShowErr;
}

#get installer status info
#TODO Make this work! Store status info after build into file
#Update the status tab
sub _info_get_status{
	my $self=shift;
	my $mod=shift||$self->{thisMod};
	return unless $mod;
	Wx::LogMessage _T("Getting status for ").$mod->name."...";

	#get status from module
	my $status=$mod->status();

	#if we haven't retrieved the file and the stored info exists
	#then use the stored values
	my $statFile=File::Spec->catfile($ENV{'HOME'},'.cpanplus','status.stored');
	if (!defined($status->fetch) && -e $statFile && (my $Allstatus=retrieve($statFile)) ){
		$thisStat=$Allstatus->{$mod->name};
		$status=$thisStat if $Allstatus->{$mod->name};
	}
	#print Dumper $status;
	Wx::Window::FindWindowByName('info_status_installed')->SetValue($status->installed || 0);
	Wx::Window::FindWindowByName('info_status_uninstall')->SetValue($status->uninstall || 0);
	Wx::Window::FindWindowByName('info_status_fetch')->SetValue($status->fetch||'n/a');
	Wx::Window::FindWindowByName('info_status_signature')->SetValue($status->signature||0);
	Wx::Window::FindWindowByName('info_status_extract')->SetValue($status->extract||'n/a');
	Wx::Window::FindWindowByName('info_status_created')->SetValue($status->created||0);
	Wx::Window::FindWindowByName('info_status_installer_type')->SetValue($status->installer_type||'n/a');
	Wx::Window::FindWindowByName('info_status_checksums')->SetValue($status->checksums || 'n/a');
	Wx::Window::FindWindowByName('info_status_checksum_value')->SetValue($status->checksum_value||'n/a');
	Wx::Window::FindWindowByName('info_status_checksum_ok')->SetValue($status->checksum_ok || 0);
	_uShowErr;
	
}

#get the readme file
sub _info_get_readme{
	my $self=shift;
	my $mod=shift||$self->{thisMod};
	return unless $mod;
	my $info_readme=Wx::Window::FindWindowByName('info_readme');
	$info_readme->Clear();
	$info_readme->AppendText($mod->readme);
	$info_readme->ShowPosition(0);
	_uShowErr;
}

sub _info_get_contents{
	my $self=shift;
	my $mod=shift||$self->{thisMod};
	return unless $mod;
	my $info_contents=Wx::Window::FindWindowByName('info_contents');
	$info_contents->Clear();
	my $txt='';
	foreach $m (sort {lc($a->name) cmp lc($b->name)} $mod->contains() ){
		$txt.=$m->name."\n";
	}
	$info_contents->AppendText($txt);
	$info_contents->ShowPosition(0); #set visible position to beginning
	_uShowErr;
}
sub _info_get_validate{
	my $self=shift;
	my $mod=shift||$self->{thisMod};
	return unless $mod;
	my $display=Wx::Window::FindWindowByName('info_validate');
	$display->Clear();
	my $txt='';
	foreach $file (sort($mod->validate) ){
		$txt.=$file."\n";
	}
	$display->AppendText( ($txt || _T("No Missing Files or No Information. See Log.")) );
	$display->ShowPosition(0); #set visible position to beginning
	_uShowErr;
}


sub _info_get_report_all{
	my $self=shift;
	my $mod=shift||$self->{thisMod};
	return unless $mod;
	my $info_report=Wx::Window::FindWindowByName('info_report');
	$info_report->DeleteAllItems();
	
	#set up the listctrl
	unless ($info_report->GetColumnCount == 3){
		while ($info_report->GetColumnCount){
			$info_report->DeleteColumn(0);
		}
		$info_report->InsertColumn( 0, _T('Distribution'));
		$info_report->InsertColumn( 1, _T('Platform') );
		$info_report->InsertColumn( 2, _T('Grade') );		
	}
	my @versions=$mod->fetch_report(all_versions => 1, verbose => 1);
	@versions=reverse(sort { lc($a->{platform}) cmp lc($b->{platform})} @versions);
#	print Dumper $versions[0];
	foreach $item (@versions ){
		$info_report->InsertStringItem( 0, $item->{'dist'} );
		$info_report->SetItem( 0, 1, $item->{'platform'} );
		$info_report->SetItem( 0, 2, $item->{'grade'} );
	}
	$info_report->SetColumnWidth(0,wxLIST_AUTOSIZE);
	$info_report->SetColumnWidth(1,wxLIST_AUTOSIZE);
	$info_report->SetColumnWidth(2,wxLIST_AUTOSIZE);
	_uShowErr;
}
sub _info_get_report_this{
	my $self=shift;
	my $mod=shift||$self->{thisMod};
	return unless $mod;
	my $info_report=Wx::Window::FindWindowByName('info_report');
	$info_report->DeleteAllItems();
	
	#set up the listctrl
	unless ($info_report->GetColumnCount == 3){
		while ($info_report->GetColumnCount){
			$info_report->DeleteColumn(0);
		}
		$info_report->InsertColumn( 0, _T('Distribution') );
		$info_report->InsertColumn( 1, _T('Platform') );
		$info_report->InsertColumn( 2, _T('Grade') );		
	}
	
	my @versions=$mod->fetch_report(all_versions => 0, verbose => 1);
	@versions=reverse(sort { lc($a->{platform}) cmp lc($b->{platform})} @versions);
	foreach $item (@versions ){
		$info_report->InsertStringItem( 0, $item->{'dist'} );
		$info_report->SetItem( 0, 1, $item->{'platform'} );
		$info_report->SetItem( 0, 2, $item->{'grade'} );
	}
	$info_report->SetColumnWidth(0,wxLIST_AUTOSIZE);
	$info_report->SetColumnWidth(1,wxLIST_AUTOSIZE);
	$info_report->SetColumnWidth(2,wxLIST_AUTOSIZE);
	_uShowErr;
}

###############################
######## Module Actions #######
###############################
sub _install_module{
	my $self=shift;
	my $mod=shift||$self->{thisMod};
	my $version=shift||'';
	return unless $mod;

	#if no version supplied, check version list in Actions tab
	unless ($version){
		my $versionList=Wx::Window::FindWindowByName('info_distributions');
		$version=$versionList->GetValue() || '';
	}
	my $fullname=$mod->name.'-'.$version;
	$self->{statusBar}->SetStatusText(_T("Installing ").$fullname."...");
	
	#$mod=$self->{cpan}->parse_module(module => $mod->name.'-'.$version) if $version;
#	print Dumper $mod;
	$self->_install_with_prereqs($mod->name,$version);

	_uShowErr;
}

sub _install_with_prereqs{
	my $self=shift;
	my $modName=shift;
	return unless $modName;
	my $version=shift||'';
	my @prereqs=$self->CheckPrerequisites($modName,$version);
	#print Dumper @prereqs;
	unshift (@prereqs,$modName.($version?"-$version":''));
	my @mods=();			#$self->{cpan}->module_tree(reverse(@prereqs));
	foreach $n (reverse(@prereqs)){
		push @mods, $self->{cpan}->parse_module(module=>$n);
	}

	#print Dumper @mods;
	my $curMod;
	my $isSuccess=1;
	foreach $mod (@mods){
		$curMod=$mod;
		unless ($self->_fetch_module($mod)){$isSuccess=0;last;}
		unless ($self->_extract_module($mod)){$isSuccess=0;last;}
		unless ($self->_prepare_module($mod)){$isSuccess=0;last;}
		unless ($self->_create_module($mod)){$isSuccess=0;last;}
		unless ($self->_test_module($mod)){$isSuccess=0;last;}
		$self->{statusBar}->SetStatusText(_T('Installing ').$mod->name);
		unless ($mod->install){$isSuccess=0;last;}
		$self->{statusBar}->SetStatusText(_T('Successfully installed ').$mod->name);
	}
	#store status info and populate status tab
	$self->_store_status(@mods);
	$self->_info_get_status();

	unless ($isSuccess){
		$self->{statusBar}->SetStatusText(_T('Failed to install ').$curMod->name._T(". Please Check Log."));
		Wx::MessageBox(_T("Failed to install ").$curMod->name._T("\nCheck Log for more information."));
		return 0;
	}
	
	_uShowErr;
	return 1;
}

sub _store_status{
	my $self=shift;
	my @mods=@_;
	my $status={};
	my $file=File::Spec->catfile($ENV{'HOME'},'.cpanplus','status.stored');
	$status=retrieve($file) if (-e $file);
	foreach $mod (@mods){
		$status->{$mod->name}=$mod->status();
	}
	store $status, $file;
}
sub _fetch_module{
	my $self=shift;
	my $mod=shift || $self->{thisMod};
	$mod = $self->{cpan}->parse_module(module=>$mod) unless ($mod->isa('CPANPLUS::Module') || $mod->isa('CPANPLUS::Module::Fake'));
	return unless $mod;
	#print Dumper $mod;
	$self->{statusBar}->SetStatusText(_T('Fetching ').$mod->{'package'});
	my $path=$mod->fetch();
	return 0 unless $path;
	_uShowErr;
	return 1;
}

sub _extract_module{
	my $self=shift;
	my $mod=shift || $self->{thisMod};
	$mod = $self->{cpan}->parse_module(module=>$mod) unless ($mod->isa('CPANPLUS::Module') || $mod->isa('CPANPLUS::Module::Fake'));
	return unless $mod;
	$self->{statusBar}->SetStatusText(_T('Extracting ').$mod->name);
	my $path=$mod->extract();
	return 0 unless $path;
	_uShowErr;
	return 1;
}
sub _prepare_module{
	my $self=shift;
	my $mod=shift || $self->{thisMod};
	$mod = $self->{cpan}->parse_module(module=>$mod) unless ($mod->isa('CPANPLUS::Module') || $mod->isa('CPANPLUS::Module::Fake'));
	return unless $mod;
	$self->{statusBar}->SetStatusText(_T('Preparing ').$mod->name);
	my $path=$mod->prepare();
	return 0 unless $path;
	_uShowErr;
	return 1;
}

sub _create_module{
	my $self=shift;
	my $mod=shift || $self->{thisMod};
	$mod = $self->{cpan}->parse_module(module=>$mod) unless ($mod->isa('CPANPLUS::Module') || $mod->isa('CPANPLUS::Module::Fake'));
	return unless $mod;
	$self->{statusBar}->SetStatusText(_T('Building ').$mod->name);
	my $path=$mod->create();
	return 0 unless $path;
	_uShowErr;
	return 1;
}
sub _test_module{
	my $self=shift;
	my $mod=shift || $self->{thisMod};
	$mod = $self->{cpan}->parse_module(module=>$mod) unless ($mod->isa('CPANPLUS::Module') || $mod->isa('CPANPLUS::Module::Fake'));
	return unless $mod;
	$self->{statusBar}->SetStatusText(_T('Testing ').$mod->name);
	my $path=$mod->test();
	return 0 unless $path;
	_uShowErr;
	return 1;
}
#populates the list with the tree items
#This function takes a tree hash, and optionally a progressdialog or bar
# and the max value of the progress bar 
#return 1 on success, or 0 if the user cancelled
# call like:
#$user_has_cancelled = $self->PopulateWithHash(\%tree,[$progress],[$max_pval]);
sub PopulateWithHash{
	#get parameters
	my $self=shift;
	my $tree=shift;
	my $progress=shift;	
	my $max_progress=shift;

	print "Window Height: ".$self->GetClientSize()->GetWidth." , ".$self->GetClientSize()->GetHeight."\n";
	
	#set defaults.
	#Use half the number of items in the hash as a total items count, if none given
	my $numFound=$tree->{'_items_in_tree_'} || %$tree/2;
	$max_progress=($numFound || 10000) unless $max_progress;
	
	#create a progressdialog if none specified in params
	$progress=Wx::ProgressDialog->new(_T("Setting Up List..."),
				_T("Inserting ").$numFound._T(" Items Into Tree..."),
				$numFound,$self,wxPD_APP_MODAL|wxPD_CAN_ABORT|wxPD_ESTIMATED_TIME|wxPD_REMAINING_TIME 
				) unless $progress;	
	
	#start timing
	$begin=time();
	
	#restart count if another progressdialog is passeed in
	$progress->Update(0,_T("Inserting ").$numFound._T(" Items Into Tree...")); 
	my $percent=$max_progress/$numFound;
	$cnt=0;
  
	foreach $top_level ( sort( keys(%$tree) ) ){
		next if $top_level eq '_items_in_tree_';
		my $curParent=$self->AppendItem(
			$self->GetRootItem(),
			$top_level,$self->_get_status_icon($top_level));
		foreach $item (sort(@{$tree->{$top_level}})){
			$self->AppendItem($curParent,$item,$self->_get_status_icon($item)) if ($curParent && $item);
			last unless $progress->Update($cnt*$percent);
			$cnt++;
		}
	}
#	$progress->Update($numFound+1);
	$progress->Destroy();
	my $inserted_time=time()-$begin;
	Wx::LogMessage _T("Finished Inserting in ").sprintf("%d",($inserted_time/60)).":".($inserted_time % 60)."\n";
	
	print "Window Height: ".$self->GetClientSize()->GetWidth." , ".$self->GetClientSize()->GetHeight."\n";
	_uShowErr;
	return 1;
}

###############################
######## New By Name ##########
###############################
sub _show_new_by_name{
	my $self=shift;
	if ($self->{'tree_NewByName'}){
		return 0 unless $self->PopulateWithHash($self->{'tree_NewByName'});
		Wx::LogMessage _T("[Done]");
		return 1;
	}	
	my %tree=();
	my $max_pval=10000;  #the maximum value of the progress bar
	my $progress=Wx::ProgressDialog->new(_T("Setting Up List..."),
				_T("CPANPLUS is getting information..."),
				$max_pval,
				$self,
				wxPD_APP_MODAL|wxPD_CAN_ABORT|wxPD_ESTIMATED_TIME|wxPD_REMAINING_TIME);
	my %allMods=%{$self->{cpan}->module_tree()}; #get all modules
	my $total=keys(%allMods);
	my $percent=$max_pval/($total||1); #number to increment progress by
	my $begin=time(); #for timing loops
	my $cnt=0;  #the count of current index of @allMods - for progressbar
	my $numFound=0;
	
	$progress->Update(0,_T("Step 1 of 2: Sorting All ").$total._T(" Modules...")); #start actual progress
	
	#search through installed modules and insert them into the correct category
	foreach $thisName (keys(%allMods)){
		my $i=$allMods{$thisName};
		if (!($i->is_uptodate || $i->installed_version)){
			my ($top_level)=split('::',$thisName);
			push (@{$tree{$top_level}}, ($thisName eq $top_level)?():$thisName); #add the item to the tree
			$numFound++;
		}
		unless ($progress->Update($cnt*$percent)){
			$progress->Destroy();
			return 0;
		}
		$cnt++; #increment current index in @installed
	}
	#end timing method
	my $end=time();
	Wx::LogMessage _T("Finished Sorting in ").sprintf("%d",(($end-$begin)/60)).":".(($end-$begin) % 60)."\n";

	#store tree for later use
	$tree{'_items_in_tree_'}=$numFound;
	$self->{'tree_NewByName'}=\%tree;
	
	#populate the TreeCtrl
	return 0 unless $self->PopulateWithHash(\%tree,$progress,$max_pval);

	Wx::LogMessage _T("[Done]");
	_uShowErr;
	return 1;	
}
###############################
######## New By Author ########
###############################
sub _show_new_by_author{
	my $self=shift;
	if ($self->{'tree_NewByAuthor'}){
		return 0 unless $self->PopulateWithHash($self->{'tree_NewByAuthor'});
		Wx::LogMessage _T("[Done]");
		return 1;
	}	
	my %tree=();
	my $max_pval=10000;  #the maximum value of the progress bar
	my $progress=Wx::ProgressDialog->new(_T("Setting Up List..."),
				_T("CPANPLUS is getting information..."),
				$max_pval,
				$self,
				wxPD_APP_MODAL|wxPD_CAN_ABORT|wxPD_ESTIMATED_TIME|wxPD_REMAINING_TIME);
	my %allMods=%{$self->{cpan}->module_tree()}; #get all modules
	my $total=keys(%allMods);
	my $percent=$max_pval/($total||1); #number to increment progress by
	my $begin=time(); #for timing loops
	my $cnt=0;  #the count of current index of @allMods - for progressbar
	$numFound=0;

	$progress->Update(0,_T("Step 1 of 2: Categorizing All ").$total._T(" Modules...")); #start actual progress
	
	#search through installed modules and insert them into the correct category
	foreach $thisName (keys(%allMods)){
		my $i=$allMods{$thisName};
		if (!($i->is_uptodate || $i->installed_version)){
			my $thisAuthor=$i->author()->cpanid." [".$i->author()->author."]";
			my $cat_num=$self->{category_list}->{$thisName};
			push (@{$tree{$thisAuthor}}, $thisName); #add the item to the tree
			$numFound++;
		}
		unless ($progress->Update($cnt*$percent)){
			$progress->Destroy();
			return 0;
		}
		$cnt++; #increment current index in @installed
	}
	#end timing method
	my $end=time();
	Wx::LogMessage _T("Finished Sorting in ").sprintf("%d",(($end-$begin)/60)).":".(($end-$begin) % 60)."\n";

	#store tree for later use
	$tree{'_items_in_tree_'}=$numFound;
	$self->{'tree_NewByAuthor'}=\%tree;
	
	#populate the TreeCtrl
	return 0 unless $self->PopulateWithHash(\%tree,$progress,$max_pval);

	Wx::LogMessage _T("[Done]");
	_uShowErr;
	return 1;	
}

###############################
######## New By Category ######
###############################
sub _show_new_by_category{
	my $self=shift;
	if ($self->{'tree_NewByCategory'}){
		return 0 unless $self->PopulateWithHash($self->{'tree_NewByCategory'});
		Wx::LogMessage _T("[Done]");
		return 1;
	}	
	my $max_pval=10000;  #the maximum value of the progress bar
	my $progress=Wx::ProgressDialog->new(_T("Setting Up List..."),
				_T("CPANPLUS is getting information..."),$max_pval,$self,
				wxPD_APP_MODAL|wxPD_CAN_ABORT|wxPD_ESTIMATED_TIME|wxPD_REMAINING_TIME);

	my %allMods=%{$self->{cpan}->module_tree()}; #get all modules
	my $total=keys(%allMods);
	my $percent=$max_pval/($total||1); #number to increment progress by
	my $begin=time(); #for timing loops
	my $cnt=0;  #the count of current index of @allMods - for progressbar
	$numFound=0;

	$progress->Update(0,_T("Step 1 of 2: Categorizing All ").$total.(" Modules...")); #start actual progress

	#search through installed modules and insert them into the correct category
	foreach $thisName (keys(%allMods)){
		my $i=$allMods{$thisName};
		my $cat_num=$self->{category_list}->{$thisName};
		if (defined($cat_num) && !($i->is_uptodate || $i->installed_version)){
			$cat_num=0 if ($cat_num==99); #don't use index 99, it make array too large
			$cat_num=1 if ($i->module_is_supplied_with_perl_core() && $cat_num==2);
			push (@{$tree{$self->{catNames}->[$cat_num]}}, $thisName); #add the item to the tree
			$numFound++;
		}
		unless ($progress->Update($cnt*$percent)){
			$progress->Destroy();
			return 0;
		}
		$cnt++; #increment current index in @installed
	}
	
	#end timing method
	my $end=time();
	Wx::LogMessage _T("Finished Sorting in ").sprintf("%d",(($end-$begin)/60)).":".(($end-$begin) % 60)."\n";

	#store tree for later use
	$tree{'_items_in_tree_'}=$numFound;
	$self->{'tree_NewByCategory'}=\%tree;
	
	#populate the TreeCtrl
	return 0 unless $self->PopulateWithHash(\%tree,$progress,$max_pval);

	Wx::LogMessage _T("[Done]");
	_uShowErr;
	return 1;	
}

###############################
######## All By Name ##########
###############################
sub _show_all_by_name{
	my $self=shift;
	if ($self->{'tree_AllByName'}){
		return 0 unless $self->PopulateWithHash($self->{'tree_AllByName'});
		Wx::LogMessage _T("[Done]");
		return 1;
	}	
	my %tree=();
	my $max_pval=10000;  #the maximum value of the progress bar
	my $progress=Wx::ProgressDialog->new(_T("Setting Up List..."),
				_T("CPANPLUS is getting information..."),
				$max_pval,
				$self,
				wxPD_APP_MODAL|wxPD_CAN_ABORT|wxPD_ESTIMATED_TIME|wxPD_REMAINING_TIME);
	my %allMods=%{$self->{cpan}->module_tree()}; #get all modules
	my $total=keys(%allMods);
	my $percent=$max_pval/($total||1); #number to increment progress by
	my $begin=time(); #for timing loops
	my $cnt=0;  #the count of current index of @allMods - for progressbar

	$progress->Update(0,_T("Step 1 of 2: Sorting All ").$total._T(" Modules...")); #start actual progress
	
	#search through installed modules and insert them into the correct category
	foreach $thisName (keys(%allMods)){
		my $i=$allMods{$thisName};
		my ($top_level)=split('::',$thisName);
		push (@{$tree{$top_level}}, ($thisName eq $top_level)?():$thisName); #add the item to the tree
		unless ($progress->Update($cnt*$percent)){
			$progress->Destroy();
			return 0;
		}
		$cnt++; #increment current index in @installed
	}
	#end timing method
	my $end=time();
	Wx::LogMessage _T("Finished Sorting in ").sprintf("%d",(($end-$begin)/60)).":".(($end-$begin) % 60)."\n";

	#store tree for later use
	$tree{'_items_in_tree_'}=$total;
	$self->{'tree_AllByName'}=\%tree;
	
	#populate the TreeCtrl
	return 0 unless $self->PopulateWithHash(\%tree,$progress,$max_pval);

	Wx::LogMessage _T("[Done]");
	_uShowErr;
	return 1;	
}

###############################
######## All By Author ########
###############################
sub _show_all_by_author{
	my $self=shift;
	if ($self->{'tree_AllByAuthor'}){
		return 0 unless $self->PopulateWithHash($self->{'tree_AllByAuthor'});
		Wx::LogMessage _T("[Done]");
		return 1;
	}	
	my %tree=();
	my $max_pval=10000;  #the maximum value of the progress bar
	my $progress=Wx::ProgressDialog->new(_T("Setting Up List..."),
				_T("CPANPLUS is getting information..."),
				$max_pval,
				$self,
				wxPD_APP_MODAL|wxPD_CAN_ABORT|wxPD_ESTIMATED_TIME|wxPD_REMAINING_TIME);
	my %allMods=%{$self->{cpan}->module_tree()}; #get all modules
	my $total=keys(%allMods);
	my $percent=$max_pval/($total||1); #number to increment progress by
	my $begin=time(); #for timing loops
	my $cnt=0;  #the count of current index of @allMods - for progressbar

	$progress->Update(0,_T("Step 1 of 2: Categorizing All ").$total._T(" Modules...")); #start actual progress
	
	#search through installed modules and insert them into the correct category
	foreach $thisName (keys(%allMods)){
		my $i=$allMods{$thisName};
		my $thisAuthor=$i->author()->cpanid." [".$i->author()->author."]";
		my $cat_num=$self->{category_list}->{$thisName};
		push (@{$tree{$thisAuthor}}, $thisName); #add the item to the tree
		unless ($progress->Update($cnt*$percent)){
			$progress->Destroy();
			return 0;
		}
		$cnt++; #increment current index in @installed
	}
	#end timing method
	my $end=time();
	Wx::LogMessage _T("Finished Sorting in ").sprintf("%d",(($end-$begin)/60)).":".(($end-$begin) % 60)."\n";

	#store tree for later use
	$tree{'_items_in_tree_'}=$total;
	$self->{'tree_AllByAuthor'}=\%tree;
	
	#populate the TreeCtrl
	return 0 unless $self->PopulateWithHash(\%tree,$progress,$max_pval);

	Wx::LogMessage _T("[Done]");
	_uShowErr;
	return 1;	
}

###############################
###### All By Category ########
###############################
sub _show_all_by_category{
	my $self=shift;
	if ($self->{'tree_AllByCategory'}){
		return 0 unless $self->PopulateWithHash($self->{'tree_AllByCategory'});
		Wx::LogMessage _T("[Done]");
		return 1;
	}	
	my $max_pval=10000;  #the maximum value of the progress bar
	my $progress=Wx::ProgressDialog->new(_T("Setting Up List..."),
				_T("CPANPLUS is getting information..."),$max_pval,$self,
				wxPD_APP_MODAL|wxPD_CAN_ABORT|wxPD_ESTIMATED_TIME|wxPD_REMAINING_TIME);

	my %allMods=%{$self->{cpan}->module_tree()}; #get all modules
	my $total=keys(%allMods);
	my $percent=$max_pval/($total||1); #number to increment progress by
	my $begin=time(); #for timing loops
	my $cnt=0;  #the count of current index of @allMods - for progressbar

	$progress->Update(0,_T("Step 1 of 2: Categorizing All ").$total._T(" Modules...")); #start actual progress

	#search through installed modules and insert them into the correct category
	foreach $thisName (keys(%allMods)){
		my $i=$allMods{$thisName};
		my $cat_num=$self->{category_list}->{$thisName};
		if (defined($cat_num)){
			$cat_num=0 if ($cat_num==99); #don't use index 99, it make array too large
			$cat_num=1 if ($i->module_is_supplied_with_perl_core() && $cat_num==2);
			push (@{$tree{$self->{catNames}->[$cat_num]}}, $thisName); #add the item to the tree
		}
		unless ($progress->Update($cnt*$percent)){
			$progress->Destroy();
			return 0;
		}
		$cnt++; #increment current index in @installed
	}
	
	#end timing method
	my $end=time();
	Wx::LogMessage _T("Finished Sorting in ").sprintf("%d",(($end-$begin)/60)).":".(($end-$begin) % 60)."\n";

	#store tree for later use
	$tree{'_items_in_tree_'}=$total;
	$self->{'tree_AllByCategory'}=\%tree;
	
	#populate the TreeCtrl
	return 0 unless $self->PopulateWithHash(\%tree,$progress,$max_pval);

	Wx::LogMessage _T("[Done]");
	$progress->Destroy();
	_uShowErr;
	return 1;	
}


sub _show_updates_by_category{
	my $self=shift;
	if ($self->{'tree_UpdatesByCategory'}){
		return 0 unless $self->PopulateWithHash($self->{'tree_UpdatesByCategory'});
		Wx::LogMessage _T("[Done]");
		return 1;
	}	
	my $max_pval=10000;  #the maximum value of the progress bar
	my $progress=Wx::ProgressDialog->new(_T("Setting Up List..."),
				_T("CPANPLUS is getting information..."),$max_pval,$self,
				wxPD_APP_MODAL|wxPD_CAN_ABORT|wxPD_ESTIMATED_TIME|wxPD_REMAINING_TIME);

	my @installed=$self->{cpan}->installed(); #get installed modules
	my $percent=$max_pval/@installed; #number to increment progress by
	my $begin=time(); #for timing loops
	my $cnt=0;  #the count of current index of @installed - for progressbar
	my $numFound=0; #the number of modules that match CPAN to CPANPLUS::Installed
	$progress->Update(0,_T("Step 1 of 2: Categorizing ").@installed._T(" Installed Modules...")); #start actual progress

	#search through installed modules and insert them into the correct category
	foreach $i (@installed){
		unless ($i->is_uptodate()){
			my $thisName=$i->name;
			my $cat_num=$self->{category_list}->{$thisName};
			if (defined($cat_num)){
				$cat_num=0 if ($cat_num==99); #don't use index 99, it make array too large
				$cat_num=1 if ($i->module_is_supplied_with_perl_core() && $cat_num==2);
				push (@{$tree{$self->{catNames}->[$cat_num]}}, $thisName); #add the item to the tree
				$numFound++; #increment the number of items that matched
			}
		}
		unless ($progress->Update($cnt*$percent)){
			$progress->Destroy();
			return 0;
		}
		$cnt++; #increment current index in @installed
	}
	
	#end timing method
	my $end=time();
	Wx::LogMessage _T("Finished Sorting in ").sprintf("%d",(($end-$begin)/60)).":".(($end-$begin) % 60)."\n";

	#store tree for later use
	$tree{'_items_in_tree_'}=$numFound;
	$self->{'tree_UpdatesByCategory'}=\%tree;
	
	#populate the TreeCtrl
	return 0 unless $self->PopulateWithHash(\%tree,$progress,$max_pval);

	Wx::LogMessage _T("[Done]");
	$progress->Destroy();
	_uShowErr;
	return 1;	
}

sub _show_updates_by_author{
	my $self=shift;
	if ($self->{'tree_UpdatesByAuthor'}){
		return 0 unless $self->PopulateWithHash($self->{'tree_UpdatesByAuthor'});
		Wx::LogMessage _T("[Done]");
		return 1;
	}	
	my %tree=();
	my $max_pval=10000;  #the maximum value of the progress bar
	my $progress=Wx::ProgressDialog->new(_T("Setting Up List..."),
				_T("CPANPLUS is getting information..."),
				$max_pval,
				$self,
				wxPD_APP_MODAL|wxPD_CAN_ABORT|wxPD_ESTIMATED_TIME|wxPD_REMAINING_TIME);
	my @installed=$self->{cpan}->installed(); #get installed modules
	my $percent=$max_pval/@installed; #number to increment progress by
	my $begin=time(); #for timing loops
	my $cnt=0;  #the count of current index of @installed - for progressbar
	my $numFound=0; #the number of modules that match CPAN to CPANPLUS::Installed
	$progress->Update(0,_T("Step 1 of 2: Sorting ").@installed." Installed Modules..."); #start actual progress
	
	#search through installed modules and insert them into the correct category
	foreach $i (@installed){
		unless ($i->is_uptodate()){
			my $thisName=$i->name;
			my $thisAuthor=$i->author()->cpanid." [".$i->author()->author."]";
			my $cat_num=$self->{category_list}->{$thisName};
			push (@{$tree{$thisAuthor}}, $thisName); #add the item to the tree
		}
		unless ($progress->Update($cnt*$percent)){
			$progress->Destroy();
			return 0;
		}
		$cnt++; #increment current index in @installed
	}
	#end timing method
	my $end=time();
	Wx::LogMessage _T("Finished Sorting in ").sprintf("%d",(($end-$begin)/60)).":".(($end-$begin) % 60)."\n";

	#store tree for later use
	$tree{'_items_in_tree_'}=$numFound;
	$self->{'tree_UpdatesByAuthor'}=\%tree;
	
	#populate the TreeCtrl
	return 0 unless $self->PopulateWithHash(\%tree,$progress,$max_pval);

	Wx::LogMessage _T("[Done]");
	$progress->Destroy();
	_uShowErr;
	return 1;	
}


sub _show_updates_by_name{
	my $self=shift;
	if ($self->{'tree_UpdatesByName'}){
		return 0 unless $self->PopulateWithHash($self->{'tree_UpdatesByName'});
		Wx::LogMessage _T("[Done]");
		return 1;
	}	
	my %tree=();
	my $max_pval=10000;  #the maximum value of the progress bar
	my $progress=Wx::ProgressDialog->new(_T("Setting Up List..."),
				_T("CPANPLUS is getting information..."),
				$max_pval,
				$self,
				wxPD_APP_MODAL|wxPD_CAN_ABORT|wxPD_ESTIMATED_TIME|wxPD_REMAINING_TIME);
	my @installed=$self->{cpan}->installed(); #get installed modules
	my $percent=$max_pval/@installed; #number to increment progress by
	my $begin=time(); #for timing loops
	my $cnt=0;  #the count of current index of @installed - for progressbar
	my $numFound=0; #the number of modules that match CPAN to CPANPLUS::Installed
	$progress->Update(0,_T("Step 1 of 2: Sorting ").@installed." Installed Modules..."); #start actual progress
	
	#search through installed modules and insert them into the correct category
	foreach $i (@installed){
		unless ($i->is_uptodate()){
			my $thisName=$i->name;
			my ($top_level)=split('::',$thisName);
			push (@{$tree{$top_level}}, ($thisName eq $top_level)?():$thisName); #add the item to the tree
		}
		unless ($progress->Update($cnt*$percent)){
			$progress->Destroy();
			return 0;
		}
		$cnt++; #increment current index in @installed
	}
	#end timing method
	my $end=time();
	Wx::LogMessage _T("Finished Sorting in ").sprintf("%d",(($end-$begin)/60)).":".(($end-$begin) % 60)."\n";

	#store tree for later use
	$tree{'_items_in_tree_'}=$numFound;
	$self->{'tree_UpdatesByName'}=\%tree;
	
	#populate the TreeCtrl
	return 0 unless $self->PopulateWithHash(\%tree,$progress,$max_pval);

	Wx::LogMessage _T("[Done]");
	$progress->Destroy();
	_uShowErr;
	return 1;	
}


sub _show_installed_by_name{
	my $self=shift;
	if ($self->{'tree_InstalledByName'}){
		return 0 unless $self->PopulateWithHash($self->{'tree_InstalledByName'});
		Wx::LogMessage _T("[Done]");
		return 1;
	}	
	my %tree=();
	my $max_pval=10000;  #the maximum value of the progress bar
	my $progress=Wx::ProgressDialog->new(_T("Setting Up List..."),
				_T("CPANPLUS is getting information..."),
				$max_pval,
				$self,
				wxPD_APP_MODAL|wxPD_CAN_ABORT|wxPD_ESTIMATED_TIME|wxPD_REMAINING_TIME);
	my @installed=$self->{cpan}->installed(); #get installed modules
	my $percent=$max_pval/@installed; #number to increment progress by
	my $begin=time(); #for timing loops
	my $cnt=0;  #the count of current index of @installed - for progressbar
	my $numFound=0; #the number of modules that match CPAN to CPANPLUS::Installed
	$progress->Update(0,_T("Step 1 of 2: Sorting ").@installed._T(" Installed Modules...")); #start actual progress
	
	#search through installed modules and insert them into the correct category
	foreach $i (@installed){
		my $thisName=$i->name;
		my ($top_level)=split('::',$thisName);
		push (@{$tree{$top_level}}, ($thisName eq $top_level)?():$thisName); #add the item to the tree
		unless ($progress->Update($cnt*$percent)){
			$progress->Destroy();
			return 0;
		}
		$cnt++; #increment current index in @installed
	}
	#end timing method
	my $end=time();
	Wx::LogMessage _T("Finished Sorting in ").sprintf("%d",(($end-$begin)/60)).":".(($end-$begin) % 60)."\n";

	#store tree for later use
	$tree{'_items_in_tree_'}=$numFound;
	$self->{'tree_InstalledByName'}=\%tree;
	
	#populate the TreeCtrl
	return 0 unless $self->PopulateWithHash(\%tree,$progress,$max_pval);

	Wx::LogMessage _T("[Done]");
	$progress->Destroy();
	_uShowErr;
	return 1;	
}

#populate tree with installed modules sorted by author id
sub _show_installed_by_author{
	my $self=shift;
	if ($self->{'tree_InstalledByAuthor'}){
		return 0 unless $self->PopulateWithHash($self->{'tree_InstalledByAuthor'});
		Wx::LogMessage _T("[Done]");
		return 1;
	}	
	my %tree=();
	my $max_pval=10000;  #the maximum value of the progress bar
	my $progress=Wx::ProgressDialog->new("Setting Up List...",
				"CPANPLUS is getting information...",
				$max_pval,
				$self,
				wxPD_APP_MODAL|wxPD_CAN_ABORT|wxPD_ESTIMATED_TIME|wxPD_REMAINING_TIME);
	my @installed=$self->{cpan}->installed(); #get installed modules
	my $percent=$max_pval/@installed; #number to increment progress by
	my $begin=time(); #for timing loops
	my $cnt=0;  #the count of current index of @installed - for progressbar
	my $numFound=0; #the number of modules that match CPAN to CPANPLUS::Installed
	$progress->Update(0,_T("Step 1 of 2: Sorting ").@installed._T(" Installed Modules...")); #start actual progress
	
	#search through installed modules and insert them into the correct category
	foreach $i (@installed){
		my $thisName=$i->name;
		my $thisAuthor=$i->author()->cpanid." [".$i->author()->author."]";
		my $cat_num=$self->{category_list}->{$thisName};
		push (@{$tree{$thisAuthor}}, $thisName); #add the item to the tree
		unless ($progress->Update($cnt*$percent)){
			$progress->Destroy();
			return 0;
		}
		$cnt++; #increment current index in @installed
	}
	#end timing method
	my $end=time();
	Wx::LogMessage _T("Finished Sorting in ").sprintf("%d",(($end-$begin)/60)).":".(($end-$begin) % 60)."\n";

	#store tree for later use
	$tree{'_items_in_tree_'}=$numFound;
	$self->{'tree_InstalledByAuthor'}=\%tree;
	
	#populate the TreeCtrl
	return 0 unless $self->PopulateWithHash(\%tree,$progress,$max_pval);

	Wx::LogMessage _T("[Done]");
	$progress->Destroy();
	_uShowErr;
	return 1;	
}

#populate tree with installed modules sorted by category
sub _show_installed_by_category{
	my $self=shift;
	if ($self->{'tree_InstalledByCategory'}){
		return 0 unless $self->PopulateWithHash($self->{'tree_InstalledByCategory'});
		Wx::LogMessage _T("[Done]");
		return 1;
	}	
	my %tree=();
	my $max_pval=10000;  #the maximum value of the progress bar
	my $progress=Wx::ProgressDialog->new(_T("Setting Up List..."),
				_T("CPANPLUS is getting information..."),
				10000,
				$self,
				wxPD_APP_MODAL|wxPD_CAN_ABORT|wxPD_ESTIMATED_TIME|wxPD_REMAINING_TIME);

	my @installed=$self->{cpan}->installed(); #get installed modules
	my $percent=$max_pval/@installed; #number to increment progress by
	my $begin=time(); #for timing loops
	my $cnt=0;  #the count of current index of @installed - for progressbar
	my $numFound=0; #the number of modules that match CPAN to CPANPLUS::Installed
	$progress->Update(0,_T("Step 1 of 2: Categorizing ").@installed._T(" Installed Modules...")); #start actual progress

	#search through installed modules and insert them into the correct category
	foreach $i (@installed){
		my $thisName=$i->name;
		my $cat_num=$self->{category_list}->{$thisName};
		$progress->Update($cnt*$percent);
#			"Step 1 of 2: Categorizing ".@installed." Installed Modules...#$cnt : ".$i->name);
		if (defined($cat_num)){
			$cat_num=0 if ($cat_num==99); #don't use index 99, it make array too large
			$cat_num=1 if ($i->module_is_supplied_with_perl_core() && $cat_num==2);
			push (@{$tree{$self->{catNames}->[$cat_num]}}, $thisName); #add the item to the tree
			$numFound++; #increment the number of items that matched
		}
		unless ($progress->Update($cnt*$percent)){
			$progress->Destroy();
			return 0;
		}
		$cnt++; #increment current index in @installed
	}
	#end timing method
	my $end=time();
	Wx::LogMessage _T("Finished Sorting in ").sprintf("%d",(($end-$begin)/60)).":".(($end-$begin) % 60)."\n";

	#store tree for later use
	$tree{'_items_in_tree_'}=$numFound;
	$self->{'tree_InstalledByCategory'}=\%tree;
	
	#populate the TreeCtrl
	return 0 unless $self->PopulateWithHash(\%tree,$progress,$max_pval);

	Wx::LogMessage _T("[Done]");
	$progress->Destroy();
	_uShowErr;
	return 1;	
	
}

#this returns a referece to a hash, (module_name=>category_number), of all modules
sub _get_categories{
	my $self = shift;

	my $moduleFile= File::Spec->catfile($self->{config}->get_conf('base'),"03modlist.data.gz");
	my $modlistEval;  #the string to evaluate == 03modlist.data.gz 

	#inflate file into $modlistEval
	Wx::LogMessage _T("Getting Category List...Inflating...");
	use IO::Uncompress::AnyInflate qw(anyinflate $AnyInflateError) ;
	anyinflate $moduleFile => \$modlistEval 
        or Wx::LogMessage _T("anyinflate failed: ").$AnyInflateError."\n";
    return unless $modlistEval;
	Wx::LogMessage _T("Successfully Inflated Module Info File!");

	#get rid of file info in header
    $modlistEval=~s/(.*)package CPAN\:\:Modulelist/package CPAN\:\:Modulelist/si ;#get rid of file info

	#create List of Categories
	my $cat_hash=(); #the hash that is stored in the file
	my %categories=(); #the return value of this function
    eval $modlistEval.'$cat_hash=(CPAN::Modulelist->data)[0];';Wx::LogMessage($@) if $@;
   	$categories{$_}=$cat_hash->{$_}->{'chapterid'} foreach (keys(%$cat_hash));

	#return list
    Wx::LogMessage _T("Successfully read Category List!");
	return \%categories;
	_uShowErr;
}

sub search{
	my $self=shift;
	my ($type,@search)=@_;
	$self->{statusBar}->SetStatusText(_T("Searching. Please Wait..."));

	my $progress=Wx::ProgressDialog->new(_T("Setting Up List..."),
				_T("CPANPLUS is getting information..."),
				MAX_PROGRESS_VALUE,
				$self,
				wxPD_APP_MODAL|wxPD_CAN_ABORT|wxPD_ESTIMATED_TIME|wxPD_REMAINING_TIME);

	$self->DeleteChildren($self->GetRootItem());
	foreach $s (@search){
		Wx::LogMessage _T("Searching for: ").$search[0]._T(" by $type\n");
		if ($s=~m|/(.*)/(.*)|){
			#print "Matching Regex...\n";
			eval "\$s=qr/$1/".($2||'');
		}
	}
	$type= lc($type);

	my $mparent=$self->GetRootItem();
	my @names=();
	my $numFound=0;
	my $tmpCnt=1;
	@modules=();
	if ($type eq 'any' || $type eq 'all'){
		my @terms=(CPANPLUS::Module->accessors(),CPANPLUS::Module::Author->accessors());
		my $percent = MAX_PROGRESS_VALUE/@terms;
		my $count=0;
		foreach $term (@terms){
			if ($progress->Update($percent*($count++),_T("Found ").$numFound._T(" items"))){
				my @mods=$self->{cpan}->search(type => $term, allow => \@search);
				push @modules, @mods;
				$numFound+=@mods;
			}else{
				$progress->Destroy();
				return;
			}
		}
	}else{
		@modules=$self->{cpan}->search(type => $type, allow => \@search);
		$numFound=@modules;
		return unless $progress->Update(MAX_PROGRESS_VALUE-1,_T("Found ").$numFound._T(" items"))
	}
	
	#remove duplicates.
	#note: there is a better way, using List::MoreUtils,
	#   but i'm trying to cut back on requirements for wxCPAN
	my $percent = MAX_PROGRESS_VALUE/@modules;
	$count=0;
	my @newmods=();
	foreach $m (@modules){
		return unless $progress->Update($percent*$count,_T("Removing Duplicates..."));
		push(@newmods,$m) unless (grep(($m->name eq $_->name),@newmods));
		$count++;
	}
	@modules=@newmods;
	$numFound=@modules;
	$self->PopulateWithModuleList($progress,$numFound,@modules);
	$progress->Destroy;

	
	Wx::Window::FindWindowByName('module_splitter')->FitInside();
	Wx::Window::FindWindowByName('module_splitter')->UpdateWindowUI(wxUPDATE_UI_RECURSE );

	_uShowErr;
	print "Window Height: ".$self->GetClientSize()->GetWidth." , ".$self->GetClientSize()->GetHeight."\n";
#	print Dumper $self->GetClientSize();
	$self->{statusBar}->SetStatusText('');
}
#this method populates the list with the given module objects.
#if the object is an Author, then get the module names he/she has written
sub PopulateWithModuleList{
	my $self=shift;
	my $progress=shift || Wx::ProgressDialog->new(_T("Please Wait..."),
				_T("Displaying List..."),
				MAX_PROGRESS_VALUE,
				$self,
				wxPD_APP_MODAL|wxPD_CAN_ABORT|wxPD_ESTIMATED_TIME|wxPD_REMAINING_TIME);
	my $totalFound=shift;
	return unless $totalFound;
	my $numFound=$totalFound;
	my @modules=@_;
	my @names=();
	my $count=0;
	my $percent=MAX_PROGRESS_VALUE/$totalFound;
	return unless $progress->Update(0,_T("Getting info for $numFound items."));

	#get information from modules
	foreach $mod (@modules){
		last unless $progress->Update($percent*$count);
		if ($mod->isa('CPANPLUS::Module')){
			push(@names,$mod->name);
		}
		if ($mod->isa('CPANPLUS::Module::Author')){
			foreach $m ($mod->modules()){
				push(@names,$m->name);
			}
		}
		$count++;
	}

	#populate the tree ctrl
	return unless $progress->Update(0,_T("Populating tree with").$totalFound._T(" items.") );
	$count=0;
	foreach $item (sort {lc($a) cmp lc($b)} @names){
		return unless $progress->Update($percent*$count);
		$self->AppendItem($self->GetRootItem(),$item,$self->_get_status_icon($item));
		$count++;
	}
	return 1;
}

#this method returns the index in the imageList for the status of the passed name
sub _get_status_icon{
	my $self=shift;
	my ($name)=@_;
	my $mod=$self->{cpan}->parse_module(module=>$name);
	return $self->{iconList}->{unknown}->{idx} unless $mod;
	return $self->{iconList}->{installed}->{idx} if $mod->is_uptodate();
	return $self->{iconList}->{not_installed}->{idx} if !$mod->installed_version();
	return $self->{iconList}->{update}->{idx};
	
	_uShowErr;
	
}
sub SetImageList{								#must be a Wx::ImageList
	my ($self,$list)=@_;
	$self->{iconList}=$list;
	$self->AssignImageList($list->{imageList});
}

########################################
########### Context Menu ##############
########################################


#the following methods are for setting the event handlers for the various 
# menu items in the context menu. They all take one parameter:a code ref
#The code ref is then executed with three parameters: 
# the menu [Wx::Menu], the event [Wx::CommandEvent], and the name of the selected module 
sub SetInfoHandler{$_[0]->{_minfoHandler}=$_[1];}
sub SetInstallMenuHandler{$_[0]->{_minstallHandler}=$_[1];}
sub SetUpdateMenuHandler{$_[0]->{_mupdateHandler}=$_[1];}
sub SetUninstallMenuHandler{$_[0]->{_muninstallHandler}=$_[1];}
sub SetFetchMenuHandler{$_[0]->{_mfetchHandler}=$_[1];}
sub SetPrepareMenuHandler{$_[0]->{_mprepareHandler}=$_[1];}
sub SetBuildMenuHandler{$_[0]->{_mbuildHandler}=$_[1];}
sub SetTestMenuHandler{$_[0]->{_mtestHandler}=$_[1];}
sub SetExtractMenuHandler{$_[0]->{_mextractHandler}=$_[1];}
sub SetSelectHandler{$_[0]->{_selectHandler}=$_[1];}
sub SetDblClickHandler{$_[0]->{_dblClickHandler}=$_[1];}

sub GetInfo{
	my ($menu,$cmd_event,$modName)=@_;
	my $modtree=Wx::Window::FindWindowByName('tree_modules');
	
	$modtree->_get_more_info($modtree->{cpan}->module_tree($modName));
}
sub BatchInstall{
	my ($self,$menu,$cmd_event,$modName)=@_;
	my $actionslist=Wx::Window::FindWindowByName('main_actions_list');
	my $modtree=Wx::Window::FindWindowByName('tree_modules');
	print "Adding $modName to batch.\n";
	$actionslist->InsertStringItem( 0, $modName );
	$actionslist->SetItem( 0, 1, "Install" );
	my @prereqs=$modtree->CheckPrerequisites($modName);
	foreach $preName (@prereqs){
		my $mod=$modtree->{cpan}->module_tree($preName);
		my $type=_T("Install");
		$type=_T("Update") if ($mod->installed_version);
		$actionslist->InsertStringItem( 0, $preName );
		$actionslist->SetItem( 0, 1, $type );
	}	
}
sub BatchUpdate{
	my ($menu,$cmd_event,$modName)=@_;
	my $actionslist=Wx::Window::FindWindowByName('main_actions_list');
	my $modtree=Wx::Window::FindWindowByName('tree_modules');
	$actionslist->InsertStringItem( 0, $modName );
	$actionslist->SetItem( 0, 1, "Update" );
	my @prereqs=$modtree->CheckPrerequisites($modName);
	foreach $preName (@prereqs){
		my $mod=$modtree->{cpan}->module_tree($preName);
		my $type=_T("Install");
		$type=_T("Update") if ($mod->installed_version);
		$actionslist->InsertStringItem( 0, $preName );
		$actionslist->SetItem( 0, 1, $type );
	}	
}
sub BatchUninstall{
	my ($menu,$cmd_event,$modName)=@_;
	my $actionslist=Wx::Window::FindWindowByName('main_actions_list');
	$actionslist->InsertStringItem( 0, $modName );
	$actionslist->SetItem( 0, 1, _T("Uninstall") );

}
sub BatchFetch{
	my ($menu,$cmd_event,$modName)=@_;
	my $actionslist=Wx::Window::FindWindowByName('main_actions_list');
	$actionslist->InsertStringItem( 0, $modName );
	$actionslist->SetItem( 0, 1, _T("Fetch") );

}
sub BatchExtract{
	my ($menu,$cmd_event,$modName)=@_;
	my $actionslist=Wx::Window::FindWindowByName('main_actions_list');
	$actionslist->InsertStringItem( 0, $modName );
	$actionslist->SetItem( 0, 1, _T("Extract") );

}
sub BatchPrepare{
	my ($menu,$cmd_event,$modName)=@_;
	my $actionslist=Wx::Window::FindWindowByName('main_actions_list');
	$actionslist->InsertStringItem( 0, $modName );
	$actionslist->SetItem( 0, 1, _T("Prepare") );

}
sub BatchBuild{
	my ($menu,$cmd_event,$modName)=@_;
	my $actionslist=Wx::Window::FindWindowByName('main_actions_list');
	$actionslist->InsertStringItem( 0, $modName );
	$actionslist->SetItem( 0, 1, _T("Build") );
}
sub BatchTest{
	my ($menu,$cmd_event,$modName)=@_;
	my $actionslist=Wx::Window::FindWindowByName('main_actions_list');
	$actionslist->InsertStringItem( 0, $modName );
	$actionslist->SetItem( 0, 1, _T("Test") );
}

package CPANPLUS::Shell::Wx::ModuleTree::Menu;
use base 'Wx::Menu';
use Wx::Event qw/EVT_WINDOW_CREATE EVT_MENU/;
use Data::Dumper;
use Wx::Locale gettext => '_T';

sub new {
	my $class = shift;
	my $parent=shift;
	my $item=shift;
	my $self  = $class->SUPER::new();    # create an 'empty' menu object
	#get image so we can determine what the status is
	$img=$parent->GetItemImage($item);
	$actions=new Wx::Menu();
	$install=$actions->Append(1000,_T("Install")) if $img == 3;
	$update=$actions->Append(1001,_T("Update")) if $img == 1;
	$uninstall=$actions->Append(1002,_T("Uninstall")) if ($img==0 or $img==1);
	$actions->AppendSeparator();
	$fetch=$actions->Append(1003,_T("Fetch"));
	$extract=$actions->Append(1004,_T("Extract"));
	$prepare=$actions->Append(1005,_T("Prepare"));
	$build=$actions->Append(1006,_T("Build"));
	$test=$actions->Append(1007,_T("Test"));

	$self->AppendSubMenu($actions,_T("Actions"));

	$info=$self->Append(1008,_T("Get All Information"));
	
	my $modName=$parent->GetItemText($item);

	EVT_MENU( $self, $info, sub{&{$parent->{_minfoHandler}}(@_,$modName)} ) if $parent->{_minfoHandler};
	EVT_MENU( $actions, $install, sub{&{$parent->{_minstallHandler}}(@_,$modName)} ) if ($img == 3 && $parent->{_minstallHandler});
	EVT_MENU( $actions, $update, sub{&{$parent->{_mupdateHandler}}(@_,$modName)} ) if ($img == 1 && $parent->{_minstallHandler});
	EVT_MENU( $actions, $uninstall, sub{&{$parent->{_muninstallHandler}}(@_,$modName)} )if (($img==0 or $img==1) && $parent->{_minstallHandler});
	EVT_MENU( $actions, $fetch, sub{&{$parent->{_mfetchHandler}}(@_,$modName)} )  if $parent->{_minstallHandler};
	EVT_MENU( $actions, $prepare, sub{&{$parent->{_mprepareHandler}}(@_,$modName)} ) if $parent->{_minstallHandler};
	EVT_MENU( $actions, $build, sub{&{$parent->{_mbuildHandler}}(@_,$modName)} ) if $parent->{_minstallHandler};
	EVT_MENU( $actions, $test,sub{&{$parent->{_mtestHandler}}(@_,$modName)} ) if $parent->{_minstallHandler};
	EVT_MENU( $actions, $extract, sub{&{$parent->{_mextractHandler}}(@_,$modName)} ) if $parent->{_minstallHandler};
#	print "Ending ";	
	return $self;
}



1;