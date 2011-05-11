package MecabTrainer::GenDic::WikipediaFile;

# Wikipedia の ダンプファイル jawiki-latest-page.sql.gz から直接読み込む。
#
# ・--target=wikipedia と違ってDBを介さないので楽。ただしダンプ形式がちょっとでも変わるとダメになるので
#   その場合は --target=wikipedia の方を使うこと。
# ・from_file に .gz を直接指定する場合は zcat 必須。

use base qw(MecabTrainer::GenDic);
use strict;

use MecabTrainer::Config;
use MecabTrainer::Utils qw(:all);

my $conf = MecabTrainer::Config->new;
my $logger = init_logger($conf->{log_conf});

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);

    my $in = $self->{from_file};
    if (-f "$in.gz") {
        if (`which gzcat`) {
            $in = "gzcat $in.gz|";
        } elsif (`which zcat`) {
            $in = "zcat $in.gz|";
        } else {
            $logger->info(".gz found, but gzcat/zcat not available");
        }
    }

    open $self->{fh}, $in or $logger->logdie("open $in failed");
    return $self;
}

sub defaults {
    my $class = shift;
    return +{
        %{$class->SUPER::defaults},

        in_kanji_code => 'utf-8',
        from_file => $conf->{dic_aux_files_dir} .'/jawiki-latest-page.sql',
        to_file => $conf->{dic_aux_files_dir} . '/wikipedia.csv',
        dic_file => $conf->{dic_aux_files_dir} . '/wikipedia.dic',
        morphs => [ { feature => source2internal('名詞,固有名詞,一般,*,*,*,*') } ],
    };
}

sub read_next_line {
    my $self = shift;
    my $fh = $self->{fh};

    do {
        while ($self->{current_line} =~ /\G(?:INSERT INTO `page` VALUES )?\(([0-9]+),([0-9]+),'((?:[^']|\\')*)','([^']*)',([0-9\.]+),([0-9\.]+),([0-9\.]+),([^']+),'([^']+)',([0-9\.]+),([0-9\.]+)\),?/gc) {
            my ($id, $namespace, $title, $restrictions, $counter, $is_redirect, $is_new) = ($1, $2, $3, $4, $5, $6, $7);
            next unless ($namespace == 0);

            $title =~ s/\\(.)/$1/g;
            $title = $self->normalize_title($title);

            return {
                word => $title,
                additional_feature => { wikipedia_id => $id },
                default_morph => $self->{morphs}->[0]
            };
        }

        undef($self->{current_line});
        while (my $line = <$fh>) {
            next unless $line;
            $line = Encode::decode($self->{in_kanji_code}, $line);
            if ($line =~ /^INSERT INTO `page` VALUES/) {
                $self->{current_line} = $line;
                last;
            }
        }

    } while ($self->{current_line});

}

my @SKIP_WORDS = map {
    my $re = source2internal($_);
    qr/$re/;
} (
    # 親クラスと同様の理由で記号のみのエントリは除く
    '^[^\p{Letter}]+$',

     # こういう名前の特殊なページが多いので...当然，たまたま形式が一致した一般名詞も除外される。ネームスペース分けてくんないかな...
    '一覧$', '^必要とされている', 'とした.*作品$', 'にした.*作品$', 'の作品$', '^著名な', 'の人物$', 'した人物$', 'の登場人物$',

    # 年月日はいらないだろう
    '^\d+年$', '^\d+月\d+日$',
);
sub skip_word {
    my ($self, $word) = @_;

    for (@SKIP_WORDS) { return 1 if ($word =~ $_) }
    return 0;
}

sub DESTROY {
    my $self = shift;

    $self->{fh}->close;
}

sub normalize_title {
    my ($self, $title) = @_;

    # http://ja.wikipedia.org/wiki/Wikipedia:記事名の付け方

    $title = $1 if ($title =~ /(.*)_\(.*\)/);
    $title =~ s/_/ /g;

    return $title;
}

1;
