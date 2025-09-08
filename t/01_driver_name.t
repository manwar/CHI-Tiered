#!/usr/bin/env perl

use v5.14;
use strict;
use warnings;
use Test::More;

use CHI::Tiered;
use File::Temp qw(tempdir);

use_ok 'CHI::Tiered';

# Create the tiered cache using the list of driver hashrefs
my $cache = CHI::Tiered->new(
    [ driver => 'Memory', global   => 1                       ],
    [ driver => 'File',   root_dir => tempdir( CLEANUP => 1 ) ],
);

$cache->clear;

# The module will automatically create the underlying CHI objects.
# We can't test them directly since they are private to the object.
isa_ok $cache, 'CHI::Tiered', 'Tiered cache object created successfully';

# Test 1: Initial `set` call (cache miss)
my $key1   = 'key_1';
my $value1 = $cache->set($key1, 'value_1');
is($value1, 'value_1', 'First set return the value');

# Test 2: Second `get` call (cache hit)
# This validates that the data was successfully cached in the fastest layer.
my $result = $cache->get($key1);
is($result, 'value_1', 'Second call hits the cache');

# Test 3: Test the `remove` method
$cache->remove($key1);
my $new_value = $cache->set($key1, 'new_value');
is($new_value, 'new_value', 'Remove method clears data from all tiers');

done_testing;
