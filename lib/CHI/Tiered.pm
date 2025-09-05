package CHI::Tiered;

use strict;
use warnings;
use CHI;
use Carp;
use Scalar::Util 'blessed';

our $VERSION = '0.01';

=head1 NAME

CHI::Tiered - Multi-tier caching system with automatic promotion

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

    use CHI::Tiered;

    # Create a tiered cache with memory and file tiers
    my $cache = CHI::Tiered->new(
        [ driver => 'Memory', global   => 1            ],
        [ driver => 'File',   root_dir => '/tmp/cache' ],
    );

    # Or with pre-configured CHI objects
    my $memory_cache = CHI->new(driver => 'Memory', global   => 1);
    my $file_cache   = CHI->new(driver => 'File',   root_dir => '/tmp/cache');
    my $cache        = CHI::Tiered->new($memory_cache, $file_cache);

    # Get or set data (automatically caches across all tiers)
    my $data = $cache->get_or_set('my_key', sub {
        # Expensive computation or data retrieval
        return compute_expensive_data();
    });

    # Remove data from all tiers
    $cache->remove('my_key');

=head1 DESCRIPTION

CHI::Tiered provides a multi-tier caching system that automatically manages
data across multiple cache layers (tiers). When data is requested, it checks
each tier from fastest to slowest. If found in a slower tier, it promotes
the data to all faster tiers for future requests.

This is particularly useful for creating cache hierarchies where you might
have very fast but limited storage (like memory) combined with slower but
more abundant storage (like disk or distributed cache).

=head1 CONSTRUCTOR

=head2 new

Creates a new CHI::Tiered object. Tiers can be specified in two ways:

    my $cache = CHI::Tiered->new(@tiers);

=over 4

=item * Array references containing CHI constructor arguments:

    CHI::Tiered->new(
        [ driver => 'Memory',    global   => 1 ],
        [ driver => 'File',      root_dir => '/tmp/cache' ],
        [ driver => 'Memcached', servers  => [ '127.0.0.1:11211' ] ]
    );

=item * Pre-configured CHI objects:

    my $memory    = CHI->new(driver => 'Memory',    global   => 1);
    my $file      = CHI->new(driver => 'File',      root_dir => '/tmp/cache');
    my $memcached = CHI->new(driver => 'Memcached', servers  => [ '127.0.0.1:11211' ]);

    CHI::Tiered->new($memory, $file, $memcached);

=back

The order of tiers is important - they should be specified from fastest to slowest.

=cut

sub new {
    my ($class, @args) = @_;
    my $self = bless {}, $class;

    $self->{_tiers} = [];

    # Check if we received any arguments at all
    if (!@args) {
        croak "Constructor requires at least one argument: list of arrayref or list of pre-configured CHI object.";
    }

    # Determine the argument type: a list of strings or a list of objects
    if (ref($args[0]) eq 'ARRAY') {
        # Interface 1: User provided a list of arrayref like below:
        # [ driver => 'Memory', datastore => \%SHARED_DATASTORE      ],
        # [ driver => 'File',   root_dir  => tempdir( CLEANUP => 1 ) ],
        foreach my $chi_driver (@args) {
            my $cache = CHI->new(@$chi_driver);
            push @{$self->{_tiers}}, $cache;
        }
    } else {
        # Interface 2: User provided a list of pre-configured CHI drivers.
        # We must respect the user's order here.
        my @SUPPORTED_DRIVERS = qw/Memory Memcached FastMmap Redis File/;
        foreach my $obj (@args) {
            if (blessed($obj) && $obj->isa('CHI::Driver')) {
                my $driver = $obj->short_driver_name;
                die "Unsupported driver $driver.\n"
                    unless (grep /$driver/, @SUPPORTED_DRIVERS);
            }
            else {
                die "Not CHI::Driver object.\n";
            }
        }
        $self->{_tiers} = \@args;
    }

    return $self;
}

=head1 METHODS

=head2 get_or_set

Retrieves a value from the cache tiers. If the value is found in any tier,
it returns the value and promotes it to all faster tiers. If the value is
not found in any tier, it executes the code reference to generate the value,
stores it in all tiers, and returns it.

    my $value = $cache->get_or_set($key, $code_ref);

Parameters:

=over 4

=item * $key - The cache key

=item * $code_ref - A code reference that returns the value to cache if not found

=back

Returns: The cached or generated value

=cut

sub get_or_set {
    my ($self, $key, $code_ref) = @_;

    # Iterate through each cache tier from fastest to slowest
    my $data;
    for (my $i = 0; $i < @{$self->{_tiers}}; $i++) {
        my $tier = $self->{_tiers}->[$i];
        $data = $tier->get($key);

        # If data is found, promote it to all faster tiers
        if (defined $data) {
            # Start from the found tier and promote to all previous tiers
            for (my $j = $i - 1; $j >= 0; $j--) {
                $self->{_tiers}->[$j]->set($key, $data);
            }
            return $data;
        }
    }

    # If data is not found in any tier, generate it
    $data = $code_ref->();

    # Set the data in all tiers for future use
    foreach my $tier (@{$self->{_tiers}}) {
        $tier->set($key, $data);
    }

    return $data;
}

=head2 remove

Removes the specified key from all cache tiers.

    $cache->remove($key);

Parameters:

=over 4

=item * $key - The cache key to remove

=back

=cut

sub remove {
    my ($self, $key) = @_;

    foreach my $tier (@{$self->{_tiers}}) {
        $tier->remove($key);
    }
}

=head1 BEHAVIOUR

=over 4

=item * Tier Order: Tiers are checked from first (fastest) to last (slowest)

=item * Data Promotion: When data is found in a slower tier, it's automatically
promoted to all faster tiers

=item * Data Population: When data is not found, it's stored in all tiers

=item * Consistency: Removal operations affect all tiers simultaneously

=back

=head1 EXAMPLES

=head2 Two-tier memory and file cache

    my $cache = CHI::Tiered->new(
        [ driver => 'Memory', global => 1, max_size => 1024 * 1024 ],
        [ driver => 'File', root_dir => '/var/cache/app', depth => 3 ]
    );

    my $result = $cache->get_or_set('user_profile_123', sub {
        # Expensive database query
        return $db->selectrow_hashref('SELECT * FROM users WHERE id = 123');
    });

=head2 Three-tier cache with memory, file and memcached

    my $cache = CHI::Tiered->new(
        [ driver => 'Memory',    global   => 1 ],
        [ driver => 'File',      root_dir => '/tmp/cache' ],
        [ driver => 'Memcached', servers  => [ 'cache1:11211', 'cache2:11211' ] ]
    );

=head1 AUTHOR

Mohammad Sajid Anwar, C<< <mohammad.anwar@yahoo.com> >>

=head1 REPOSITORY

L<https://github.com/manwar/CHI-Tiered>

=head1 BUGS

Please report any bugs or feature requests through the web interface at L<https://github.com/manwar/CHI-Tiered/issues>.
I will  be notified and then you'll automatically be notified of progress on your
bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc CHI::Tiered

You can also look for information at:

=over 4

=item * BUG Report

L<https://github.com/manwar/CHI-Tiered/issues>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/CHI-Tiered>

=item * Search MetaCPAN

L<https://metacpan.org/dist/CHI-Tiered>

=back

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2025 Mohammad Sajid Anwar.

This program  is  free software; you can redistribute it and / or modify it under
the  terms  of the the Artistic License (2.0). You may obtain a  copy of the full
license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any  use,  modification, and distribution of the Standard or Modified Versions is
governed by this Artistic License.By using, modifying or distributing the Package,
you accept this license. Do not use, modify, or distribute the Package, if you do
not accept this license.

If your Modified Version has been derived from a Modified Version made by someone
other than you,you are nevertheless required to ensure that your Modified Version
 complies with the requirements of this license.

This  license  does  not grant you the right to use any trademark,  service mark,
tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge patent license
to make,  have made, use,  offer to sell, sell, import and otherwise transfer the
Package with respect to any patent claims licensable by the Copyright Holder that
are  necessarily  infringed  by  the  Package. If you institute patent litigation
(including  a  cross-claim  or  counterclaim) against any party alleging that the
Package constitutes direct or contributory patent infringement,then this Artistic
License to you shall terminate on the date that such litigation is filed.

Disclaimer  of  Warranty:  THE  PACKAGE  IS  PROVIDED BY THE COPYRIGHT HOLDER AND
CONTRIBUTORS  "AS IS'  AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES. THE IMPLIED
WARRANTIES    OF   MERCHANTABILITY,   FITNESS   FOR   A   PARTICULAR  PURPOSE, OR
NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY YOUR LOCAL LAW. UNLESS
REQUIRED BY LAW, NO COPYRIGHT HOLDER OR CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL,  OR CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE
OF THE PACKAGE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut

1; # End of CHI::Tiered
