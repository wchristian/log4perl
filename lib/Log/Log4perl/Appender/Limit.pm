######################################################################
# Limit.pm -- 2003, Mike Schilli <m@perlmeister.com>
######################################################################
# Special composite appender limiting the number of messages relayed
# to its appender(s).
######################################################################

###########################################
package Log::Log4perl::Appender::Limit;
###########################################

use strict;
use warnings;

our @ISA = qw(Log::Log4perl::Appender);

our $CVSVERSION   = '$Revision: 1.1 $';
our ($VERSION)    = ($CVSVERSION =~ /(\d+\.\d+)/);

###########################################
sub new {
###########################################
    my($class, %options) = @_;

    my $self = {
        appender     => undef,
        accumulate   => 1,
        persistent   => undef,
        block_period => 3600,
        buffer       => [],
        %options,
    };

        # Pass back the appender to be synchronized as a dependency
        # to the configuration file parser
    push @{$options{l4p_depends_on}}, $self->{appender};

        # Run our post_init method in the configurator after
        # all appenders have been defined to make sure the
        # appenders we're connecting to really exist.
    push @{$options{l4p_post_config_subs}}, sub { $self->post_init() };

    bless $self, $class;
}

###########################################
sub log {
###########################################
    my($self, %params) = @_;
    
    if(exists $self->{sent_last} and
       $self->{sent_last} + $self->{block_period} > time()) {
            # Message needs to be blocked for now.

            # Save event time for later
        $params{log4p_logtime} = $self->{app}->{layout}->{time_function}->();

            # Save message and other parameters
        push @{$self->{buffer}}, \%params if $self->{accumulate};

        return;
    }

    # Relay all messages we got to the SUPER class, which needs to render the
    # messages according to the appender's layout, first.

    $Log::Log4perl::caller_depth += 2;

        # Log pending messages if we have any
    for(@{$self->{buffer}}) {
            # Trick the renderer into using the original event time
        local $self->{app}->{layout}->{time_function};
        $self->{app}->{layout}->{time_function} = 
                                    sub { $_->{log4p_logtime} };
        $self->{app}->SUPER::log($_,
                                 $_->{log4p_category},
                                 $_->{log4p_level});
    }
        # Log current message as well
    $self->{app}->SUPER::log(\%params,
                             $params{log4p_category},
                             $params{log4p_level});

    $Log::Log4perl::caller_depth -= 2;

    $self->{sent_last} = time();
}

###########################################
sub post_init {
###########################################
    my($self) = @_;

    if(! exists $self->{appender}) {
       die "No appender defined for " . __PACKAGE__;
    }

    my $appenders = Log::Log4perl->appenders();
    my $appender = Log::Log4perl->appenders()->{$self->{appender}};

    if(! defined $appender) {
       die "Appender $self->{appender} not defined (yet) when " .
           __PACKAGE__ . " needed it";
    }

    $self->{app} = $appender;
}

###########################################
sub DESTROY {
###########################################
    my($self) = @_;

    # Nothing to clean up (yet).
}

1;

__END__

=head1 NAME

    Log::Log4perl::Appender::Limit - Limit message delivery via block period

=head1 SYNOPSIS

    use Log::Log4perl qw(:easy);

    my $conf = qq(
      log4perl.category = WARN, Limiter
    
          # Email appender
      log4perl.appender.Mailer          = Log::Dispatch::Email::MailSend
      log4perl.appender.Mailer.to       = drone\@pageme.com
      log4perl.appender.Mailer.subject  = Something's broken!
      log4perl.appender.Mailer.buffered = 0
      log4perl.appender.Mailer.layout   = PatternLayout
      log4perl.appender.Mailer.layout.ConversionPattern=%d %m %n

          # Limiting appender, using the email appender above
      log4perl.appender.Limiter              = Log::Log4perl::Appender::Limit
      log4perl.appender.Limiter.appender     = Mailer
      log4perl.appender.Limiter.block_period = 3600
    );

    Log::Log4perl->init(\$conf);
    WARN("This message will be sent immediately");
    WARN("This message will be delayed by one hour.");
    sleep(3601);
    WARN("This message plus the last one will be sent now");

=head1 DESCRIPTION

=over 4

=item C<appender>

Specifies the name of the appender used by the limiter. The
appender specified must be defined somewhere in the configuration file,
not necessarily before the definition of 
C<Log::Log4perl::Appender::Limit>.

=item C<block_period>

Period in seconds between delivery of messages. If messages arrive in between,
they will be either saved (if C<accumulate> is set to a true value) or
discarded (if C<accumulate> isn't set).

=item C<persistent>

File name in which C<Log::Log4perl::Appender::Limit> persistently stores 
delivery times. If omitted, the appender will have no recollection of what
happened when the program restarts.

=back

If the appender attached to C<Limit> uses C<PatternLayout> with a timestamp
specifier, you will notice that the message timestamps are reflecting the
original log event, not the time of the message rendering in the
attached appender. Major trickery has applied to accomplish this (Cough!).

=head1 DEVELOPMENT NOTES

C<Log::Log4perl::Appender::Synchronized> is a I<composite> appender.
Unlike other appenders, it doesn't log any messages, it just
passes them on to its attached sub-appender.
For this reason, it doesn't need a layout (contrary to regular appenders).
If it defines none, messages are passed on unaltered.

Custom filters are also applied to the composite appender only
They are I<not> applied to the sub-appender. Same applies to appender
thresholds. This behaviour might change in the future.

=head1 LEGALESE

Copyright 2004 by Mike Schilli, all rights reserved.
This program is free software, you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 AUTHOR

2004, Mike Schilli <m@perlmeister.com>
