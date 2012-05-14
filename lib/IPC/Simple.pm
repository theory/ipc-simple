package IPC::Simple;

use 5.008001;
use strict;
use warnings;
use IPC::Open3;
use Carp;

sub new {
    my $class = shift;
    my $cmd   = shift;
    croak sprintf q{Entirely blank command passed: "%s"}, $cmd
        unless defined $cmd && $cmd ne '';

    my $in  = IO::File::PipeWriter->new($cmd);
    my $out = IO::File->new;
    my $err = IO::File->new;

    my $pid = eval { open3 $in, $out, $err, $cmd, @_ };
    # Handle errors.
    if ($@) {
        $@ =~ s/^open3:\s*//;
        croak;
    }

    # If STDERR has any output, it's an exec error, so die.
    croak "Unable to disable blocking on errput: $!"
        unless defined $err->blocking(0);
    if (my $error = $err->getline) {
        # Setting $! to our child error number gives us nice looking strings
        # when printed (according to IPC::System::Simple).
        local $! = $error;
        croak sprintf q{"%s" failed to start: "%s"}, $cmd, $!;
    }
    croak "Unable to enable blocking on errput: $!"
        unless defined $err->blocking(1);

    # We good, go!
    return bless {
        cmd     => $cmd,
        input   => $in,
        output  => $out,
        errput  => $err,
        pid     => $pid,
    } => $class;
}

sub input  { shift->{input}  }
sub output { shift->{output} }
sub errput { shift->{errput} }

sub close {
    my $self = shift;
    return $self if $self->{closed}++;
    for my $fh (qw(input output errput)) {
        $self->{$fh}->close or die sprintf q{Error closing "%s" %s: %s\n},
            $self->{cmd}, $fh, $!;
    }
    eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
        alarm 2;
        waitpid $self->{pid}, 0;
        alarm 0;
        croak sprintf '"%s" unexpectedly returned exit value %d', $self->{cmd}, $? >> 8
            if $?;
    };
    if ($@) {
        die unless $@ eq "alarm\n";
        croak sprintf 'Timeout expired waiting for "%s" to finish', $self->{cmd};
    }
}

sub eof {
    shift->input->eof;
}

sub getc {
    shift->output->getc;
}

sub read {
    shift->output->read(@_);
}

sub sysread {
    shift->output->sysread(@_);
}

sub getline {
    shift->output->getline;
}

sub getlines {
    shift->output->getlines;
}

sub print {
    shift->input->print(@_);
}

sub printf {
    shift->input->printf(@_);
}

sub say {
    shift->input->say(@_);
}

sub write {
    shift->input->write(@_);
}

sub syswrite {
    shift->input->syswrite(@_);
}

package IO::File::PipeWriter;
use base 'IO::File';
use Carp;

sub new {
    my ($class, $cmd) = @_;
    my $self = $class->SUPER::new;
    ${*$self}{'io_file_pipewriter_cmd'} = $cmd;
    return $self;
}

BEGIN {
    # Install a PIPE error handler for each write method.
    # XXX Do something for Windows, too?
    for my $meth (qw(format_write print printf say syswrite write)) {
        eval qq{
            sub $meth {
                my \$self = shift;
                local \$SIG{PIPE} = sub {
                    croak "Error writing to \${*\$self}{'io_file_pipewriter_cmd'}"
                };
                \$self->SUPER::$meth(\@_);
            }
        };
    }
}

1;
__END__

=head1 Name

IPC::Simple - Simple File-handle based command execution, with detailed diagnostics

=head1 Synopsis

  use IPC::Simple;

  my $ipc = IPC::Simple->new('some_command');
  $ipc->say('hello');
  $ipc->say('goodbye');
  say $ipc->getline;
  $ipc->close;

=head1 Description



=head1 Interface

=head2 Constructor

=head3 C<new>



=head2 Accessors

=head3 C<input>

=head3 C<output>

=head3 C<errput>

=head2 Instance Methods

=head3 C<close>

=head3 C<eof>

=head3 C<getc>

=head3 C<getline>

=head3 C<getlines>

=head3 C<print>

=head3 C<printf>

=head3 C<read>

=head3 C<say>

=head3 C<sysread>

=head3 C<syswrite>

=head3 C<write>

=head1 See Also

=over

=item * L<perlipc>

=item * L<IPC::Open3>

=item * L<IPC::Open2>

=item * L<IPC::Cmd>

=item * L<IPC::Run>

=item * L<IPC::Run3>

=item * L<IPC::System::Simple>

=back

=head1 Support

This module is managed in an open
L<GitHub repository|http://github.com/theory/ipc-simple/>. Feel free to
fork and contribute, or to clone L<git://github.com/theory/ipc-simple.git>
and send patches!

Found a bug? Please L<post|http://github.com/theory/ipc-simple/issues> or
L<email|mailto:bug-ipc-simple@rt.cpan.org> a report!

=head1 Authors

David E. Wheeler <david@justatheory.com>

=head1 Copyright and License

Copyright (c) 2012 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
