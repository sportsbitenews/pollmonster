# PollMonster - a distributed data collection framework
# Copyright (C) 2010 Jerry Lundström
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# PollMonster is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with PollMonster.  If not, see <http://www.gnu.org/licenses/>.

package PollMonster::WorkDispatcher::Client;

use common::sense;
use Carp;

use PollMonster qw(:name);
use PollMonster::RPC::Client;

use Log::Log4perl ();
use Scalar::Util qw(weaken);

=head1 NAME

PollMonster - The great new PollMonster!

=head1 VERSION

See L<PollMonster> for version.

=cut

our $VERSION = $PollMonster::VERSION;

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use PollMonster;

    my $foo = PollMonster->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 function1

=cut

sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my %args = ( @_ );
    my $self = {
        logger => Log::Log4perl->get_logger,
        queue_full => 0
    };
    bless $self, $class;
    my $rself = $self;
    weaken($self);

    if (exists $args{on_connect} and ref($args{on_connect}) eq 'CODE') {
        $self->{on_connect} = $args{on_connect};
    }
    if (exists $args{on_error} and ref($args{on_error}) eq 'CODE') {
        $self->{on_error} = $args{on_error};
    }
    if (exists $args{on_eof} and ref($args{on_eof}) eq 'CODE') {
        $self->{on_eof} = $args{on_eof};
        $args{on_eof} = sub {
            $self->close;
            $self->{on_eof}->($self);
        };
    }
    if (exists $args{on_noauth} and ref($args{on_noauth}) eq 'CODE') {
        $self->{on_noauth} = $args{on_noauth};
        $args{on_noauth} = sub {
            $self->close;
            $self->{on_noauth}->($self);
        };
    }

    if (exists $args{on_queue_full} and ref($args{on_queue_full}) eq 'CODE') {
        $self->{on_queue_full} = $args{on_queue_full};
    }
    if (exists $args{on_queue_ok} and ref($args{on_queue_ok}) eq 'CODE') {
        $self->{on_queue_ok} = $args{on_queue_ok};
    }

    $args{on_connect} = sub {
        my ($rpc, $name) = @_;

        unless (defined $self->{rpc} and $self->{rpc}->is_connected) {
            if (exists $self->{on_error}) {
                $self->{on_error}->($self, 'connected but lost rpc object');
            }
            return;
        }

        unless ($name eq WORK_DISPATCHER_NAME) {
            if (exists $self->{on_error}) {
                $self->{on_error}->($self, 'connected to wrong service, expected '.WORK_DISPATCHER_NAME.' but got '.$name);
            }
            return;
        }

        if (exists $self->{on_connect}) {
            $self->{on_connect}->($self, $name);
        }
    };
    $args{on_error} = sub {
        my ($rpc, $message) = @_;

        $self->close;

        if (exists $self->{on_error}) {
            $self->{on_error}->($self, $message);
        }
    };

    if (exists $args{service} and ref($args{service}) eq 'HASH') {
        foreach (qw(queue_full queue_ok)) {
            if (exists $args{service}->{$_}) {
                croak 'Method '.$_.' is not allowed to overload in '.__PACKAGE__;
            }
        }
    }
    else {
        $args{service} = {};
    }

    foreach my $callback (qw(result)) {
        unless (exists $args{service}->{$callback}) {
            $args{service}->{$callback} = sub { croak 'Uncatch callback ('.$callback.') in '.__PACKAGE__ };
        }
    }

    $args{service}->{queue_full} = sub {
        $self->{queue_full} = 1;

        if (exists $self->{on_queue_full}) {
            $self->{on_queue_full}->($self);
        }
    };
    $args{service}->{queue_ok} = sub {
        $self->{queue_full} = 0;

        if (exists $self->{on_queue_ok}) {
            $self->{on_queue_ok}->($self);
        }
    };

#                  no_delay => 1,
#                  autocork => 0

    $self->{rpc} = PollMonster::RPC::Client->new(%args);

    PollMonster::OBJ_DEBUG and $self->{logger}->debug('new ', __PACKAGE__, ' ', $self);

    $self;
}

sub DESTROY {
    PollMonster::OBJ_DEBUG and $_[0]->{logger}->debug('destroy ', __PACKAGE__, ' ', $_[0]);
}

=head2 function2

=cut

sub is_connected {
    defined $_[0]->{rpc} and $_[0]->{rpc}->is_connected;
}

=head2 function2

=cut

sub uri {
    defined $_[0]->{rpc} and $_[0]->{rpc}->uri;
}

=head2 function2

=cut

sub close {
    $_[0]->{rpc} = undef;

    $_[0];
}

=head2 function2

=cut

sub queue {
    my ($self, $payload) = @_;

    unless (defined $self->{rpc}) {
        return;
    }

    if ($self->{queue_full}) {
        return -1;
    }

    if (defined $payload->private) {
        return $self->{rpc}->call('queue', $payload->uuid, $payload->module, $payload, $payload->private);
    }

    return $self->{rpc}->call('queue', $payload->uuid, $payload->module, $payload);
}

=head2 function2

=cut

sub is_queue_full {
    $_[0]->{queue_full};
}

=head1 AUTHOR

Jerry Lundström, C<< <lundstrom.jerry at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-pollmonster at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=PollMonster>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PollMonster


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=PollMonster>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/PollMonster>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/PollMonster>

=item * Search CPAN

L<http://search.cpan.org/dist/PollMonster/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2010 Jerry Lundström.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

PollMonster is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with PollMonster.  If not, see <http://www.gnu.org/licenses/>.


=cut

1;
