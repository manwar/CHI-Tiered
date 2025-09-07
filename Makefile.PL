#!/usr/bin/perl

use v5.14;
use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME               => 'CHI::Tiered',
    AUTHOR             => q{Mohammad Sajid Anwar <mohammad.anwar@yahoo.com>},
    VERSION_FROM       => 'lib/CHI/Tiered.pm',
    ABSTRACT_FROM      => 'lib/CHI/Tiered.pm',
    LICENSE            => 'artistic_2',
    MIN_PERL_VERSION   => 5.014,
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    BUILD_REQUIRES   => {
        'Test::More' => 0,
    },
    PREREQ_PM => {
        'CHI'          => 0,
        'Carp'         => 0,
        'Scalar::Util' => 0,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'CHI-Tiered-*' },
    (eval { ExtUtils::MakeMaker->VERSION(6.46) } ? (META_MERGE => {
        'meta-spec' => { version => 2 },
        provides    => {
            'CHI::Tiered' => { file => 'lib/CHI/Tiered.pm', version => '0.01' }
        },
        resources => {
            repository => {
                type => 'git',
                url  => 'https://github.com/manwar/CHI-Tiered.git',
                web  => 'https://github.com/manwar/CHI-Tiered',
            },
        }})
     : ()
    ),
);
