# derived from Pickles::Config
# https://github.com/ikebe/Pickles/blob/master/lib/Pickles/Config.pm

package MecabTrainer::Config;
use strict;
use File::Spec;
use Path::Class;
use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors( qw(appname home) );

sub new {
    my $class = shift;
    my %args = @_;
    my $self = bless {}, $class;

    $self->{appname} = _appname( $class );
    $self->setup_home( $args{home} );
    $self->{env} = $args{env} || _env_value('ENV', $self->appname);
    $self->{base} = $args{base} || _env_value('CONFIG', $self->appname);
    $self->{ACTION_PREFIX} = '';
    $self->load_config;
    $self;
}

sub get {
    my( $self, $key, $default ) = @_;
    return defined $self->{$key} ? $self->{$key} : $default;
}

sub setup_home {
    my( $self, $home ) = @_;
    my $dir = 
        $home || _env_value( 'HOME', $self->appname );
    if ( $dir ) {
        $self->{home} = dir( $dir );
    }
    else {
        my $class = ref $self;
        (my $file = "$class.pm") =~ s|::|/|g;
        if (my $inc_path = $INC{$file}) {
            (my $path = $inc_path) =~ s/$file$//;
            my $home = dir($path)->absolute->cleanup;
            $home = $home->parent while $home =~ /b?lib$/;
            $self->{home} = $home;
        }
    }
}

sub load_config {
    my $self = shift;
    my $files = $self->get_config_files;
    my %config;

    # In 5.8.8 at least, putting $self in an evaled code produces
    # extra warnings (and possibly break the behavior of __path_to)
    # so we create a private closure, and plant the closure into
    # the generated packes
    my $path_to = sub { $self->path_to(@_) };

    for my $file( @{$files} ) {
        # only do this if the file exists
        next unless -e $file;

        my $pkg = $file;
        $pkg =~ s/([^A-Za-z0-9_])/sprintf("_%2x", unpack("C", $1))/eg;

        my $fqname = sprintf '%s::%s', ref $self, $pkg;
        { # XXX This is where we plant that closure
            no strict 'refs';
            no warnings 'redefine';
            *{"$fqname\::__path_to"} = $path_to;
        }

        my $config_pkg = sprintf <<'SANDBOX', $fqname;
package %s;
{
    my $conf = do $file or die $!;
    $conf;
}
SANDBOX
        my $conf = eval $config_pkg || +{};
        if ($@) {
            warn "Error while trying to read config file $file: $@";
        }
        %config = (
            %config,
            %{$conf},
        );
    }
    $self->{__FILES} = $files;
    $self->{__TIME} = time;
    for my $key( keys %config ) {
        $self->{$key} = $config{$key};
    }
    \%config;
}

sub get_config_files {
    my $self = shift;
    my @files;

    if ( $self->{base} ) {
        if ( $self->{base} !~ m{^/} ) {
            $self->{base} = $self->path_to( $self->{base} );
        }
        push @files, $self->{base};
    }
    else {
        my @base_files = ( File::Spec->catfile('etc', 'config.pl'), 'config.pl' );
        foreach my $f (@base_files) {
            my $base = $self->path_to($f);
            push @files, $base if -e $base;
        }
    }

    if ( my $env = $self->{env} ) {
        my @env_files;
        for my $file( @files ) {
            my ($v, $d, $fname) = File::Spec->splitpath( $file );
            $fname =~ s/(\.[^\.]+)?$/$1 ? "_%s$1" : "%s"/e;
            my $template = File::Spec->catpath( $v, $d, $fname );
            my $filename = sprintf $template, $env;
            if ( $filename !~ m{^/}) {
                $filename = $self->path_to( $filename );
            }
            push @env_files, $filename;

        }
        push @files, @env_files;
    }

    return \@files;
}

sub path_to {
    my( $self, @path ) = @_;
    file( $self->home, @path )->stringify;
}

sub _env_name {
    my( $name, $appname ) = @_;
    $appname =~ s/::/_/g;
    return uc(join('_', $appname, $name));
}

sub _env_value {
    return $ENV{ _env_name(@_) };
}

sub _appname {
    my $class = shift;
    if (my $appname = $ENV{APPNAME}) {
        return $appname;
    }
    if ( $class =~ m/^(.*?)::(Context|Config)$/ ) {
        my $appname = $1;
        return $appname;
    }
    Carp::croak("Could not determine APPNAME from either %ENV or classname ($class)");
}

1;
