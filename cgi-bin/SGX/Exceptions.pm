#
#===============================================================================
#
#         FILE:  Exceptions.pm
#
#  DESCRIPTION:
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Eugene Scherba (es), escherba@gmail.com
#      COMPANY:  Boston University
#      VERSION:  1.0
#      CREATED:  06/23/2011 17:03:33
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;

package SGX::Exceptions;

use Exception::Class (
    'SGX::Exception::Internal' => {
        fields      => 'errstr',
        description => 'internal error'
    },

    'SGX::Exception::DBI' => {
        fields      => 'errstr',
        description => 'DBI error'
    },

    'SGX::Exception::Prepare' => {
        isa         => 'SGX::Exception::DBI',
        fields      => 'errstr',
        description => 'could not prepare SQL statement'
    },

    'SGX::Exception::Execute' => {
        isa         => 'SGX::Exception::DBI',
        fields      => 'errstr',
        description => 'could not execute SQL statement'
    },

    'SGX::Exception::Insert' => {
        isa         => 'SGX::Exception::Execute',
        fields      => 'errstr',
        description => 'could not add record(s)'
    }
);

1;
