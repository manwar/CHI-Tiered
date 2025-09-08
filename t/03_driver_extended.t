#!/usr/bin/env perl

use v5.14;
use strict;
use warnings;
use Test::More;

use CHI;
use CHI::Tiered;
use CHI::Driver::FastMmap;

use Data::UUID;
use File::Temp qw(tempdir);

BEGIN { use_ok 'CHI::Tiered'; }

eval {
    use CHI::Driver::Redis;
    use CHI::Driver::Memcached;
};
plan skip_all => "Missing CHI driver (Redis/Memcached)" if $@;

my $ns = Data::UUID->new->create_str;

# Setup Caching Layers
# Layer 1: Fastest - In-memory cache
my $mem_cache = CHI->new(
    driver    => 'Memory',
    namespace => $ns,
    global    => 1,
);

# Layer 2: Fast - Memcached (requires a running Memcached service)
my $memcached_cache = CHI->new(
    driver    => 'Memcached',
    namespace => $ns,
    servers   => ['127.0.0.1:11211'],
);

# Layer 3: Slower - Fast::Mmap (very fast, but disk-backed and local)
my $mmap_cache = CHI->new(
    driver    => 'FastMmap',
    namespace => $ns,
    root_dir  => tempdir(CLEANUP => 1),
);

# Layer 4: Slower - Redis (requires a running Redis service)
my $redis_cache = CHI->new(
    driver    => 'Redis',
    namespace => $ns,
);

# Layer 5: Slowest - File system cache
my $file_cache = CHI->new(
    driver    => 'File',
    namespace => $ns,
    root_dir  => tempdir(CLEANUP => 1),
);

$mem_cache->clear;
$mmap_cache->clear;
$redis_cache->clear;
$file_cache->clear;

# Create the tiered cache with all five layers, from fastest to slowest.
my $cache = CHI::Tiered->new(
    $mem_cache,
    $memcached_cache,
    $mmap_cache,
    $redis_cache,
    $file_cache,
);

$cache->clear;

# Test 1: Tiered cache initialization
isa_ok $cache, 'CHI::Tiered', 'Tiered cache object created successfully';

# Test 2: Initial `get_or_set` call (cache miss on all layers)
my $key1 = 'key_1';
my $result1 = $cache->set($key1, 'value_1');
is($result1, 'value_1', 'First get_or_set returns the generated value');
is($mem_cache->get($key1), 'value_1', 'Data is now in Memory cache');
is($memcached_cache->get($key1), 'value_1', 'Data is now in Memcached cache');
is($mmap_cache->get($key1), 'value_1', 'Data is now in Fast::Mmap cache');
is($redis_cache->get($key1), 'value_1', 'Data is now in Redis cache');
is($file_cache->get($key1), 'value_1', 'Data is now in File cache');

# Test 3: Cache hit on L1 (Memory)
my $result2 = $cache->get($key1);
is($result2, 'value_1', 'Second call hits memory cache and returns correct value');

# Test 4: Simulate an L1 miss, L2 hit (Memcached)
$mem_cache->remove($key1);
my $result3 = $cache->get($key1);
is($result3, 'value_1', 'Correctly falls back to Memcached cache');
is($mem_cache->get($key1), 'value_1', 'Data is promoted back to Memory cache');

# Test 5: Simulate L1/L2 miss, L3 hit (Fast::Mmap)
$mem_cache->remove($key1);
$memcached_cache->remove($key1);
my $result4 = $cache->get($key1);
is($result4, 'value_1', 'Correctly falls back to Fast::Mmap cache');
is($mem_cache->get($key1), 'value_1', 'Data is promoted to Memory cache');
is($memcached_cache->get($key1), 'value_1', 'Data is promoted to Memcached cache');

# Test 6: Test the `remove` method
$cache->remove($key1);
my $data_after_remove = $cache->set($key1, 'new_value');
is($data_after_remove, 'new_value', 'Remove method clears data from all tiers');
is($mem_cache->get($key1), 'new_value', 'Data is correctly regenerated after removal');
is($memcached_cache->get($key1), 'new_value', 'Data is correctly regenerated in Memcached cache');
is($mmap_cache->get($key1), 'new_value', 'Data is correctly regenerated in Fast::Mmap cache');
is($redis_cache->get($key1), 'new_value', 'Data is correctly regenerated in Redis cache');
is($file_cache->get($key1), 'new_value', 'Data is correctly regenerated in file cache');

done_testing;
