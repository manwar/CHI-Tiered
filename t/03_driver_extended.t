use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use CHI;
use Data::GUID;
use CHI::Driver::FastMmap; # You need to explicitly load this driver

# A single, shared in-memory datastore
our %SHARED_DATASTORE = ();

# Load the module under test
BEGIN { use_ok 'CHI::Tiered'; }

# --- Setup Caching Layers ---
# Layer 1: Fastest - In-memory cache
my $mem_cache = CHI->new( driver => 'Memory', namespace => 'mem', datastore => \%SHARED_DATASTORE );

# Layer 2: Fast - Memcached (requires a running Memcached service)
my $memcached_cache = CHI->new( driver => 'Memcached', namespace => 'memc'.Data::GUID->new->as_string, servers => ['127.0.0.1:11211'] );

# Layer 3: Slower - Fast::Mmap (very fast, but disk-backed and local)
my $mmap_cache = CHI->new(
    driver    => 'FastMmap',
    namespace => 'mmap',
    root_dir  => tempdir( CLEANUP => 1 ),
);

# Layer 4: Slower - Redis (requires a running Redis service)
my $redis_cache = CHI->new( driver => 'Redis', namespace => 'redis' );

# Layer 5: Slowest - File system cache
my $file_cache = CHI->new(
    driver    => 'File',
    namespace => 'file',
    root_dir  => tempdir( CLEANUP => 1 ),
);

# Clear each cache using the appropriate supported method
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

# --- Test 1: Tiered cache initialization ---
isa_ok $cache, 'CHI::Tiered', 'Tiered cache object created successfully';

# --- Test 2: Initial `get_or_set` call (cache miss on all layers) ---
my $key1 = 'test_key_1';
my $result1 = $cache->get_or_set($key1, sub {
    return 'value_1';
});
is($result1, 'value_1', 'First get_or_set returns the generated value');
is($mem_cache->get($key1), 'value_1', 'Data is now in Memory cache');
is($memcached_cache->get($key1), 'value_1', 'Data is now in Memcached cache');
is($mmap_cache->get($key1), 'value_1', 'Data is now in Fast::Mmap cache');
is($redis_cache->get($key1), 'value_1', 'Data is now in Redis cache');
is($file_cache->get($key1), 'value_1', 'Data is now in File cache');

# --- Test 3: Cache hit on L1 (Memory) ---
my $result2 = $cache->get_or_set($key1, sub {
    die 'This subroutine should not be called!';
});
is($result2, 'value_1', 'Second call hits memory cache and returns correct value');

# --- Test 4: Simulate an L1 miss, L2 hit (Memcached) ---
$mem_cache->remove($key1);
my $result3 = $cache->get_or_set($key1, sub {
    die 'This subroutine should not be called!';
});
is($result3, 'value_1', 'Correctly falls back to Memcached cache');
is($mem_cache->get($key1), 'value_1', 'Data is promoted back to Memory cache');

# --- Test 5: Simulate L1/L2 miss, L3 hit (Fast::Mmap) ---
$mem_cache->remove($key1);
$memcached_cache->remove($key1);
my $result4 = $cache->get_or_set($key1, sub {
    die 'This subroutine should not be called!';
});
is($result4, 'value_1', 'Correctly falls back to Fast::Mmap cache');
is($mem_cache->get($key1), 'value_1', 'Data is promoted to Memory cache');
is($memcached_cache->get($key1), 'value_1', 'Data is promoted to Memcached cache');

# --- Test 6: Test the `remove` method ---
$cache->remove($key1);
my $data_after_remove = $cache->get_or_set($key1, sub {
    return 'new_value';
});
is($data_after_remove, 'new_value', 'Remove method clears data from all tiers');
is($mem_cache->get($key1), 'new_value', 'Data is correctly regenerated after removal');
is($memcached_cache->get($key1), 'new_value', 'Data is correctly regenerated in Memcached cache');
is($mmap_cache->get($key1), 'new_value', 'Data is correctly regenerated in Fast::Mmap cache');
is($redis_cache->get($key1), 'new_value', 'Data is correctly regenerated in Redis cache');
is($file_cache->get($key1), 'new_value', 'Data is correctly regenerated in file cache');

done_testing;
