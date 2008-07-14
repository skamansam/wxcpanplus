package CPANPLUS::Shell::Wx::UpdateWizard;

use base qw(Wx::Wizard);
use Wx qw/:allclasses wxID_OK wxID_CANCEL wxHORIZONTAL
	wxVERTICAL wxADJUST_MINSIZE wxDefaultPosition wxDefaultSize wxTE_MULTILINE 
	wxTE_READONLY wxTE_CENTRE wxTE_WORDWRAP wxALIGN_CENTER_VERTICAL wxEXPAND
	wxALIGN_CENTER_HORIZONTAL wxGA_HORIZONTAL wxGA_SMOOTH wxLC_REPORT 
	wxSUNKEN_BORDER/;
use Wx::Event qw(EVT_WIZARD_PAGE_CHANGED EVT_WINDOW_CREATE EVT_BUTTON EVT_CHECKBOX);
use Wx::ArtProvider qw/:artid :clientid/;
use Cwd;
use Data::Dumper;

use Wx::Locale gettext => '_T';

sub new{
	my $class = shift;
	my ($parent) = @_;
    my $self = $class->SUPER::new($parent,-1,"Update CPANPLUS");
	$self->{parent} = $parent;

	#get all the pages
	$self->{page1}=$self->_get_intro_page;
	$self->{page2}=$self->_get_update_type_page;
	$self->{page3}=$self->_get_review_page;
	$self->{page4}=$self->_get_progress_page;
	$self->{page5}=$self->_get_report_page;

	#connect all the pages together
	Wx::WizardPageSimple::Chain( $self->{page1}, $self->{page2} );
	Wx::WizardPageSimple::Chain( $self->{page2}, $self->{page3} );
	Wx::WizardPageSimple::Chain( $self->{page3}, $self->{page4} );
	Wx::WizardPageSimple::Chain( $self->{page4}, $self->{page5} );

	return $self;
}

#runs the wizard. 
sub Run{
	my $self=shift;
	$self->RunWizard($self->{page1});
}

#page 1: introduction
sub _get_intro_page{
	my $self=shift;
	my $page=Wx::WizardPageSimple->new( $self );

	$txt = Wx::TextCtrl->new($page, -1, 
		_T("Welcome to the CPANPLUS update wizard. \n".
		"	\nWe will begin by asking a few simple questions to update ".
		"CPANPLUS. \n	\nClick Next to begin."), 
		wxDefaultPosition, wxDefaultSize, wxTE_MULTILINE|wxTE_READONLY|wxTE_CENTRE|wxTE_WORDWRAP);

	$txt->Enable(0);

	$sizer = Wx::BoxSizer->new(wxVERTICAL);
	$sizer->Add($txt, 1, wxEXPAND|wxADJUST_MINSIZE, 0);
	$page->SetSizer($sizer);
	$sizer->Fit($page);

	return $page;
}

#page 2:
sub _get_update_type_page{
	my $self=shift;
	my $page=Wx::WizardPageSimple->new( $self );

	$txt = Wx::TextCtrl->new($page, -1, _T("First, we need to know which modules you would like to update:"), wxDefaultPosition, wxDefaultSize, wxTE_MULTILINE|wxTE_READONLY|wxTE_CENTRE|wxTE_WORDWRAP);
	$self->{update_core} = Wx::CheckBox->new($page, -1, _T("Core: \n  Just the core CPANPLUS modules."), wxDefaultPosition, wxDefaultSize, );
	$self->{update_deps} = Wx::CheckBox->new($page, -1, _T("Dependencies: \n  All the modules which CPANPLUS depends upon."), wxDefaultPosition, wxDefaultSize, );
	$self->{update_efeatures} = Wx::CheckBox->new($page, -1, _T("Enabled Features: \n  Currently enabled features of CPANPLUS."), wxDefaultPosition, wxDefaultSize, );
	$self->{update_features} = Wx::CheckBox->new($page, -1, _T("All Features: \n  Enabled and Non-Enabled Features"), wxDefaultPosition, wxDefaultSize, );
	$self->{update_all} = Wx::CheckBox->new($page, -1, _T("All"), wxDefaultPosition, wxDefaultSize, );
	$self->{static_line_1} = Wx::StaticLine->new($page, -1, wxDefaultPosition, wxDefaultSize, );
	$self->{update_all_copy} = Wx::CheckBox->new($page, -1, _T("Update to Latest Version"), wxDefaultPosition, wxDefaultSize, );

	$self->SetTitle(_T("Update Which Modules?"));
	$txt->Enable(0);
	$self->{update_all}->SetValue(1);
	$self->{update_all_copy}->SetValue(1);

	$sizer = Wx::BoxSizer->new(wxVERTICAL);
	$sizer->Add($txt, 0, wxEXPAND|wxADJUST_MINSIZE, 0);
	$sizer->Add($self->{update_core}, 0, wxALIGN_CENTER_VERTICAL|wxADJUST_MINSIZE, 0);
	$sizer->Add($self->{update_deps}, 0, wxALIGN_CENTER_VERTICAL|wxADJUST_MINSIZE, 0);
	$sizer->Add($self->{update_efeatures}, 0, wxALIGN_CENTER_VERTICAL|wxADJUST_MINSIZE, 0);
	$sizer->Add($self->{update_features}, 0, wxALIGN_CENTER_VERTICAL|wxADJUST_MINSIZE, 0);
	$sizer->Add($self->{update_all}, 0, wxALIGN_CENTER_VERTICAL|wxADJUST_MINSIZE, 0);
	$sizer->Add($self->{static_line_1}, 0, wxEXPAND, 0);
	$sizer->Add($self->{update_all_copy}, 0, wxALIGN_CENTER_VERTICAL|wxADJUST_MINSIZE, 0);
	$page->SetSizer($sizer);
	$sizer->Fit($page);

	return $page;
	
}
sub _get_progress_page{
	my $self=shift;
	
	my $page=Wx::WizardPageSimple->new( $self );
	
	$txt= Wx::TextCtrl->new($page, -1, _T("Please wait while we install the selected modules."), wxDefaultPosition, wxDefaultSize, wxTE_MULTILINE|wxTE_READONLY|wxTE_CENTRE|wxTE_WORDWRAP);
	$self->{progress} = Wx::Gauge->new($page, -1, 1000, wxDefaultPosition,     wxDefaultSize, wxGA_HORIZONTAL|wxGA_SMOOTH);
	$self->{status_text} = Wx::StaticText->new($page, -1, _T("Status text..."), wxDefaultPosition, wxDefaultSize, );

	$txt->Enable(0);

	$sizer = Wx::BoxSizer->new(wxVERTICAL);
	$sizer->Add($txt, 0, wxEXPAND|wxADJUST_MINSIZE, 0);
	$sizer->Add($self->{progress}, 0, wxEXPAND|wxADJUST_MINSIZE, 0);
	$sizer->Add($self->{status_text}, 0, wxEXPAND|wxALIGN_CENTER_HORIZONTAL|wxALIGN_CENTER_VERTICAL|wxADJUST_MINSIZE, 0);
	$page->SetSizer($sizer);
	$sizer->Fit($page);

	return $page;
	
}
sub _get_review_page{
	my $self=shift;
	
	my $page=Wx::WizardPageSimple->new( $self );
	$txt = Wx::TextCtrl->new($page, -1, _T("Next, review all the modules that need to be upgraded or installed:"), wxDefaultPosition, wxDefaultSize, wxTE_MULTILINE|wxTE_READONLY|wxTE_CENTRE|wxTE_WORDWRAP);
	$self->{update_list} = Wx::CheckListBox->new($page, -1, wxDefaultPosition, wxDefaultSize, [],wxSUNKEN_BORDER);

	$self->SetTitle(_T("wxCPAN Update Wizard Review Updates"));
	$txt->Enable(0);


	$sizer = Wx::BoxSizer->new(wxVERTICAL);
	$sizer->Add($txt, 0, wxEXPAND|wxADJUST_MINSIZE, 0);
	$sizer->Add($self->{update_list}, 1, wxEXPAND, 0);
	$page->SetSizer($sizer);
	$sizer->Fit($page);

	return $page;

}

sub _get_report_page{
	my $self=shift;
	
	my $page=Wx::WizardPageSimple->new( $self );
	$self->{problems} = Wx::TextCtrl->new($page, -1, _T("If there were any problems, they are listed below."), wxDefaultPosition, wxDefaultSize, wxTE_MULTILINE|wxTE_READONLY|wxTE_CENTRE|wxTE_WORDWRAP);


	$self->SetTitle(_T("wxCPAN Update Wizard Finished"));
	$self->{problems}->Enable(0);


	$sizer = Wx::BoxSizer->new(wxVERTICAL);
	$sizer->Add($self->{problems}, 1, wxEXPAND|wxADJUST_MINSIZE, 0);
	$page->SetSizer($sizer);
	$sizer->Fit($page);

	return $page;
	
}

1;
