use 5.008008;
use inc::Module::Install;

# Define metadata
name           'CPANPLUS-Shell-Wx';
#author           'Skaman Sam Tyler <skamansam@gmail.com>';
#license        'perl';
#perl_version   '5.006';
all_from       'lib/CPANPLUS/Shell/Wx.pm';

# Specific dependencies
requires       'File::Spec'  				=> '0.80';
requires       'Wx'          				=> '0.74';
requires       'Cwd'    	 				=> '0.0';
requires       'IPC::Cmd'    				=> '0.0';
requires       'Module::Load'   			=> '0.0';
requires       'Params::Check'  			=> '0.0';
requires       'Module::Load::Conditional'	=> '0.0';
requires       'Locale::Maketext::Simple'	=> '0.0';
requires       'File::Spec'    				=> '0.0';
requires       'File::HomeDir'    			=> '0.0';
requires       'Class::Struct'    			=> '0.0';
#requires       'CPANPLUS'    => '0.0';
#requires       'CPANPLUS'    => '0.0';

#test_requires  'Test::More'  => '0.42';
#recommends     'Text::CSV_XS'=> '0.50';
no_index       'directory'   => 'blib';
install_script 'bin/wxcpan';
install_script 'bin/wxpodreader';


WriteAll;
