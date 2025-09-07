#!/usr/bin/env perl

use v5.14;
use strict;
use warnings;
use Test::More tests => 1;

BEGIN { use_ok('CHI::Tiered') || print "Bail out!\n"; }
diag( "Testing CHI::Tiered $CHI::Tiered::VERSION, Perl $], $^X" );
