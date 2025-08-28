#!/usr/bin/perl

use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More tests => 1;

BEGIN { use_ok('CHI::Tiered') || print "Bail out!\n"; }
diag( "Testing CHI::Tiered $CHI::Tiered::VERSION, Perl $], $^X" );
