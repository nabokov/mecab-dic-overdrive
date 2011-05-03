package MecabTrainer::MeCab;

#
# Text::MeCab ラッパー
#

use strict;
use Text::MeCab qw(:all);
use Encode;
use Encode::JP;

use MecabTrainer::Utils qw(:all);
use MecabTrainer::Config;

my $conf = MecabTrainer::Config->new;
my $logger = init_logger($conf->{log_conf});

my $MAX_DB_KEY_LENGTH = 128;
my $FEATURES_STEM_INDEX = 6;
my @DELIM = map source2internal($_), ('記号', '句点');

sub new {
    my $class = shift;
    my $self = {
        mecab_kanji_code => 'utf8',
        dicdir => $conf->{dicdir},
        userdic => $conf->{mecab_default_userdic},

        mecab_command_opts => [],
        @_
    };
    bless $self, $class;

    # set mecab instance
    if (scalar @{$self->{mecab_command_opts}} > 0) {
        $self->{mecab} = new Text::MeCab( @{$self->{mecab_command_opts}} );
    } else {
        my $mecab_opts;
        $mecab_opts->{dicdir} = $self->{dicdir} if ($self->{dicdir});
        $mecab_opts->{userdic} = $self->{userdic} if ($self->{userdic});
        $self->{mecab} =new Text::MeCab($mecab_opts);

        ## 0.92->0.93 でコマンドの最初の引数が無視されたりされなかったりする問題があるので、
        ## 最初に無難な引数をつけてコマンド引数型で呼び出す → そうした場合(のみ).mecabrcの設定が上書きされる(追加にならない)???
#        my @mecab_opts = ('--nbest=1');
#        for (qw(userdic dicdir)) {
#            push @mecab_opts, "--$_=".$self->{$_} if ($self->{$_});
#        }
#        $self->{mecab} =new Text::MeCab( @mecab_opts );
    }
    return $self;
}

sub parse {
    my ($self, $text) = @_;

    my $mecab = $self->{mecab};

    my @nodes;

#    my $node = $mecab->parse($self->internal2mecab($text)); ### なんか utf フラグ付きでいいらしい ??
    my $node = $mecab->parse($text);
    while ($node) {
         my %hash = map { $_ => $node->$_ }
             qw(id rcattr lcattr stat isbest alpha beta prob wcost cost);

         my $surface = ''.$self->mecab2internal($node->surface); ### でも 返りはフラグ付け直し必要 ???
         my $feature = ''.$self->mecab2internal($node->feature);

         my @f = split_csv($feature);
         ($surface, @f) = $self->normalize_features($surface, @f);
         $feature = join_csv(@f);

          %hash = (
              %hash,
              surface => $surface,
              stem => $self->get_stem(@f),
              feature => $feature,
              features => [ @f ],
              wikipedia_id => $self->get_wikipedia_id(@f),
              is_eos => $self->is_eos($node), # BOS/EOSマーカーの場合1
              is_sentence_delim => $self->is_delim(@f), # 文章の区切り目。現在は「。」のみ反応
              is_unknown => $self->is_unknown($node),
              db_key => $self->get_db_key(@f)
          );
         push @nodes, { %hash };

         $node = $node->next;
    };

    return @nodes;
}

sub internal2mecab {
    my ($self, $text) = @_;
    return Encode::encode($self->{mecab_kanji_code}, $text);
}


sub mecab2internal {
    my ($self, $text) = @_;
    return Encode::decode($self->{mecab_kanji_code}, $text);
}

#
# class methods
#

sub normalize_features {
    my ($class, $surface, @f) = @_;

    $surface =~ s/[\n\r]//g;
#    $surface = &Utils::normalize_text($surface);

    for (0..5) { $f[$_] = '*' if !($f[$_]) };
    $f[$FEATURES_STEM_INDEX] = $surface if (!$f[$FEATURES_STEM_INDEX] or $f[$FEATURES_STEM_INDEX] eq '*');

    return ($surface, @f);
}

sub create_dic_line {
    my ($class, $surface, $lcattr, $rcattr, $cost, $features, $opts) = @_;

    my @f = (ref($features) eq 'ARRAY') ? @$features : split_csv($features);

    ($surface, @f) = $class->normalize_features($surface, @f);

    if ($opts->{wikipedia_id} and !$class->get_wikipedia_id(@f)) {
        push @f, 'Wikipedia:'.$opts->{wikipedia_id};
    }

    return join_csv($surface, $lcattr, $rcattr, $cost, @f);
}

sub get_db_key {
    my $class = shift;

    return $class->get_db_key_short(@_);
#    return $class->get_db_key_long(@_);
}

# features の前から4つで区別する用
# 「名詞・固有名詞」や「名詞・一般」が別エントリになる
sub get_db_key_long {
    my ($class, @f) = @_;

#    my $db_key = $class->join_csv(@f[0..6]);

# morphemeの区別の方針
# ・区別すべきものは別idで保存する
# ・「あびる優」と「水をあびる」を一緒にしないように、品詞まで含めてユニークキーにする。
# ・上の副作用として、名詞の一部や、最初未知語として検出されて後に辞書登録されたものなどは
#   「名詞・固有名詞,一般・○」と「名詞・人名,一般・○」のようにふたつに分かれてしまう場合がある。
# ・↑なので、折衝案として、品詞(feature)の大分類だけを使って区別する (db_key_short)
#
# feature の例:
# 名詞,固有名詞,一般,*,*,*,a
# 名詞,サ変接続,*,*,*,*,脱退,ダッタイ,ダッタイ
# 名詞,形容動詞語幹,*,*,*,*,まじ,マジ,マジ
# 助詞,格助詞,連語,*,*,*,って,ッテ,ッテ
# 動詞,自立,*,*,五段・ワ行促音便,基本形,叶う,カナウ,カナウ
# 動詞,自立,*,*,五段・ワ行促音便,連用形,叶う,カナイ,カナイ
# 動詞,自立,*,*,サ変・スル,連用形,する,シ,シ
# 動詞,自立,*,*,一段,未然形,使える,ツカエ,ツカエ

# is_unknown の時でも feature は推測されてつけられる。

    my $db_key = join_csv(@f[0..3], $f[$FEATURES_STEM_INDEX]);

    if (length($db_key) > $MAX_DB_KEY_LENGTH) {
        # $logger->warn("db_key too long:[".internal2console($db_key)."]");
        return undef;
    }

    return $db_key;
}

# features の最初のひとつだけで区別する用
sub get_db_key_short {
    my ($class, @f) = @_;

    my $db_key = join_csv(@f[0], $f[$FEATURES_STEM_INDEX]);

    if (length($db_key) > $MAX_DB_KEY_LENGTH) {
        # $logger->warn("db_key too long:[".internal2console($db_key)."]");
        return undef;
    }

    return $db_key;
}


sub get_stem {
    my ($class, @f) = @_;

    return $f[$FEATURES_STEM_INDEX];
}

sub get_wikipedia_id {
    my ($class, @f) = @_;

    for (-2..-1) {
        if (@f[$_]=~/Wikipedia:(.*)/) { return $1 }
    }
    return undef;
}

sub is_eos {
    my ($class, $node) = @_;
    return ($node->stat == MECAB_EOS_NODE or $node->stat == MECAB_BOS_NODE);
}

sub is_delim {
    my ($class, @f) = @_;
    return ($f[0] eq $DELIM[0] and $f[1] eq $DELIM[1]);
}

sub is_unknown {
    my ($class, $node) = @_;
    return ($node->stat == MECAB_UNK_NODE);
}


1;
