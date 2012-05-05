#!/usr/bin/perl -wT

use strict;
use warnings;

#---------------------------------------------------------------------------
#  Library includes
#---------------------------------------------------------------------------
# :TRICKY:05/04/2012 16:55:21:es:
# -nosticky: Prevent CGI.pm from printing hidden .cgifields inside a form
# without us specifically asking it so.
# -no_xhtml: By default, CGI.pm versions 2.69 and higher emit XHTML. This pragma
# disables this feature.
# use CGI::Pretty 2.47 qw/-nosticky -private_tempfiles -no_xhtml/;
#
use CGI 2.47 qw/-nosticky -private_tempfiles/;
use Carp qw/croak/;

#---------------------------------------------------------------------------
#  SGX directory
#---------------------------------------------------------------------------
use lib qw/./;
use SGX::Debug;
use SGX::Config qw/init_context get_module_from_action require_path/;
use SGX::Session::User 0.07 ();

#---------------------------------------------------------------------------
#  This is our own super-cool custom dispatcher and dynamic loader
#---------------------------------------------------------------------------
my $q = CGI->new();
my ($action) = $q->url_param('a');
$action = ( defined $action ) ? $action : '';

# :TODO:10/15/2011 23:07:12:es: throw 404 error here if cannot find a module
# that corresponds to the given action.
my $module = get_module_from_action($action)
  or croak "Invalid action name $action";

# get the Perl module needed
my $obj = eval {

    # convert Perl path to system path and load the file
    require_path($module);
    $module->new( _ResourceName => $action, init_context($q) )->init();
} or do {
    my $error = $@;
    croak "Error loading module $module. The message returned was:\n\n$error";
};

#---------------------------------------------------------------------------
# next, prepare and print header and body
#---------------------------------------------------------------------------
my $show_html = $obj->prepare_head();

my %header_command = (
    (
        ($show_html)
        ? (
            -status => 200,            # 200 OK
            -type   => 'text/html',    # do not send Content-Type
          )
        : ( -type => 'text/plain' )
    ),
    $obj->get_header()
);

# Show headers and cookies sent to user
#warn Dumper( \%header_command );

# :TRICKY:05/04/2012 16:53:32:es: Below is the only statement in the entire
# application that prints HTML body.
print

  # HTTP response header
  $q->header(%header_command),

  # HTTP response body
  $obj->view_show_content($show_html);

