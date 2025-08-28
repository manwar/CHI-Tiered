use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use CHI;

# A single, shared in-memory datastore
our %SHARED_DATASTORE = ();

# Load the module under test
use_ok 'CHI::Tiered';

# --- Setup Caching Layers with Real Drivers ---
# Pass the shared datastore explicitly.
my $mem_cache = CHI->new( driver => 'Memory', namespace => 'mem', datastore => \%SHARED_DATASTORE );
my $file_cache = CHI->new(
    driver    => 'File',
    namespace => 'file',
    root_dir  => tempdir( CLEANUP => 1 ),
);

# Add this crucial section to ensure a clean slate before every test run
$mem_cache->clear;
$file_cache->clear;

# Create the tiered cache with real CHI objects
my $cache = CHI::Tiered->new(
    $mem_cache,
    $file_cache,
);

# --- Test 1: Tiered cache initialization ---
isa_ok $cache, 'CHI::Tiered', 'Tiered cache object created successfully';

# --- Test 2: Initial `get_or_set` call (cache miss) ---
my $key1 = 'test_key_1';
my $result1 = $cache->get_or_set($key1, sub {
    return 'value_1';
});
is($result1, 'value_1', 'First get_or_set returns the generated value');
is($mem_cache->get($key1), 'value_1', 'Data is now in Memory cache');
is($file_cache->get($key1), 'value_1', 'Data is now in File cache');

# --- Test 3: Second `get_or_set` call (cache hit on L1) ---
my $result2 = $cache->get_or_set($key1, sub {
    die 'This subroutine should not be called!';
});
is($result2, 'value_1', 'Second call hits memory cache and returns correct value');

# --- Test 4: Simulate a memory cache miss (L1 miss, L2 hit) ---
# Remove data from the fastest layer and verify it's retrieved from the next one.
$mem_cache->remove($key1);
my $result3 = $cache->get_or_set($key1, sub {
    die 'This subroutine should not be called!';
});
is($result3, 'value_1', 'Correctly falls back to File cache');
is($mem_cache->get($key1), 'value_1', 'Data is promoted back to Memory cache');

# --- Test 5: Test the `remove` method ---
$cache->remove($key1);
my $data_after_remove = $cache->get_or_set($key1, sub {
    return 'new_value';
});
is($data_after_remove, 'new_value', 'Remove method clears data from all tiers');
is($mem_cache->get($key1), 'new_value', 'Data is correctly regenerated after removal');
is($file_cache->get($key1), 'new_value', 'Data is correctly regenerated in file cache');

done_testing;
