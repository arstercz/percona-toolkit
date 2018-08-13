package pt_online_schema_change_plugin;

use Data::Dumper;
local $Data::Dumper::Indent    = 1;
local $Data::Dumper::Sortkeys  = 1;
local $Data::Dumper::Quotekeys = 0;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
  my ($class, %args) = @_;
  my $self = { %args };
  return bless $self, $class;
}

sub _concat_sql {
  my ($tbl, $tag, $cols) = @_;
  my $suf = $tag eq 'INSERT' ? 'ins' : $tag eq 'UPDATE' ? 'upd' : 'unk';
  my $trigger_sql = qq{
CREATE TRIGGER tg_$tbl\_$suf BEFORE $tag ON $tbl
FOR EACH ROW
BEGIN
  };

  foreach my $col (@$cols) {
  $trigger_sql .= qq{
  IF NEW.$col IS NOT NULL AND NEW.$col NOT REGEXP '\\\\.|\\\\:' THEN
      SET NEW.$col = inet_ntoa(NEW.$col);
  END IF;
  };
  }

  $trigger_sql .= qq {
END
};
  return $trigger_sql;
}

sub before_exit {
  my ($self, %args) = @_;

  my $tbl = $self->{cxn}->{dsn}->{t};
  my $col = $args{opt_args}->{'convert-column'}->{'value'};
  my @convert_cols = split(/,/, $col);

  my $drop_ins = qq {DROP TRIGGER IF EXISTS tg_$tbl\_ins};
  my $trigger_ins = _concat_sql($tbl, 'INSERT', \@convert_cols);

  my $drop_upd = qq{DROP TRIGGER IF EXISTS tg_$tbl\_upd};
  my $trigger_upd = _concat_sql($tbl, 'UPDATE', \@convert_cols);

  my $dbh = $self->{aux_cxn}->dbh;

  print "Drop the old trigger for table: $tbl, cols: $col\n";
  eval {
    $dbh->do($drop_ins);
    $dbh->do($drop_upd);
  };
  if ($@) {
    print "Drop old trigger error: $@";
  }
  else {
    print "Drop old trigger ok\n";
  }

  print "Create convert trigger for table: $tbl, cols: $col\n";
  eval {
    $dbh->do($trigger_ins);
    $dbh->do($trigger_upd);
  };
  if ($@) {
    print "Create convert trigger error: $@";
  }
  else {
     print "Create convert trigger ok\n";
  }
  return 1;
}

1;
