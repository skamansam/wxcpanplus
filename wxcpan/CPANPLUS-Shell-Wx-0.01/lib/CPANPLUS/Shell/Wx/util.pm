package CPANPLUS::Shell::Wx::util;

use Wx::Event qw(EVT_MENU EVT_TOOL EVT_WINDOW_CREATE EVT_BUTTON);
use Wx::ArtProvider qw/:artid :clientid/;
use CPANPLUS;
use Cwd;
use Data::Dumper;
use CPANPLUS::Error;
use File::Spec;

#enable gettext support
use Wx::Locale gettext => '_T';

use base qw(Exporter);
our @EXPORT = qw(_uPopulateTree _uGetTimed _uGetInstallPath 
		_uShowErr _u_t_ShowErr);

#TODO this method populates a tree with the correct status icon
sub _uPopulateModulesWithIcons{
	my $max_pval=10000;  #the maximum value of the progress bar
	my $tree=shift;
	my $parent=shift;
	my $aref=shift;
	my $progress = shift;
	my $percent=shift || $max_pval/(@{%$tree}/2);
	my $cnt=shift || 0;

	$progress=Wx::ProgressDialog->new(_T("Inserting Items..."),
				_T("Inserting Items Into List..."),
				$max_pval,
				$self,
				wxPD_APP_MODAL) unless $progress;
	
	#remove all items if we are stating anew
	$tree->DeleteChildren($tree->GetRootItem()) unless $cnt;

	foreach $items ( sort {lc $a cmp lc $b} keys(%$tree)  ){
		my $curParent=$tree->AppendItem(
			$self->GetRootItem(),
			$top_level,_uGetStatusIcon($top_level));
		$progress->Update($cnt*$percent); #,"[Step 2 of 2] Iserting ".keys(%tree)." Authors Into Tree...#$cnt : $top_level");
		foreach $item (sort(@{$tree{$top_level}})){
			if (keys(%$item)){
				my $new_parent=$self->AppendItem($curParent,(keys(%$item))[0],$self->_get_status_icon($item)) if ($curParent && $item);				
				$cnt++;
				$progress->Update($cnt*$percent);
				$cnt=_uPopulateModulesWithIcons($tree,$new_parent,$item,$progress,$percent,$cnt);
			}else{
				my $new_parent=$self->AppendItem($curParent,$item,$self->_get_status_icon($item)) if ($curParent && $item);
				$progress->Update($cnt*$percent);
				$cnt++;
			}
		}
	}
	return $cnt;
	#$progress->Destroy();
}

sub _uGetInstallPath{
	my $file=shift;
	#$file=~s|::|/|g;
	my @path=split('::',$file);
	foreach $p (@INC){
		my $file=File::Spec->catfile($p,@path);
		#print "$p/$file\n";
		return $file if(-e $file) ;
	}
}

#it checks the stack in CPANPLUS::Error,
# and logs it to wherever Wx::LogMessage is sent to
sub _uShowErr{
	foreach $msg (CPANPLUS::Error::stack()){
		my $lvl=$msg->level;
		$lvl=~s/cp_//; 
		Wx::LogMessage("[CPANPLUS ".(uc($lvl||''))."@".$msg->when."]".$msg->message);
		CPANPLUS::Error::flush();
	}
}
#this method retrieves the local directory where CPANPLUS
#stores its information regarding each module
sub _uGetModDir{
	my $mod=shift;
	
}
#TODO this method populates a tree with the given array ref
sub _uPopulateModules($$){
	my $tree=shift;
	my $aref=shift;
}

#@return the time in readable - mm:ss - format 
#@params: 
#	$begin: the time we are comparing to 
#@usage: 
#	use util qw/_uGetTimed/;
#	my $begin=time();
#	{... code to be timed ...}
#	my $totalTime=_uGetTimed($begin);
sub _uGetTimed($){
	my $begin=shift;
	mu $end=time();
	return sprintf("%2d",(($end-$begin)/60)).":".sprintf("%2d",(($end-$begin) % 60));
}
