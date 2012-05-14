use strict;
use warnings;
use Module::Build;

Module::Build->new(
    module_name        => 'IPC::Simple',
    license            => 'perl',
    configure_requires => {
        'Module::Build' => '0.30',
    },
    build_requires     => {
        'Module::Build'    => '0.30',
        'Test::More'       => '0.88',
    },
    requires           => {
        'IPC::Open3' => 0,
        'perl'       => 5.008001,
    },
    recommends         => {
        'Test::Pod'           => '1.41',
        'Test::Pod::Coverage' => '1.06',
    },
    meta_merge         => {
        resources => {
            homepage    => 'http://search.cpan.org/dist/IPC-Simple/',
            bugtracker  => 'http://github.com/theory/ipc-simple/issues/',
            repository  => 'http://github.com/theory/ipc-simple/tree/',
        }
    },
)->create_build_script;
