package MecabTrainer::GenDic::SimpleList;

#
# シンプルなやつ。とりあえず辞書登録したい単語をテキストに列挙しておけばよい。
#

use base qw(MecabTrainer::GenDic);
use strict;

use MecabTrainer::Utils qw(:all);
use MecabTrainer::Config;

my $conf = MecabTrainer::Config->new;
my $logger = init_logger($conf->{log_conf});

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);

    open $self->{fh}, $self->{from_file};
    return $self;
}

sub defaults {
    my $class = shift;
    return +{
        %{$class->SUPER::defaults},

        from_file => $conf->{dic_aux_files_dir} .'/simple_list.txt',
        in_kanji_code => 'utf-8',
        to_file => $conf->{dic_aux_files_dir} . '/simple_list.csv',
        dic_file => $conf->{dic_aux_files_dir} . '/simple_list.dic',
        morphs => [ { feature => source2internal('名詞,固有名詞,一般,*,*,*,*') } ],
    };
}

sub read_next_line {
    my $self = shift;

    my $fh = $self->{fh};
    if (my $line = <$fh>) {
        my $line = Encode::decode($self->{in_kanji_code}, $line);
        chomp $line;
        return {
            word => $line,
            default_morph => $self->{morphs}->[0]
        };
    }

    else {
        return undef;
    }
}

sub skip_word {
    return 0;
}

sub DESTROY {
    my $self = shift;

    $self->{fh}->close;
}

1;
