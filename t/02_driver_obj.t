#!/usr/bin/env perl

use v5.14;
use strict;
use warnings;
use Test::More;

use Data::UUID;
use CHI::Tiered;
use File::Temp qw(tempdir);

use_ok 'CHI::Tiered';

my $ns = Data::UUID->new->create_str;

# Setup Caching Layers with Real Drivers
my $mem_cache  = CHI->new(
    driver    => 'Memory',
    namespace => $ns,
    global    => 1,
);

my $file_cache = CHI->new(
    driver    => 'File',
    namespace => $ns,
    root_dir  => tempdir(CLEANUP => 1),
);

$mem_cache->clear;
$file_cache->clear;

# Create the tiered cache with real CHI objects
my $cache = CHI::Tiered->new($mem_cache, $file_cache);

# Test 1: Tiered cache initialization
isa_ok $cache, 'CHI::Tiered', 'Tiered cache object created successfully';

# Test 2: Initial `get_or_set` call (cache miss)
my $key1 = 'key_1';
my $result1 = $cache->set($key1, 'value_1');
is($result1, 'value_1', 'First get_or_set returns the generated value');
is($mem_cache->get($key1), 'value_1', 'Data is now in Memory cache');
is($file_cache->get($key1), 'value_1', 'Data is now in File cache');

# Test 3: Second `get_or_set` call (cache hit on L1)
my $result2 = $cache->get($key1);
is($result2, 'value_1', 'Second call hits the cache');

# Test 4: Simulate a memory cache miss (L1 miss, L2 hit)
$mem_cache->remove($key1);
my $result3 = $cache->get($key1);
is($result3, 'value_1', 'Correctly falls back to File cache');
is($mem_cache->get($key1), 'value_1', 'Data is promoted back to Memory cache');

# Test 5: Test the `remove` method
$cache->remove($key1);
my $data_after_remove = $cache->set($key1, 'new_value');
is($data_after_remove, 'new_value', 'Remove method clears data from all tiers');
is($mem_cache->get($key1), 'new_value', 'Data is correctly regenerated after removal');
is($file_cache->get($key1), 'new_value', 'Data is correctly regenerated in file cache');

done_testing;
