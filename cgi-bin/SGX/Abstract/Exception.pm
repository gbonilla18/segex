package SGX::Abstract::Exception;

use strict;
use warnings;

# User exceptions are messages to user; Internal exceptions are messages for
# internal development puprposes. Showing internal exceptions to user may pose a
# security risk.
#
use Exception::Class (
    'SGX::Exception::User' => {
        description =>
          'Error potentially caused by bad user input (to be displayed to user)'
    },
    'SGX::Exception::Internal' =>
      { description => 'Internal error (to be hidden from user)' },
    'SGX::Exception::Internal::JS' => {
        isa         => 'SGX::Exception::Internal',
        description => 'Cannot form Javascript'
    },
    'SGX::Exception::Internal::Mail' => {
        isa         => 'SGX::Exception::Internal',
        description => 'Mailer error'
    },
    'SGX::Exception::Internal::Session' => {
        isa         => 'SGX::Exception::Internal',
        description => 'Session-related error'
    },
    'SGX::Exception::Internal::Duplicate' => {
        isa         => 'SGX::Exception::Internal',
        description => 'Two or more records encountered where one was expected'
    }
);

1;

__END__

#
#===============================================================================
#
#         FILE:  Exceptions.pm
#
#  DESCRIPTION:
#
#  Here we declare our exception hierarchy zoo.
#
#  For now, the top two branches in the hierarchy are
#  SGX::Exception::User and SGX::Exception::Internal. They
#  are meant to describe two general classes of errors: user errors and internal
#  errors. User errors are caused by bad user input or improper interaction and
#  they are excepted to happen during normal use (albeit not very often).
#  Internal errors are caused by unexpected internal state and should never
#  happen; in case they do happen, we throw SGX::Exception::Internal.
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:
#
#  About stringification: "The default implementation of the as_string() method
#  does not take into account any fields that might exist for a given exception
#  class. If you want to include these when an object is stringified or when
#  as_string() is called, the correct way to do this is to override
#  full_message() instead of overriding as_string()."
#  http://drdobbs.com/web-development/184416129
#
#       AUTHOR:  Eugene Scherba (es), escherba@gmail.com
#      COMPANY:  Boston University
#      VERSION:  1.0
#      CREATED:  06/23/2011 17:03:33
#     REVISION:  ---
#===============================================================================


