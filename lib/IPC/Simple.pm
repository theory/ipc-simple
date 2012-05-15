package IPC::Simple;

use 5.008001;
use strict;
use warnings;
use IPC::Open3;
use Carp;
use Config;
use POSIX qw(WIFEXITED WEXITSTATUS WIFSIGNALED WTERMSIG);
use constant UNDEFINED_POSIX_RE => qr{not (?:defined|a valid) POSIX macro|not implemented on this architecture};
use constant EXIT_ANY_CONST => -1;			# Used internally

my @Signal_from_number = split(' ', $Config{sig_name});

# TODO: Ideally, $NATIVE_WCOREDUMP should be a constant.

my $NATIVE_WCOREDUMP;

eval { POSIX::WCOREDUMP(1); };

if ($@ =~ UNDEFINED_POSIX_RE) {
	*WCOREDUMP = sub { $_[0] & 128 };
        $NATIVE_WCOREDUMP = 0;
} elsif ($@) {
    croak sprintf q{IPC::Simple does not understand the POSIX error '%s'.  Please check http://search.cpan.org/perldoc?IPC::Simple to see if there is an updated version.  If not please report this as a bug to http://rt.cpan.org/Public/Bug/Report.html?Queue=IPC-System-Simple}, $@;
} else {
	# POSIX actually has it defined!  Huzzah!
	*WCOREDUMP = \&POSIX::WCOREDUMP;
        $NATIVE_WCOREDUMP = 1;
}

sub new {
    my $class = shift;
    my $cmd   = shift;
    croak sprintf q{Entirely blank command passed: "%s"}, $cmd
        unless defined $cmd && $cmd ne '';

    my $in  = IO::File::PipeWriter->new($cmd);
    my $out = IO::File->new;
    my $err = IO::File->new;

    use Data::Dump; ddx [$cmd, @_];
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
        exitval => -1,
    } => $class;
}

sub input   { shift->{input}   }
sub output  { shift->{output}  }
sub errput  { shift->{errput}  }
sub exitval { shift->{exitval} }

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
        $self->_process_child_error($?, [0]);
    };
    if ($@) {
        die unless $@ eq "alarm\n";
        croak sprintf 'Timeout expired waiting for "%s" to finish', $self->{cmd};
    }
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

sub eof {
    shift->input->eof;
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

# This subroutine performs the difficult task of interpreting
# $?.  It's not intended to be called directly, as it will
# croak on errors, and its implementation and interface may
# change in the future.

sub _process_child_error {
    my ($self, $child_error, $valid_returns) = @_;
	
	$self->{exitval} = -1;

	my $coredump = WCOREDUMP($child_error);

    # There's a bug in perl 5.10.0 where if the system does not provide a
    # native WCOREDUMP, then $? will never contain coredump information. This
    # code checks to see if we have the bug, and works around it if needed.

    if ($] >= 5.010 and not $NATIVE_WCOREDUMP) {
        $coredump ||= WCOREDUMP( ${^CHILD_ERROR_NATIVE} );
    }

	if ($child_error == -1) {
		croak sprintf(q{"%s" failed to start: "%s"}, $self->{cmd}, $!);

	} elsif ( WIFEXITED( $child_error ) ) {
		$self->{exitval} = WEXITSTATUS( $child_error );
        return $self if $self->{exitval} == 0;

	} elsif ( WIFSIGNALED( $child_error ) ) {
		my $signal_no   = WTERMSIG( $child_error );
		my $signal_name = $Signal_from_number[$signal_no] || "UNKNOWN";

		croak sprintf(
            q{"%s" died to signal "%s" (%d)%s},
            $self->{cmd}, $signal_name, $signal_no,
            ($coredump ? " and dumped core" : "")
        );
	}

	croak sprintf(
        q{Internal error in IPC::System::Simple: "%s"},
        qq{'$self->{cmd}' ran without exit value or signal}
    );

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

First of all, if all you want is a better C<system> or backticks interface, go
use L<IPC::System::Simple>, instead.

IPC::Simple provides a simple, file-handle-based interface for executing
commands. You can read the command's output, write to its input, or read its
errors. This is just like L<IPC::Open3>, except that you don't have to worry
about trapping errors or how to deal with platform-specific error handling.
IPC::Simple takes care of all that for you (well, it tries to), and turns all
such errors into exceptions.

IPC::Simple also provides a few convenience methods to the input and output
file handles, so you can just read or write as appropriate, without thinking
too much about what file handle to mess with.

=head1 Interface

=head2 Constructor

=head3 C<new>

  my $ipc = IPC::Simple->new('some_command', @args);

Executes the command and its arguments, hooking up the C<input>, C<output>,
and C<errput> file handles, and returns the resulting IPC::Simple object. If
any errors are encountered executing the command, an exception will be thrown.

=head2 Accessors

=head3 C<input>

  my $input = $ipc->input;
  $input->print('hello');

Returns an IO::File::PipeWriter handle for the command's input (C<STDIN>).
This object is a subclass of L<IO::File> and supports all the same methods.
Notably, when write methods are called, an error handler throws any exceptions
errors from the child process. You are therefor encouraged to execute write
actions as method calls, rather than core functions. In other words, do this:

  $input->say('yes');

Rather than this:

  say $input 'yes';

=head3 C<output>

  my $output = $ipc->output;
  print while <$output>;

Returns the output file handle (C<STDOUT>) for the command. This is an
L<IO::File> object. Use it to read the command's output.

=head3 C<errput>

  my $errput = $ipc->errput;
  print while <$errput>;

Returns the error output file handle (C<STDERR>) for the command. This is an
L<IO::File> object. Use it to read the command's error output.

=head2 Instance Methods

=head3 C<close>

  $ipc->close;

Close the connection to the command. This closes all three file handles. In
the event that any fails to close, an exception will be thrown.

=head2 Delegate Methods

These methods provide convenient access to the corresponding methods on the
input or output handles, as appropriate. This makes it simple to simply write
to and read from the command without worrying about which handle to use. Only
the most commonly-used methods are provided; call directly on the appropriate
file handles for other methods.



=head3 C<getc>

  my $c = $ipc->getc;

Calls C<getc> on the command's output file handle.

=head3 C<read>

 $ipc->read(my $buf, 1024);

Calls C<read> on the command's output file handle.

=head3 C<sysread>

 $ipc->sysread(my $buf, 1024);

Calls C<sysread> on the command's output file handle.

=head3 C<getline>

  my $line = $ipc->getline;

Calls C<getline> on the command's output file handle.

=head3 C<getlines>

  my @lines = $ipc->getlines;

Calls C<getlines> on the command's output file handle.

=head3 C<eof>

  say 'done' if $ipc->eof;

Calls C<eof> on the command's input file handle.

=head3 C<print>

  $ipc->print('yes');

Calls C<print> on the command's input file handle.

=head3 C<printf>

  $ipc->printf('%u minutes', 12);

Calls C<printf> on the command's input file handle.

=head3 C<say>

  $ipc->say('yes');

Calls C<say> on the command's input file handle.

=head3 C<write>

  $ipc->write;

Calls C<write> on the command's input file handle.

=head3 C<syswrite>

  $ipc->syswrite($buf, 1024);

Calls C<syswrite> on the command's input file handle.

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
