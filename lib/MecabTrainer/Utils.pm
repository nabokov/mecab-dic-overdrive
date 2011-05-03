package MecabTrainer::Utils;

use strict;
use base qw(Exporter);

use Encode;
use Encode::JP;
use Unicode::Normalize;
use Unicode::RecursiveDowngrade;
use HTML::Entities;

use DBI;
use Data::Dumper;
use Time::Piece;
use Log::Log4perl qw(:easy);
use Time::HiRes qw(gettimeofday tv_interval);


our @EXPORT_OK = (
                    qw(normalize_text strip_html
                       db2internal internal2db source2internal internal2console console2internal web2internal internal2web
                       init_logger db_error init_db
                       split_csv join_csv add_element_to_csv
                   )
                );
our %EXPORT_TAGS = (
    all => \@EXPORT_OK,
);

#
# 文字コード調整関係
#

sub db2internal {
    return Encode::decode('utf8', $_[0]);
}

sub internal2db {
    return Encode::encode('utf8', $_[0]);
}

sub source2internal {
    return Encode::decode('utf8', $_[0]);
}

sub internal2console {
    return Encode::encode('utf8', $_[0]);
}

sub console2internal {
    return Encode::decode('utf8', $_[0]);
}

sub db2console {
    return &internal2console(&db2internal($_[0]));
}

sub web2internal {
    return Encode::decode('utf8', $_[0]);
}

sub internal2web {
    return Encode::encode('utf8', $_[0]);
}

#
# ログ関連
#

Log::Log4perl::Layout::PatternLayout::add_global_cspec('E',
    sub {
        our $LAST_MESSAGE_TIME;

        my $mes = sprintf("%.3f sec from start", tv_interval($Log::Log4perl::Layout::PatternLayout::PROGRAM_START_TIME));
        if ($LAST_MESSAGE_TIME) {
            $mes .= sprintf(", %.3f sec from last msg." , tv_interval($LAST_MESSAGE_TIME));
        }
        $LAST_MESSAGE_TIME = [gettimeofday];
        return $mes;
    });

Log::Log4perl::Layout::PatternLayout::add_global_cspec('B',
    sub {
        return "$0, pid $$";
    });

sub init_logger {
    my ($path, $catch_stderr) = @_;

    if ($catch_stderr) {
        $SIG{__DIE__} = sub {
            $Log::Log4perl::caller_depth++;
            LOGDIE @_;
        };
        $SIG{__WARN__} = sub {
            local $Log::Log4perl::caller_depth =
                $Log::Log4perl::caller_depth + 1;
            WARN @_;
        };
    }

    Log::Log4perl->init_once($path);
    return Log::Log4perl->get_logger();
}


#
# DB関連
#

our $DBH;
sub init_db {
    my ($datasource) = @_;

    my $key = join(',',@$datasource);
    if (!$DBH->{$key}) {
        $DBH->{$key} = DBI->connect(@$datasource, { RaiseError => 1, AutoCommit => 1 }) or &db_error;
        $DBH->{$key}->do(q{set names 'utf8'}) or &db_error;
    }
    return $DBH->{$key};
}

sub db_error {
    my $logger = Log::Log4perl->get_logger();
    my $message = $DBI::errstr;

    $logger->logcroak($message);
}

# csv関連

sub split_csv {
    my ($feature) = @_;

    my @features;
    for my $f ($feature =~ /(?:^|,)("(?:[^"]|"")*"|[^,]*)/g) {
        if ($f =~ /^"(.*)"$/) {
            $f = $1;
            $f =~ s/""/"/g;
        }
        push @features, $f;
    }
    return @features;
}

sub join_csv {
    my (@features) = @_;

    my @f;
    for my $f (@features) {
        if ($f =~ /"/ or $f =~ /,/ or $f eq ' ') {
            $f =~ s/"/""/g;
            $f = qq{"$f"};
        }
        push @f, $f;
    }
    return join(',', @f);
}

sub add_element_to_csv {
    my ($csv, $element) = @_;

    return $csv unless ($element);

    my @s = split_csv($csv);
    unless (member_of($element, @s)) {
        push @s, $element;
        $csv =join_csv(@s);
    }
    return $csv;
}

1;
