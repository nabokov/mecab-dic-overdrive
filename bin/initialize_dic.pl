#!/usr/bin/perl

#
# 初期辞書 (ipadic) をutf8に変換 & ノーマライズするスクリプト
#

use strict;
use Encode;
use Encode::JP;
use Getopt::Long;

use FindBin;
use lib "$FindBin::Bin/../lib";
use MecabTrainer::Config;
use MecabTrainer::Utils qw(:all);
use MecabTrainer::NormalizeText;
use MecabTrainer::GenDic;

my $conf = MecabTrainer::Config->new;
my $logger = init_logger($conf->{log_conf});

my %opts;
$opts{compile} = 1;
$opts{install} = 1;
&GetOptions(\%opts, 'compile!', 'install!');

my $dir = $conf->{dic_src_dir};
unless ($dir && -e $dir) {
    print <<EOS;
dic_src_dir ('$dir') not set or not found.

usage:
  initialize_dic.pl [ --nocompile --noinstall ]
  see etc/config.pl for details.
EOS
    exit;
}

my $normalizer = MecabTrainer::NormalizeText->new($conf->{default_normalize_opts});

my $in_kanji_code = 'euc-jp';
my $out_kanji_code = $conf->{out_kanji_code};
my $dic_kanji_code = $conf->{dic_kanji_code};


# configure

unless (-e "$dir/Makefile") {
    $logger->info("running configure");
    system("cd $dir;./configure --with-charset=".$dic_kanji_code) == 0 or $logger->logdie('configure failed');
}


# convert csv/def

$logger->info("processing *.csv/*.def files under $dir");
my $n_files = 0;
opendir DIR, $dir;
while (my $file =readdir(DIR)) {
    next unless $file =~ /\.(csv|def)$/;

    my $fullpath = "$dir/$file";
    my $org = "$fullpath.org";
    unless (-e $org) {
        rename($fullpath, $org) or $logger->logdie("can not create backup .org file");
    }
    system("cp $org $fullpath") == 0 or $logger->logdie("can not create working file");

    convert_charset($fullpath, $in_kanji_code, $out_kanji_code);

    # diff はエンコーディング変換の後，normalizeの前に適用
    my $patch = $conf->{dic_aux_files_dir}."/$file.patch";
    if (-e $patch) {
        $logger->info("applying $patch");
        system("patch $fullpath $patch") == 0 or $logger->logdie("patch $patch failed");
    }

    # *.csv は utf8化 + エントリを正規化
    if ($file =~ /\.csv$/) {
        open OUT, ">$fullpath.tmp";
        open IN, $fullpath;

        $logger->info("processing $file");

        while (my $line = <IN>) {
            chomp $line;
            my @f = split_csv(Encode::decode($out_kanji_code, $line));
            $f[0] = $normalizer->normalize($f[0]); # normalizeするのはsurfaceのとこだけ
            print OUT Encode::encode($out_kanji_code, join_csv(@f));
            print OUT "\n";
        }
        close IN;
        close OUT;
        unlink($fullpath);
        rename("$fullpath.tmp", $fullpath);
    }
    # *.def はutf8に変換するだけ
    elsif ($file =~ /\.def$/) {
    }

    $n_files ++;
}
closedir DIR;

unless ($n_files) { $logger->logdie("no files found. may be wrong dir ?") }


# compile & install

if ($opts{compile}) {
    MecabTrainer::GenDic->new->compile_dic;
}
if ($opts{install}) {
    system("cd $dir; sudo make install") == 0 or $logger->logdie('"sudo make install" failed. may be you should run this by hand');
}
exit;


#
#

sub convert_charset {
    my ($file, $in_code, $out_code) = @_;

    $logger->debug("converting $file by Encode");
    open IN, $file;
    open OUT, ">$file.tmp";
    while (<IN>) { print OUT Encode::encode($out_code, Encode::decode($in_code, $_)) }
    close OUT;
    close IN;
    rename("$file.tmp", $file);
}
