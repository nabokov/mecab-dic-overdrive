package MecabTrainer::GenDic;

#
# 辞書作成の手順を一般化する用
#

use strict;

use MecabTrainer::Config;
use MecabTrainer::Utils qw(:all);

use MecabTrainer::NormalizeText;

my $max_cost = 32768; # should be =< 32768
my $min_cost = 0;

my $conf = MecabTrainer::Config->new;
my $logger = init_logger($conf->{log_conf});

sub new {
    my $class = shift;
    my $self = bless {
        %{$class->defaults},
        @_
    }, $class;

    $self->{normalizer} = MecabTrainer::NormalizeText->new($self->{normalize_opts});
    return $self;
}

sub defaults {
    my $class = shift;
    return +{

        # ↓各子クラスでオーバーライドする

        morphs => [ { feature => source2internal('名詞,固有名詞,一般,*,*,*,*')} ],

        normalize_opts => $conf->{default_normalize_opts},

        dic_src_dir => $conf->{dic_src_dir},

        dicdir => $conf->{dicdir},

        idfile_kanji_code => $conf->{idfile_kanji_code}, # idfileの漢字コード=dic_src_dirにあるソースのエンコーディング
        out_kanji_code => $conf->{out_kanji_code}, # CSV出力時のエンコーディング(mecab-dict-indexが読み込む)
        dic_kanji_code => $conf->{dic_kanji_code}, # 辞書バイナリのエンコーディング(mecabが読み込む)

        mecab_dict_index => $conf->{mecab_dict_index},

#        from_file => 'new_words.tsv',
#        to_file => 'new_words.csv',
#        dic_file => 'new_words.dic',
    };
}

# 適宜、子クラスでオーバーライド
sub skip_word {
    my ($self, $word) = @_;

    # 以下の事情により、とりあえずデフォルトでは，記号のみから成るワードは除外
    # ・"名詞・一般"として登録するのが不適切。
    # ・特に一文字のやつを入れると、「)」などが本来の「記号」よりも優先されるようになってしまう。
    # 　また、英単語が一文字ずつバラバラに認識される。

    return ($word =~ /^[^\p{Letter}]+$/);
}

sub _prepare_mecab {
    my $self = shift;

    require MecabTrainer::MeCab;
    $self->{mecab} = new MecabTrainer::MeCab(
        dicdir => $self->{dicdir},
        userdic => $self->{userdic}
    );
}

sub read_next_line {
    my $self = shift;
    die 'abstract method : read_next_line';
}

sub all_morph_candidates {
    my $self = shift;

    return $self->{morphs};
}


# コスト計算の準備
# ・新語に使う形態素の形態素idを left-id.def と right-id.def から決定
# ・matrix.def から，その形態素が単独で出てくるときのコスト読み込み

sub prepare_costs {
    my $self = shift;

    $self->_prepare_mecab;

    $logger->info("prepareing base costs from dir:".$self->{dic_src_dir}.", expected encoding:".$self->{out_kanji_code});

    $self->_supply_ids($self->{dic_src_dir}."/left-id.def", "left_id");
    $self->_supply_ids($self->{dic_src_dir}."/right-id.def", "right_id");
    $self->_supply_base_cost;
}

sub _supply_ids {
    my ($self, $file, $attr) = @_;

    my $morphs = $self->all_morph_candidates;

    open FH, $file;
    while (my $line = <FH>) {
        $line = Encode::decode($self->{idfile_kanji_code}, $line);
        my ($id, $feature) = ($line =~ /^(\d+)\s+(.*)$/);

        for (@$morphs) {
            if ($_->{feature} eq $feature) {
                $_->{$attr} = $id;
                $logger->debug($attr . ":" . internal2console($_->{feature}) . ":$id");
                last;
            }
        }
    }
    close FH;


    for (@$morphs) {
        $logger->logdie("$attr not found for ". internal2console($_->{feature}))
            unless ($_->{$attr});
    }
}

sub _supply_base_cost {
    my ($self) = @_;

    my $morphs = $self->all_morph_candidates;
    my $file = $self->{dic_src_dir}.'/matrix.def';

    for my $morph (@$morphs) {
        my $target_id = $morph->{left_id};

        my $found_b = 0; my $found_e = 0;
        open FH, $file;
        while (my $line = <FH>) {
            if (!$found_b and my ($cost) = ($line =~ /^0\s+$target_id\s+([0-9\-]+)/)) {
                $morph->{base_cost} += $cost;
                $found_b = 1;
            }
            elsif (!$found_e and my ($cost) = ($line =~ /^$target_id\s+0\s+([0-9\-]+)/)) {
                $morph->{base_cost} += $cost;
                $found_e = 1;
            }
            last if ($found_b and $found_e);
        }
        close FH;
        $logger->logdie ("base cost for id:$target_id not found, file=[$file]") if (!$found_b or !$found_e);

        $morph->{cost_by_length} = $self->_prepare_cost_by_length($morph->{left_id}, $morph->{right_id});
    }
}

# 各語のコスト計算 & .csv 書き出し

sub write_csv {
    my $self = shift;

    $logger->info("writing csv to " .$self->{to_file});

    my $n_lines = 0;

    open CSV, ">".$self->{to_file};
    while (my $line = $self->read_next_line) {

        my $word = $self->{normalizer}->normalize($line->{word});
        $logger->debug(internal2console("normalize_text [$line->{word}] => [$word]"));
        next if ($self->skip_word($word));

        my $default_morph = $line->{default_morph};
        my $additional_feature = $line->{additional_feature};

        # コストと既存の辞書の該当エントリの内容(ある場合)取得
        my ($cost, $node) = $self->_get_cost($word);

        if ($node) {
            # 既存のいずれかの辞書に存在する語の場合
            $logger->debug("exisitng word:". internal2console($node->{surface}));

            print CSV Encode::encode($self->{out_kanji_code},
                                     $self->{mecab}->create_dic_line($node->{surface}, $node->{lcattr}, $node->{rcattr}, $node->{wcost}, $node->{features}, $additional_feature ));

        } else {
            # 既存の辞書にはない語の場合
            $logger->debug("new word:". internal2console($word));

            my $cost_by_length = $self->_get_cost_by_length($word, $default_morph);

            $cost = $cost - $default_morph->{base_cost};

            # ここで，既存の最低コストよりさらに低いコストを設定する。1だけ引くとか, 何割り引きとか ?
#            $cost -= 1;
            $cost -= int(1 + (($cost > 0) ? ($cost * 0.3) : ($cost *-0.3)));

            $logger->debug(internal2console($word).": estimated_cost:$cost, cost_by_legth:$cost_by_length");

            # 同じ長さの語の平均コストから集計したコストの方が小さければそっちを採用する
            $cost = $cost_by_length if ($cost_by_length < $cost);

            $cost = $max_cost if ($cost > $max_cost);
            $cost = $min_cost if ($cost < $min_cost);

            print CSV Encode::encode($self->{out_kanji_code},
                                     $self->{mecab}->create_dic_line($word, $default_morph->{left_id}, $default_morph->{right_id}, $cost, $default_morph->{feature}, $additional_feature ));

        }
        print CSV "\n";
        $n_lines ++;
    }
    close CSV;

    if ($n_lines > 0) {
        $logger->info("written $n_lines lines");
    } else {
        $logger->logdie("no lines written. can't continue");
    }
}

# 与えられた語を現在の辞書でparseした時の、最終コストを返す
# もし、現在の辞書にその語が単独で存在したのであればその情報も返す
sub _get_cost {
     my ($self, $word) = @_;

     my @nodes = $self->{mecab}->parse($word);
     my $last_node_cost = @nodes[-1]->{cost};

     @nodes = grep { !$_->{is_eos} } @nodes;
     my $n_morphs = scalar @nodes;
     my $last_node = @nodes[-1];

     return ($last_node_cost,
             ($n_morphs == 1 and !$last_node->{is_unknown} ? $last_node : undef)
         );
}

# 手持ちの.csvから，その[left_id/right_id/長さ]の語の平均コストを求める力業メソッド
sub _prepare_cost_by_length {
    my ($self, $left_id, $right_id) = @_;

    $logger->info("preparing cost_by_length table for [left_id=$left_id, right_id=$right_id]");

    my @costs;

    opendir DIR, $self->{dic_src_dir};
    while (my $file = readdir(DIR)) {
        next unless ($file =~ /\.csv$/);

        open FH, $self->{dic_src_dir}."/$file";
        while (<FH>) {
            split(/,/); my ($word,$l_id,$r_id,$cost) = @_; # Encodeもしてないしエスケープされた'\,' の処理もしてないけどまあ平均値とれればいいので適当に...
            next unless ($l_id == $left_id and $r_id == $right_id and $word);
            my $len = length(Encode::decode($self->{idfile_kanji_code}, $word));
            $costs[$len] ||= {};
            $costs[$len]->{max} = $cost if ($costs[$len] < $cost);
            $costs[$len]->{min} = $cost if (!defined($costs[$len]) or $costs[$len] > $cost);
            $costs[$len]->{sum} += $cost;
            $costs[$len]->{n}++;
        }
        close FH;

    }
    closedir(DIR);

    my $cost = [];
    for my $i (1..$#costs) {
        next unless ($costs[$i]->{n} > 2);
        $cost->[$i] = int($costs[$i]->{sum}/$costs[$i]->{n});
        $logger->debug("cost by length via sampling: length $i = ".$cost->[$i]);
    }
    return $cost;
}

# ↑サンプルがなければ，最終手段として，同じ長さの語の全平均コストから集計した長さベースのテーブルを使う
#
# ※集計のしかた例:
#
# cat Noun.*.csv | perl -nle 'use Encode;split(/,/);($word,$l_id,$r_id,$cost)=@_[0,1,2,3];$len=length(Encode::decode(q{utf8},$word));$e=$rslt->[$len]||={};$e->{sum}+=$cost;$e->{n}++;$e->{max}=$cost if ($e->{max}<$cost);$e->{min}=$cost if (!defined($e->{min})or $cost<$e->{min});END{for $len (0..$#$rslt){$e=$rslt->[$len]||{};print " len:$len:";print "  max:".$e->{max};print "  min:".$e->{min};print "  avg:".$e->{sum}/$e->{n} if $e->{n}} }';
#
# left_id:right_id別に細かくみたいならこんな感じ ?
#
# > cat Noun.*.csv | perl -nle 'use Encode;split(/,/);($word,$l_id,$r_id,$cost)=@_[0,1,2,3];$len=length(Encode::decode(q{utf8},$word));$e=$rslt->{"$l_id,$r_id"}->{$len}||={};$e->{sum}+=$cost;$e->{n}++;$e->{max}=$cost if ($e->{max}<$cost);$e->{min}=$cost if (!defined($e->{min})or $cost<$e->{min});END{for $id (keys(%$rslt)){print "$id:";for $len (keys(%{$rslt->{$id}})){$e=$rslt->{$id}->{$len};print " len:$len:";print "  max:".$e->{max};print "  min:".$e->{min};print "  avg:".$e->{sum}/$e->{n}} } }';
#

sub _get_cost_by_length {
    my ($self, $word, $morph) = @_;

    my $len = length($word);
    if ($morph->{cost_by_length} and defined($morph->{cost_by_length}->[$len])) {
        return $morph->{cost_by_length}->[$len];
    } else {
#    my @h = (8106 7053 7563 7171 7011 6673 6308 6019 5991 6021 5837 5833 5784 5890 5769 5566 5765 5188 5141);
        my @h = qw(8891 7729 8179 7704 7532 7130 6682 6314 6261 6297 6067 6057 5993 6099 5982 5709 5984 5181 5122);
        return ($len < $#h) ? $h[$len-1] : $h[-1];
#    return 3000/$_[0]+5000;
#    return 8000-log($_[0])*800;
    }
};




# compile

sub compile_dic {
    my $self = shift;

    my $command = $self->{mecab_dict_index}.' -f '.$self->{out_kanji_code}.' -t '.$self->{dic_kanji_code}.' -d '.$self->{dic_src_dir}.' -o '.$self->{dic_src_dir};

    $command .= ' -u '.$self->{dic_file} if $self->{dic_file};
    $command .= ' '.$self->{to_file} if $self->{to_file};

    $logger->info("invoking command [$command]");

    system($command) == 0 or $logger->logdie("command failed");
}

1;
