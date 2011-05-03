#!/usr/bin/perl

use strict;

use Encode;
use Encode::JP;
use Getopt::Long;

use FindBin;
use lib "$FindBin::Bin/../lib";

use MecabTrainer::Config;
use MecabTrainer::Utils qw(:all);
use MecabTrainer::NormalizeText;

my $conf = MecabTrainer::Config->new;

my %opts;
&GetOptions(\%opts, 'normalize_opts=s');

my $normalize_opts;
if ($opts{normalize_opts}) {
    $normalize_opts = [ split(/[,:]/, $opts{normalize_opts}) ];
} else {
    $normalize_opts = $conf->{default_normalize_opts},
}
my $normalizer = MecabTrainer::NormalizeText->new($normalize_opts);


while (<>) { print internal2console($normalizer->normalize(console2internal($_))); }


