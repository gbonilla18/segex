#
#===============================================================================
#
#         FILE:  Exceptions.pm
#
#  DESCRIPTION:
#
#  Here we declare our exception hierarchy.
#
#  For now, the top two branches in the hierarchy are
#  SGX::Abstract::Exception::User and SGX::Abstract::Exception::Internal. They
#  are meant to describe two general classes of errors: user errors and internal
#  errors. User errors are caused by bad user input or improper interaction and
#  they are excepted to happen during normal use (albeit not very often).
#  Internal errors are caused by unexpected internal state and should never
#  happen; in case they do happen, we throw SGX::Abstract::Exception::Internal.
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

use strict;
use warnings;

package SGX::Abstract::Exception;

# User exceptions are messages to user; Internal exceptions are messages for
# internal development puprposes. Showing internal exceptions to user may pose a
# security risk.
#
use Exception::Class (
    'SGX::Abstract::Exception::User' => {
        description =>
          'Error potentially caused by bad user input (to be displayed to user)'
    },
    'SGX::Abstract::Exception::Internal' =>
      { description => 'Internal error (to be hidden from user)' },
    'SGX::Abstract::Exception::Internal::JS' => {
        isa         => 'SGX::Abstract::Exception::Internal',
        description => 'Cannot form Javascript'
    }
);

1;
