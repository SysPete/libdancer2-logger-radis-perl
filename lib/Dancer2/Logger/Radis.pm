use strictures 2;

package Dancer2::Logger::Radis;

# ABSTRACT: Dancer2 logger engine for Log::Radis

use Moo;
use Log::Radis;
use Devel::StackTrace;

with 'Dancer2::Core::Role::Logger';

=head1 DESCRIPTION

Radis (from I<Radio> and I<Redis>) is a concept of caching GELF messages in a Redis DB. Redis provides a I<reliable queue> via the I<(B)RPOPLPUSH> command. See L<http://redis.io/commands/rpoplpush> for more information about that mechanism.

The implementation of a Radis client is quite simple: just push a GELF message with the L<LPUSH|http://redis.io/commands/lpush> command onto the queue. A collector fetches the messages from the queue and inserts them into a Graylog2 server, for example.

The current perl implementation is L<Log::Radis>. This module is a simple wrapper for it.

=head1 CONFIGURATION

    logger: 'Radis'
    engines:
      logger:
        Radis:
          server: 'redis-server:6379'
          queue: 'my-own-radis-queue'

For allowed options see L</ATTRIBUTES>.

=cut

# VERSION

=attr server

The Redis DB server we should connect to. Defaults to C<localhost:6379>.

See L<Log::Radis/server> for allowed values.

=cut

has server => (
    is => 'ro',
    default => 'localhost:6379',
);

=attr reconnect

Re-try connecting to the Redis DB up to I<reconnect> seconds. C<0> disables auto-reconnect.

See L<Log::Radis/reconnect> for more information.

=cut

has reconnect => (
    is => 'ro',
    default => 5,
);

=attr every

Re-try connection to the Redis DB every I<every> milliseconds.

See L<Log::Radis/every> for more information.

=cut

has every => (
    is => 'ro',
    default => 1,
);

=attr queue

The name of the list, which gelf streams are pushed to. Defaults to C<graylog-radis:queue>.

See L<Log::Radis/queue> for more information.

=cut

has queue => (
    is => 'ro',
    default => 'graylog-radis:queue',
);


has __mock => (
    is => 'ro',
);

has _radis => (
    is => 'lazy',
    builder => sub {
        my $self = shift;
        my %opts = (
            server => $self->server,
            reconnect => $self->reconnect,
            every => $self->every,
            queue => $self->queue,
        );
        if ($self->__mock) {
            $opts{redis} = $self->__mock;
        } else {
            die('meh');
        }
        Log::Radis->new(%opts);
    }
);

=method log

    log($level, $message);

Nothing special, just like you'd expect.

=cut

sub log {
    my $self = shift;
    my ($level, $message) = @_;
    my $caller = Devel::StackTrace->new->frame(5);

=head1 GELF MESSAGE

The log message cannot be formatted like described at L<Dancer2::Core::Role::Logger/log_format>. Instead, the additioal values are passed into the GELF message directly. Currently this mapping is hard-coded into this module:

    Dancer2 variable               | GELF param
    -------------------------------+-----------
    $$                             | _pid
    $dsl->app_name                 | _source
    $caller->package               | _package
    $caller->filename              | _filename
    $caller->line                  | _line
    $request->id                   | _http_id
    $request->user                 | _http_user
    $request->address              | _http_client
    $request->method               | _http_method
    $request->path                 | _http_path
    $request->protocol             | _http_proto
    $request->header('referer')    | _http_referer
    $request->header('user_agent') | _http_useragent
    $request->session->id          | _session_id

This may change in future.

=cut

    my %hash = (
        _source => $self->app_name,
        _pid => $$,
        _package => $caller->package,
        _filename => $caller->filename,
        _line => $caller->line,
    );
    if (my $request = $self->request) {
        $hash{_http_id} = $request->id;
        $hash{_http_user} = $request->user;
        $hash{_http_client} = $request->address;
        $hash{_http_method} = $request->method;
        $hash{_http_path} = $request->path;
        $hash{_http_proto} = $request->protocol;
        $hash{_http_referer} = $request->header('referer');
        $hash{_http_useragent} = $request->header('user_agent');
        if ($self->_has_session) {
            $hash{_session_id} = $request->session->id;
        }
    }
    $self->_radis->log($level, $message, %hash);
}

1;
