package MecabTrainer::NormalizeText;

use strict;
use base qw(Exporter);

use Encode;
use Encode::JP;
use Unicode::Normalize;
use HTML::Entities;

use MecabTrainer::Config;
use MecabTrainer::Utils qw(:all);

my $conf = MecabTrainer::Config->new;
my $logger = init_logger($conf->{log_conf});

my @AVAILABLE_OPTS = qw(decode_entities strip_html strip_nl strip_single_nl
                unify_whitespaces wave2tilde wavetilde2long fullminus2long
                dashes2long drawing_lines2long unify_long_repeats nfkc lc);

sub new {
    my $class = shift;
    my $self = bless {}, $class;

    # 例: new NormalizeText('nfkc', 'lc')
    #
    # あとで説明書く

    my ($opts) = @_;
    $self->{converters} = [];

    my %set= map { $_ => 1 } @$opts;
    unless ($set{none}) {
        for (@AVAILABLE_OPTS) {
            if ($set{$_}) {
                my $coder = "__$_";
                push @{$self->{converters}}, $self->$coder;
                delete($set{$_});
            }
        }
        if (keys(%set)) {
            $logger->warn("unrecognized option(s):".join(',', keys(%set)));
            $logger->warn("avaiable options are:".join(',', @AVAILABLE_OPTS));
        }
    }

    return $self;
}

sub normalize {
    my ($self, $str) = @_;

    return '' unless defined($str);

    map { $str = $_->($str) } @{$self->{converters}};
    return $str;
}

sub __decode_entities {
    return sub { decode_entities(shift) }
}
sub __strip_html {
    return sub {
        my $str = shift;
        my $max_length = 20000; # ↓で seg fault するのを防ぐために，長過ぎるテキストはカット
        $str = substr($str, 0, $max_length) if (length($str) > $max_length);

        $str =~ s/<br(\s+(\"[^\"]*\"|[^>])*)?>[\n\r]?/\n/go;
        $str =~ s/<\/?p(\s+(\"[^\"]*\"|[^>])*)?>[\n\r]?/\n/go;
        $str =~ s/<(\"[^\"]*\"|[^>])*>//go; ### これ，長い文章のときに seg fault することがあるようだ。注意。
        $str =~ s/&#?[a-zA-Z0-9]+;?//go;

        $str;
    }
}
sub __strip_nl {
    return sub { my $str = shift; $str =~ s/[\n\r]//go; $str; }
}
sub __strip_single_nl {
    return sub { my $str = shift; $str =~ s/([\n\r]?)([\n\r]+)/$1/go; $str; }
}
sub __unify_whitespaces {
    return sub { my $str = shift; $str =~ s/\p{White_Space}/ /go; $str; }
}
sub __wave2tilde {
    my $tilde = chr(hex("FF5E"));
    my $wave = chr(hex("301C"));
    return sub { my $str = shift; $str =~ s/$wave/$tilde/ego; $str; }
}
sub __wavetilde2long {
    my $tilde = chr(hex("FF5E"));
    my $wave = chr(hex("301C"));
    my $long = chr(hex("30FC"));
    return sub { my $str = shift; $str =~ s/[$wave$tilde]/$long/ego; $str; }
}
sub __fullminus2long {
    my $minus = chr(hex("2212"));
    my $long = chr(hex("30FC"));
    return sub { my $str = shift; $str =~ s/$minus/$long/ego; $str; }
}
sub __dashes2long {
    my $long = chr(hex("30FC"));
    return sub { my $str = shift; $str =~ s/\p{Dash}/$long/ego; $str; }
}
sub __drawing_lines2long {
    my $dr_lines = join '', map chr(hex($_)), qw(2500 2501 254C 254D 2574 2576 2578 257A);
    my $long = chr(hex("30FC"));
    return sub { my $str = shift; $str =~ s/[$dr_lines]/$long/ego; $str; }
}
sub __unify_long_repeats {
    my $long = chr(hex("30FC"));
    return sub { my $str = shift; $str =~ s/$long{2,}/$long/ego; $str; }
}
sub __nfkc {
    return sub { Unicode::Normalize::NFKC(shift); }
}
sub __lc {
    return sub { lc(shift); }
}


1;
