#!/usr/bin/perl

#
# ユーザ辞書作成の手順
#
# 1.元データを用意
#   Wikipediaクラス使用の場合: jawiki-*-pages-articles.xml.bz2 をdbにロードしたもの
#   WikipediaFileクラス使用の場合: jawiki-*-pages-articles.xml.bz2 ファイル自体
#   Kaomojiクラス使用の場合: 顔文字辞書をtsvにしたファイル
#   SimpleListクラス使用の場合: 単語を列挙したテキストファイル
#
# 2.generate_dic.pl --target=クラス名[ wikipedia|wikipedia_file|kaomoji|simple_list ... ] でdicファイル書き出し
#
# 3.~/.mecabrcのuserdicや、MeCabインスタンスを呼ぶときのuserdicオプションに、ここで書き出されたdicファイルを指定
#

use strict;
use Encode;
use Encode::JP;
use Getopt::Long;

use FindBin;
use lib "$FindBin::Bin/../lib";

use MecabTrainer::Config;
use MecabTrainer::Utils qw(:all);

my $conf = MecabTrainer::Config->new;
my $logger = init_logger($conf->{log_conf});

my %opts;
$opts{compile} = 1;
&GetOptions(\%opts, 'target=s', 'dic_src_dir=s', 'from_file=s', 'to_file=s',  'dic_file=s', 'dic_src_dir=s', 'dicdir=s', 'mecab_dict_index=s', 'normalize_opts=s', 'out_kanji_code=s', 'dic_kanji_code=s', 'compile!');

my $gen_dic_class = $opts{target};
$gen_dic_class =~ s/(^|_|-)(.)/uc($2)/eg;
$gen_dic_class = "MecabTrainer::GenDic::".$gen_dic_class;

eval "require $gen_dic_class";
if ($@) {
    print <<EOS;
usage:
  generate_dic.pl --target=(plugin classname = wikipedia | kaomoji | simple_list ...)
                  --dic_src_dir=(path to ipadic src dir ... where to find matrix.def and left/right-id.def)
                  [
                    --nocompile

                    (files are read from / written to conf->{dic_aux_files_dir} by default)
                    --from_file=(source .tsv filename)
                    --to_file=(target .csv filename)
                    --dic_file=(target compiled .dic filename)

                    (options below are read from conf by default)
                    --normalize_opts=(list of normalization opts. e.g."nfkc,lc". see Utils.pm for details)
                    --dicdir=(path to installed dic ... will be passed to mecab)
                    --mecab_dict_index=(path to mecab-dict-index)
                    --out_kanji_code=(intermediate csv kanji code)
                    --dic_kanji_code=(final binary dic kanji code)
                  ]
EOS
    exit;
}

my %gendic_args;
for (qw(dic_src_dir from_file to_file dic_file dicdir mecab_dict_index out_kanji_code dic_kanji_code idfile_kanji_code)) {
    $gendic_args{$_} = $opts{$_} if defined($opts{$_});
}
if ($opts{normalize_opts}) {
    $gendic_args{normalize_opts} = [ split(/[,:]/, $opts{normalize_opts}) ];
}


my $gen_dic = $gen_dic_class->new(%gendic_args);

$gen_dic->prepare_costs;
$gen_dic->write_csv;
$gen_dic->compile_dic if ($opts{compile});

exit;
