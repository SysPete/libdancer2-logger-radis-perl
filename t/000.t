#!perl

use t::ests;
use Log::Radis;
use Test::Mock::Redis;
use JSON qw(decode_json);

my $mock = Test::Mock::Redis->new;
my $queue;

sub lastlog {
    decode_json($mock->lpop($queue//return)//return)
}

{
    package Webservice;
    use Dancer2 appname => 'RadisTest';

    set engines => { logger => { Radis => { __mock => $mock } } };
    set logger => 'Radis';
    $queue = engine('logger')->queue;
    debug('Debug');
}

my $PT = init('Webservice');

my $log = lastlog();
eval { delete $log->{timestamp} };

is_deeply $log => {
    _filename => 't/000.t',
    _line => 22,
    _package => 'Webservice',
    _pid => $$,
    _source => 'RadisTest',
    host => $Log::Radis::HOSTNAME,
    level => 8, # debug
    short_message => 'Debug',
    version => $Log::Radis::GELF_SPEC_VERSION,
};

done_testing;
