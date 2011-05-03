package MecabTrainer::GenDic::Kaomoji;

#
# http://www.geocities.co.jp/SiliconValley-Cupertino/3080/
# あたりの顔文字データを記号/一般で dic 化する用
#

use base qw(MecabTrainer::GenDic);
use strict;

use MecabTrainer::Config;
use MecabTrainer::Utils qw(:all);

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

        from_file => $conf->{dic_aux_files_dir} .'/kaomoji.tsv',
        in_kanji_code => 'utf-8',
        to_file => $conf->{dic_aux_files_dir} . '/kaomoji.csv',
        dic_file => $conf->{dic_aux_files_dir} . '/kaomoji.dic',
        morphs => [ { feature => source2internal('記号,一般,*,*,*,*,*') } ],

        # Wikipediaより優先(括弧などの記号がほかので上書きされちゃうので)
        userdic => $conf->{dic_aux_files_dir} . '/wikipedia.dic',
    };
}

sub read_next_line {
    my $self = shift;

    my $fh = $self->{fh};
    if (my $line = <$fh>) {
        my $line = Encode::decode($self->{in_kanji_code}, $line);
        my @fields = split(/\t/, $line);
        return {
            word => $fields[1],
            default_morph => $self->{morphs}->[0]
        };
    }

    else {
        return undef;
    }
}

sub skip_word {
    # 顔文字なので記号のみの語でも登録する。
    return 0;
}

sub DESTROY {
    my $self = shift;

    $self->{fh}->close;
}

1;
