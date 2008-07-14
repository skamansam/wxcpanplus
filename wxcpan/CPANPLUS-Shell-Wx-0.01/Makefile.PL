use 5.008008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'CPANPLUS::Shell::Wx',
    VERSION_FROM      => 'lib/CPANPLUS/Shell/Wx.pm', # finds $VERSION
    PREREQ_PM         => {'Wx'=>0.74,'CPANPLUS'=>0.78}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/CPANPLUS/Shell/Wx.pm', # retrieve abstract from module
       AUTHOR         => 'Samuel C. Tyler <skamansam@gmail.com>') : ()),
);
