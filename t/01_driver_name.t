use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use CHI;

# A single, shared in-memory datastore
# Note: This is not actually used when creating the cache with driver names
# but it's kept for consistency with the other tests.
our %SHARED_DATASTORE = ();

# Load the module under test
use_ok 'CHI::Tiered';

# Create the tiered cache using the string form of drivers
my $cache = CHI::Tiered->new(
    [ driver => 'Memory', datastore => \%SHARED_DATASTORE ],
    [ driver => 'File', root_dir => tempdir( CLEANUP => 1 ) ]
);

# The module will automatically create the underlying CHI objects.
# We can't test them directly since they are private to the object.
isa_ok $cache, 'CHI::Tiered', 'Tiered cache object created successfully using strings';

# --- Test 1: Initial `get_or_set` call (cache miss) ---
my $key1 = 'test_key_1';
my $result1 = $cache->get_or_set($key1, sub {
    return 'value_1';
});
is($result1, 'value_1', 'First get_or_set returns the generated value');

# --- Test 2: Second `get_or_set` call (cache hit on L1) ---
# This validates that the data was successfully cached in the fastest layer.
my $result2 = $cache->get_or_set($key1, sub {
    die 'This subroutine should not be called!';
});
is($result2, 'value_1', 'Second call hits memory cache and returns correct value');

# --- Test 3: Test the `remove` method ---
$cache->remove($key1);
my $data_after_remove = $cache->get_or_set($key1, sub {
    return 'new_value';
});
is($data_after_remove, 'new_value', 'Remove method clears data from all tiers');

done_testing;
