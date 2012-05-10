#!/usr/bin/perl -wT

use strict;
use warnings;

use lib qw/./;
use SGX::Abstract::Exception ();
use SGX::Config              ();

#---------------------------------------------------------------------------
#  This is our own super-cool custom dispatcher and dynamic loader
#---------------------------------------------------------------------------
my ( $module, $obj );
my @context;
my @header;
my $config = SGX::Config->new();
eval {
    @context = $config->get_context();
    $module  = $config->get_module_name();

    # convert Perl path to system path and load the file
    my $module_path = $module;
    $module_path =~ s/::/\//g;
    require "$module_path.pm";    ## no critic
    $obj = $module->new(
        config               => {@context},
        restore_session_from => undef
    );
    $obj->init();
    @header = $obj->get_header();
} or do {

    # do not restore session to show simply a static error page
    my $exception = Exception::Class->caught();
    require SGX::Static;
    $obj = SGX::Static->new(
        config => {
            _Exception       => $exception,
            _ExceptionSource => $module,
            @context
        }
    );
    $obj->init();
    $obj->set_action('error');
    @header = $obj->get_header();
};

# Important: Below is the only line in the entire application that is allowed to
# print to the browser window.
print @header, $obj->view_show_content();
