# Hoon "tidy" utility

use 5.010;
use strict;
use warnings;
no warnings 'recursion';

use Data::Dumper;
use English qw( -no_match_vars );
use Scalar::Util qw(looks_like_number weaken);
use Getopt::Long;

require "yahc.pm";

my $style;

my $verbose; # right now does nothing
my $censusWhitespace;
my $inclusionsFileName;
my @suppressionsFileNames;
my $contextLines = 0;

GetOptions(
    "verbose"             => \$verbose,
    "context|C=i"         => \$contextLines,
    "census-whitespace"   => \$censusWhitespace,
    "inclusions-file|I=s" => \$inclusionsFileName,
    "suppressions_file|S=s" => \@suppressionsFileNames,
) or die("Error in command line arguments\n");

sub usage {
    die "usage: $PROGRAM_NAME [options ...] fileName\n";
}

usage() if scalar @ARGV != 1;
my $fileName = $ARGV[0];

sub internalError {
   my @pieces = ("$PROGRAM_NAME $fileName: Internal Error\n", @_);
   push @pieces, "\n" unless $pieces[$#pieces] =~ m/\n$/;
   my (undef, $codeFilename, $codeLine) = caller;
   die join q{}, @pieces, "Internal error was at $codeFilename, line $codeLine";
}

sub slurp {
    my ($fileName) = @_;
    local $RS = undef;
    my $fh;
    open $fh, q{<}, $fileName or die "Cannot open $fileName";
    my $file = <$fh>;
    close $fh;
    return \$file;
}

my $defaultSuppressionFile = 'hoonlint.suppressions';
if ( not @suppressionsFileNames
    and -f $defaultSuppressionFile )
{
    @suppressionsFileNames = ($defaultSuppressionFile);
}

sub itemError {
    my ( $error, $line ) = @_;
    return qq{Error in item file "$fileName": $error\n}
    . qq{  Problem with line: $line\n};
}

my $pSuppressions;
{
    my @suppressions = ();
    for my $fileName (@suppressionsFileNames) {
        push @suppressions, ${ slurp($fileName) };
    }
    $pSuppressions = \(join "", @suppressions);
}

my %reportItemType   = map { +( $_, 1 ) } qw(indent sequence);
my ($suppressions, $unusedSuppressions) = parseReportItems($pSuppressions);
die $unusedSuppressions if not $suppressions;

my $pInclusions;
my ( $inclusions, $unusedInclusions );
if ( defined $inclusionsFileName ) {
    $pInclusions = slurp($inclusionsFileName);
    ( $inclusions, $unusedInclusions ) = parseReportItems($pInclusions);
    die $unusedInclusions if not $inclusions;
}

sub parseReportItems {
    my ($reportItems)        = @_;
    my %itemHash       = ();
    my %unusedItemHash = ();
  ITEM: for my $itemLine ( split "\n", ${$reportItems} ) {
        my $rawItemLine = $itemLine;
        $itemLine =~ s/\s*[#].*$//;   # remove comments and preceding whitespace
        $itemLine =~ s/^\s*//;        # remove leading whitespace
        $itemLine =~ s/\s*$//;        # remove trailing whitespace
        next ITEM unless $itemLine;
        my ( $thisFileName, $lc, $type, $message ) = split /\s+/, $itemLine, 4;
        return undef, itemError( "Problem in report line", $rawItemLine )
          if not $thisFileName;

        return undef, itemError( qq{Bad report item type "$type"}, $rawItemLine )
          if not exists $reportItemType{$type};
        return undef, itemError( qq{Malformed line:column in item line: "$lc"},
            $rawItemLine )
          unless $lc =~ /^[0-9]+[:][0-9]+$/;
        my ( $line, $column ) = split ':', $lc, 2;
        itemError( qq{Malformed line:column in item line: "$lc"},
            $rawItemLine )
          unless Scalar::Util::looks_like_number($line)
          and Scalar::Util::looks_like_number($column);
        next ITEM unless $thisFileName eq $fileName;

        # We reassemble line:column to "normalize" it -- be indifferent to
        # leading zeros, etc.
        my $tag = join ':', $line, $column;
        $itemHash{$type}{$tag}         = $message;
        $unusedItemHash{$type}{$tag} = 1;
    }
    return \%itemHash, \%unusedItemHash;
}

my $pHoonSource = slurp($fileName);

my @data = ();
my $recce;

my $semantics = <<'EOS';
:default ::= action=>main::doNode
lexeme default = latm => 1 action=>[start,length,name]
EOS

my $parser = MarpaX::YAHC::new( { semantics => $semantics, all_symbols => 1 } );
my $dsl = $parser->dsl();
my $grammar = $parser->rawGrammar();

my %tallRuneRule = map { +( $_, 1 ) } grep {
         /^tall[B-Z][aeoiu][b-z][b-z][aeiou][b-z]$/
      or /^tall[B-Z][aeoiu][b-z][b-z][aeiou][b-z]Mold$/
} map { $grammar->symbol_name($_); } $grammar->symbol_ids();

# TODO: wisp5d needs study -- may depend on parent
my %tallNoteRule = map { +( $_, 1 ) } qw(
  tallBarhep tallBardot
  tallCendot tallColcab tallColsig
  tallKethep tallKetlus tallKetwut
  tallSigbar tallSigcab tallSigfas tallSiglus
  tallTisbar tallTiscom tallTisgal
  tallWutgal tallWutgar tallWuttis
  tallZapgar wisp5d
  tallTailOfElem tallTailOfTop
);

my %mortarLHS = map { +( $_, 1 ) } qw(rick5dJog ruck5dJog rick5d ruck5d);
my %tallBodyRule =
  map { +( $_, 1 ) } grep { not $tallNoteRule{$_} } keys %tallRuneRule;

# TODO: These are *not* jogging rules.  Change the name and look
# at the logic.
my %tall_0JoggingRule = map { +( $_, 1 ) } qw(tallWutbar tallWutpam);

my %tall_1JoggingRule =
  map { +( $_, 1 ) } qw(tallCentis tallCencab tallWuthep);
my %tall_2JoggingRule = map { +( $_, 1 ) } qw(tallCentar tallWutlus);
my %tallJogging1_Rule = map { +( $_, 1 ) } qw(tallTiscol);
my %tallLuslusRule = map { +( $_, 1 ) } qw(LuslusCell LushepCell LustisCell
  optFordFashep optFordFaslus fordFaswut fordFastis);
my %tallJogRule      = map { +( $_, 1 ) } qw(rick5dJog ruck5dJog);
my @unimplementedRule = qw( tallSemCol tallSemsig );
my %tallBackdentRule = map { +( $_, 1 ) } @unimplementedRule,
qw(
  bonz5d
  fordFasbar
  fordFascom
  fordFasdot
  fordFasket
  fordFassem
  tallBarcab
  tallBarcen
  tallBarcol
  tallBarket
  tallBarsig
  tallBartar
  tallBartis
  tallBuccen
  tallBuccenMold
  tallBuccol
  tallBuccolMold
  tallBuchep
  tallBucket
  tallBucketMold
  tallBucpat
  tallBuctisMold
  tallBucwut
  tallBucwutMold
  tallCenhep
  tallCenhepMold
  tallCenket
  tallCenlus
  tallCenlusMold
  tallCensig
  tallCentar
  tallColhep
  tallColket
  tallCollus
  tallColtar
  tallDottar
  tallDottis
  tallKetcen
  tallKettis
  tallSigbuc
  tallSigcen
  tallSiggar
  tallSigpam
  tallSigwut
  tallSigzap
  tallTisdot
  tallTisfas
  tallTisgar
  tallTishep
  tallTisket
  tallTislus
  tallTissem
  tallTistar
  tallTiswut
  tallWutcol
  tallWutdot
  tallWutket
  tallWutpat
  tallWutsig
  tallZapcol
  tallZapdot
  tallZapwut
);

# say Data::Dumper::Dumper(\%tallBodyRule);

my %separator = qw(
  hyf4jSeq DOT
  singleQuoteCord gon4k
  dem4k gon4k
  timePeriodKernel DOT
  optBonzElements GAP
  optWideBonzElements ACE
  till5dSeq GAP
  wyde5dSeq ACE
  gash5d FAS
  togaElements ACE
  wide5dJogs wide5dJoggingSeparator
  rope5d DOT
  rick5d GAP
  wideRick5d commaAce
  ruck5d GAP
  wideRuck5d commaAce
  tallTopKidSeq  GAP_SEM
  wideInnerTops ACE
  wideAttrBody commaAce
  scriptStyleTailElements GAP
  moldInfixCol2 COL
  lusSoilSeq DOG4I
  hepSoilSeq DOG4I
  infixDot DOG4I
  waspElements GAP
  whap5d GAP
  hornSeq GAP
  wideHornSeq ACE
  fordHoopSeq GAP
  tall5dSeq GAP
  wide5dSeq ACE
  fordFascomElements GAP
  optFordHithElements FAS
  fordHoofSeq commaWS
);

sub doNode {
    my ( undef, @argChildren ) = @_;
    my @results    = ();
    my $childCount = scalar @argChildren;
    no warnings 'once';
    my $ruleID = $Marpa::R2::Context::rule;
    use warnings;
    my ( $lhs, @rhs ) =
      map { $grammar->symbol_display_form($_) } $grammar->rule_expand($ruleID);
    my ( $first_g1, $last_g1 ) = Marpa::R2::Context::location();
    my ($lhsStart) = $recce->g1_location_to_span( $first_g1 + 1 );

    my $node;
  CREATE_NODE: {
        if ( $childCount <= 0 ) {
            $node = {
                type   => 'null',
                symbol => $lhs,
                start  => $lhsStart,
                length => 0,
            };
            last CREATE_NODE;
        }
        my ( $last_g1_start, $last_g1_length ) =
          $recce->g1_location_to_span($last_g1);
        my $lhsLength = $last_g1_start + $last_g1_length - $lhsStart;
      RESULT: {
          CHILD: for my $childIX ( 0 .. $#argChildren ) {
                my $child   = $argChildren[$childIX];
                my $refType = ref $child;
                next CHILD unless $refType eq 'ARRAY';

                my ( $lexemeStart, $lexemeLength, $lexemeName ) = @{$child};

                if ( $lexemeName eq 'TRIPLE_DOUBLE_QUOTE_STRING' ) {
                    my $terminator = q{"""};
                    my $terminatorPos = index ${$pHoonSource}, $terminator,
                      $lexemeStart + $lexemeLength;
                    $lexemeLength =
                      $terminatorPos + ( length $terminator ) - $lexemeStart;
                }
                if ( $lexemeName eq 'TRIPLE_QUOTE_STRING' ) {
                    my $terminator = q{'''};
                    my $terminatorPos = index ${$pHoonSource}, $terminator,
                      $lexemeStart + $lexemeLength;
                    $lexemeLength =
                      $terminatorPos + ( length $terminator ) - $lexemeStart;
                }
                $argChildren[$childIX] = {
                    type   => 'lexeme',
                    start  => $lexemeStart,
                    length => $lexemeLength,
                    symbol => $lexemeName,
                };
            }

            my $lastLocation = $lhsStart;
            if ( ( scalar @rhs ) != $childCount ) {

          # This is a non-trivial (that is, longer than one item) sequence rule.
                my $childIX = 0;
                my $lastSeparator;
              CHILD: for ( ; ; ) {

                    my $child     = $argChildren[$childIX];
                    my $childType = $child->{type};
                    $childIX++;
                  ITEM: {
                        if ( defined $lastSeparator ) {
                            my $length =
                              $child->{start} - $lastSeparator->{start};
                            $lastSeparator->{length} = $length;
                        }
                        push @results, $child;
                        $lastLocation = $child->{start} + $child->{length};
                    }
                    last RESULT if $childIX > $#argChildren;
                    my $separator = $separator{$lhs};
                    next CHILD unless $separator;
                    $lastSeparator = {
                        type   => 'separator',
                        symbol => $separator,
                        start  => $lastLocation,

                        # length supplied later
                    };
                    push @results, $lastSeparator;
                }
                last RESULT;
            }

            # All other rules
          CHILD: for my $childIX ( 0 .. $#argChildren ) {
                my $child = $argChildren[$childIX];
                push @results, $child;
            }
        }

        # Add weak links
        $node = {
            type     => 'node',
            ruleID   => $ruleID,
            start    => $lhsStart,
            length   => $lhsLength,
            children => \@results,
        };
    }

    my $children = $node->{children};
    if ( $children and scalar @{$children} >= 1 ) {
      CHILD: for my $childIX ( 0 .. $#$children ) {
            my $child = $children->[$childIX];
            $child->{PARENT} = $node;
            weaken( $child->{PARENT} );
        }
      CHILD: for my $childIX ( 1 .. $#$children ) {
            my $thisChild = $children->[$childIX];
            my $prevChild = $children->[ $childIX - 1 ];
            $thisChild->{PREV} = $prevChild;
            weaken( $thisChild->{PREV} );
            $prevChild->{NEXT} = $thisChild;
            weaken( $prevChild->{NEXT} );
        }
    }

    return $node;
}

$parser->read($pHoonSource);
$recce  = $parser->rawRecce();
$parser = undef;                 # free up memory
my $astRef = $recce->value();

sub literal {
    my ( $start, $length ) = @_;
    return substr ${$pHoonSource}, $start, $length;
}

my @lineToPos = (-1, 0);
while (${$pHoonSource} =~ m/\n/g) { push @lineToPos, pos ${$pHoonSource} };

sub column {
    my ($pos) = @_;
    return $pos - ( rindex ${$pHoonSource}, "\n", $pos - 1 );
}

sub context2 {
    my ( $pContextLines, $pMistakeLines, $contextSize ) = @_;
    return '' if $contextSize <= 0;
    my @pieces      = ();
    my $runeLine    = $pContextLines->[0];
    my $mistakeLine = $pMistakeLines->[0];
    my %tag         = map { $_ => q{>} } @{$pContextLines};
    $tag{$_} = q{!} for @{$pMistakeLines};
    my $runeRangeStart = $runeLine - ( $contextSize - 1 );
    $runeRangeStart = 1 if $runeRangeStart < 1;
    my $runeRangeEnd = $runeLine + ( $contextSize - 1 );
    $runeRangeEnd = $#lineToPos if $runeRangeEnd > $#lineToPos;
    my $mistakeRangeStart = $mistakeLine - ( $contextSize - 1 );
    $mistakeRangeStart = 1 if $mistakeRangeStart < 1;
    my $mistakeRangeEnd = $mistakeLine + ( $contextSize - 1 );
    $mistakeRangeEnd = $#lineToPos if $mistakeRangeEnd > $#lineToPos;

    # Note: duplicate lines OK (I hope!)
    my @sortedLines = sort { $a <=> $b } (@{$pContextLines}, @{$pMistakeLines});
    my $lineNumFormat = q{%} . (length q{} . $#lineToPos) . 'd';

    # Add to @pieces a set of lines to be displayed consecutively
    my $doConsec = sub () {
        my ($start, $end) = @_;
        $start = 1 if $start < 1;
        $end = $#lineToPos if $end > $#lineToPos;
        for my $lineNum ( $start .. $end ) {
            my $startPos = $lineToPos[$lineNum];
            my $line =
              literal( $startPos, ( $lineToPos[ $lineNum + 1 ] - $startPos ) );
            my $tag = $tag{$lineNum} // q{ };
            push @pieces, (sprintf $lineNumFormat, $lineNum), $tag, q{ }, $line;
        }
    };

    my $lastIX = -1;
  CONSEC_RANGE: while ( $lastIX < $#sortedLines ) {
        my $firstIX = $lastIX + 1;

        # Divider line if after first consecutive range
        say '-----' if $firstIX > 0;
        $lastIX = $firstIX;
      SET_LAST_IX: while (1) {
            my $nextIX = $lastIX + 1;
            last SET_LAST_IX if $nextIX > $#sortedLines;

    # We combine lines if by doing so, we make the listing shorter.
    # This is calculated by
    # 1.) Taking the current last line.
    # 2.) Add the context lines for the last and next lines (2*($contextSize-1))
    # 3.) Adding 1 for the divider line, which we save if we combine ranges.
    # 4.) Adding 1 because we test if they abut, not overlap
    # Doing the arithmetic, we get
            last SET_LAST_IX
              if $sortedLines[$lastIX] + 2 * $contextSize <
              $sortedLines[$nextIX];
            $lastIX = $nextIX;
        }
        $doConsec->(
            $sortedLines[$firstIX] - ( $contextLines - 1 ),
            $sortedLines[$lastIX] + ( $contextLines - 1 )
        );
    }

    return join q{}, @pieces;
}

sub reportItem {
  my ($topic, $runeLines, $mistakeLines, $contextSize) = @_;
  return "$topic\n" if not $contextSize;
  $mistakeLines = [$mistakeLines] unless ref $mistakeLines;
  $runeLines = [$runeLines] unless ref $runeLines;
  return join q{}, "== ", $topic, "\n", context2($runeLines, $mistakeLines, $contextSize);
}

# The "symbol" of a node.  Not necessarily unique.
sub symbol {
    my ($node) = @_;
    my $name = $node->{symbol};
    return $name if defined $name;
    my $type = $node->{type};
    if ( $type eq 'node' ) {
        my $ruleID = $node->{ruleID};
        my ( $lhs, @rhs ) = $grammar->rule_expand($ruleID);
        return $grammar->symbol_name($lhs);
    }
    return "[$type]";
}

# Can be used as test of "brick-ness"
sub brickName {
    my ($node) = @_;
    my $type = $node->{type};
    return symbol($node) if $type ne 'node';
    my $ruleID = $node->{ruleID};
    my ( $lhs, @rhs ) = $grammar->rule_expand($ruleID);
    my $lhsName = $grammar->symbol_name($lhs);
    return $lhsName if not $mortarLHS{$lhsName};
    return;
}

# The name of a name for diagnostics purposes.  Prefers
# "brick" symbols over "mortar" symbols.
sub diagName {
    my ($node, $context) = @_;
    my $type = $node->{type};
    return symbol($node) if $type ne 'node';
    my $ruleID = $node->{ruleID};
    my ( $lhs, @rhs ) = $grammar->rule_expand($ruleID);
    my $lhsName = $grammar->symbol_name($lhs);
    return $lhsName if not $mortarLHS{$lhsName};
    my $hoonName = $context->{hoonName};
    internalError("No hoon name for $lhsName") if not $hoonName;
    return $hoonName;
}

# The "name" of a node.  Not necessarily unique
sub name {
    my ($node) = @_;
    my $type = $node->{type};
    my $symbol = symbol($node);
    return $symbol if $type ne 'node';
    my $ruleID = $node->{ruleID};
    my ( $lhs, @rhs ) = $grammar->rule_expand($ruleID);
    return $symbol . '#' . ( scalar @rhs );
}

die "Parse failed" if not $astRef;

local $Data::Dumper::Deepcopy = 1;
local $Data::Dumper::Terse    = 1;

# say Data::Dumper::Dumper($astRef);

my $astValue = ${$astRef};

# Determine how many spaces we need.
# Arguments are an array of strings (intended
# to be concatenated) and an integer, representing
# the number of spaces needed by the app.
# (For hoon this will always between 0 and 2.)
# Hoon's notation of spacing, in which a newline is equivalent
# a gap and therefore two spaces, is used.
#
# Return value is the number of spaces needed after
# the trailing part of the argument string array is
# taken into account.  It is always less than or
# equal to the `spacesNeeded` argument.
sub spacesNeeded {
    my ( $strings, $spacesNeeded ) = @_;
    for ( my $arrayIX = $#$strings ; $arrayIX >= 0 ; $arrayIX-- ) {

 # say STDERR join " ", __FILE__, __LINE__, "tab command: needed=$spacesNeeded";
        my $string = $strings->[$arrayIX];

       # say STDERR join " ", __FILE__, __LINE__, "tab command: string=$string";
       # say STDERR +(join " ", __FILE__, __LINE__, ''), (length $string);
        for (
            my $stringIX = ( length $string ) - 1 ;
            $stringIX >= 0 ;
            $stringIX--
          )
        {
# say STDERR join " ", __FILE__, __LINE__, "tab command: stringIX=$stringIX; needed=$spacesNeeded";
            my $char = substr $string, $stringIX, 1;
            return 0 if $char eq "\n";
            return $spacesNeeded if $char ne q{ };
            $spacesNeeded--;
            return 0 if $spacesNeeded <= 0;
        }
    }

    # No spaces needed at beginning of string;
    return 0;
}

my @ruleDB          = ();
my @symbolDB        = ();
my %symbolReverseDB = ();

sub testStyleCensus {
  SYMBOL:
    for my $symbolID ( $grammar->symbol_ids() ) {
        my $name = $grammar->symbol_name($symbolID);
        my $data = {};
        $data->{name}   = $name;
        $data->{id}     = $symbolID;
        $data->{lexeme} = 1;                     # default to lexeme
        $data->{gap}    = 1 if $name eq 'GAP';
        $data->{gap}    = 1
          if $name =~ m/^[B-Z][AEOIU][B-Z][B-Z][AEIOU][B-Z]GAP$/;
        $symbolDB[$symbolID] = $data;
        $symbolReverseDB{$name} = $data;
    }
    my $gapID = $symbolReverseDB{'GAP'}->{id};
  RULE:
    for my $ruleID ( $grammar->rule_ids() ) {
        my $data = { id => $ruleID };
        my ( $lhs, @rhs ) = $grammar->rule_expand($ruleID);
        $data->{symbols} = [ $lhs, @rhs ];
        my $lhsName       = $grammar->symbol_name($lhs);
        my $separatorName = $separator{$lhsName};
        if ($separatorName) {
            my $separatorID = $symbolReverseDB{$separatorName}->{id};
            $data->{separator} = $separatorID;
            if ( $separatorID == $gapID ) {
                $data->{gapiness} = -1;
            }
        }
        if ( not defined $data->{gapiness} ) {
            for my $rhsID (@rhs) {
                $data->{gapiness}++ if $symbolDB[$rhsID]->{gap};
            }
        }
        $ruleDB[$ruleID] = $data;
        $symbolReverseDB{$lhs}->{lexeme} = 0;
    }

}

testStyleCensus();

sub line_column {
   my ($pos) = @_;
   my ( $line, $column ) = $recce->line_column($pos);
   $column--;
   return $line, $column;
}

my $brickLC = sub() {
    my ($node)     = @_;
    for (my $thisNode = $node; $thisNode; $thisNode = $node->{PARENT} ) {
        return line_column($node) if brickName($node);
    }
    internalError("No brick parent");
};

my $calcGapIndents = sub () {
    my ($node)     = @_;
    my $children   = $node->{children};
    my @gapIndents = ();
    my $child      = $children->[0];
    my $childStart = $child->{start};
    my ( $childLine, $childColumn ) = $recce->line_column($childStart);
    push @gapIndents, [ $childLine, $childColumn - 1 ];
    for my $childIX ( 0 .. ( $#$children - 1 ) ) {
        my $child  = $children->[$childIX];
        my $symbol = $child->{symbol};
        if ( defined $symbol
            and $symbolReverseDB{$symbol}->{gap} )
        {
            my $nextChild = $children->[ $childIX + 1 ];
            my $nextStart = $nextChild->{start};
            my ( $nextLine, $nextColumn ) = $recce->line_column($nextStart);
            push @gapIndents, [ $nextLine, $nextColumn - 1 ];
        }
    }
    return \@gapIndents;
};

sub doLint {
    my ( $node, $argContext ) = @_;

    my $parentSymbol = $node->{symbol};
    my $parentStart  = $node->{start};
    my $parentLength = $node->{length};
    my $parentRuleID = $node->{ruleID};
    my ( $parentLine, $parentColumn ) = line_column($parentStart);
    my $parentLC = join ':', $parentLine, $parentColumn+1;

    my @parentIndents = @{ $argContext->{indents} };

    # TODO: Delete "ancestors" in favor of tree traversal
    my @ancestors = @{ $argContext->{ancestors} };
    shift @ancestors if scalar @ancestors >= 5;    # no more than 5
    push @ancestors, { ruleID => $parentRuleID, start => $parentStart };

    my $argLine = $argContext->{line};
    if ( $argLine != $parentLine ) {
        @parentIndents = ($parentColumn);

        # say "line $parentLine: new indents: ", (join " ", @parentIndents);
    }
    elsif ( $parentColumn != $parentIndents[$#parentIndents] ) {
        push @parentIndents, $parentColumn;

        # say "line $parentLine: indents: ", (join " ", @parentIndents);
    }

    my $argBodyIndent     = $argContext->{bodyIndent};
    my $argTallRuneIndent = $argContext->{tallRuneIndent};
    my $parentBodyIndent;
    $parentBodyIndent = $argBodyIndent if $argLine == $parentLine;
    my $parentTallRuneIndent;
    $parentTallRuneIndent = $argTallRuneIndent if $argLine == $parentLine;
    my $parentContext = {
        ancestors => \@ancestors,
        line      => $parentLine,
        indents   => [@parentIndents],
    };
    $parentContext->{bodyIndent} = $parentBodyIndent
      if defined $parentBodyIndent;
    $parentContext->{tallRuneIndent} = $parentTallRuneIndent
      if defined $parentTallRuneIndent;

    # notes align with body indent from ancestor, if there is one;
    # otherwise, with the parent tall rune (if one exists);
    # otherwise with the parent.
    my $noteIndent = ( $parentBodyIndent // $parentTallRuneIndent )
      // $parentColumn;

    my $parentChessSide = $argContext->{chessSide};
    $parentContext->{chessSide} = $parentChessSide
      if defined $parentChessSide;

    my $parentJogRuneColumn = $argContext->{jogRuneColumn};
    $parentContext->{jogRuneColumn} = $parentJogRuneColumn
      if defined $parentJogRuneColumn;

    my $parentJogBodyColumn = $argContext->{jogBodyColumn};
    $parentContext->{jogBodyColumn} = $parentJogBodyColumn
      if defined $parentJogBodyColumn;

    my $parentHoonName = $argContext->{hoonName};
    # say STDERR "setting hoonName = $parentHoonName";
    $parentContext->{hoonName} = $parentHoonName;

    my $children = $node->{children};

  LINT_NODE: {

        # "Policies" will go here
        # As of this writing, these is only one policy -- the "whitespace"
        # policy.

      WHITESPACE_POLICY: {

            my $nodeType = $node->{type};
            last WHITESPACE_POLICY if $nodeType ne 'node';

            my $ruleID = $node->{ruleID};
            die Data::Dumper::Dumper($node) if not defined $ruleID;
            my ( $lhs, @rhs ) = $grammar->rule_expand( $node->{ruleID} );
            my $lhsName = $grammar->symbol_name($lhs);

            # say STDERR join " ", __FILE__, __LINE__, $lhsName;

            # say STDERR "current hoonName = $parentHoonName ", $parentContext->{hoonName};
            if (not $mortarLHS{$lhsName}) {
                $parentHoonName = $lhsName;
                # say STDERR "resetting hoonName = $parentHoonName";
                $parentContext->{hoonName} = $parentHoonName;
            }

            $parentContext->{bodyIndent} = $parentColumn
              if $tallBodyRule{$lhsName};

            # TODO: This corresponds to some arvo/ file indentations,
            # but would cause many other discrepancies, including one
            # in toe.hoon
            # $parentContext->{bodyIndent} = $parentColumn+2
            # if $tallLuslusRule{$lhsName};

            $parentContext->{tallRuneIndent} = $parentColumn
              if $tallRuneRule{$lhsName};

            if ( $lhsName eq 'optGay4i' ) {
                last WHITESPACE_POLICY;
            }

            my $childCount = scalar @{$children};
            last WHITESPACE_POLICY if $childCount <= 0;
            if ( $childCount == 1 ) {
                last WHITESPACE_POLICY;
            }

            my $firstChildIndent = column( $children->[0]->{start} ) - 1;

            my $gapiness = $ruleDB[$ruleID]->{gapiness} // 0;

            my $reportType = $gapiness < 0 ? 'sequence' : 'indent';

            # TODO: In another policy, warn on tall children of wide nodes
            if ( $gapiness == 0 ) {    # wide node
                last WHITESPACE_POLICY;
            }

            # tall node

            if ( $gapiness < 0 ) {     # sequence
                my ( $parentLine, $parentColumn ) =
                  $recce->line_column($parentStart);
                my $parentLC = join ':', $parentLine, $parentColumn;
                $parentColumn--;       # 0-based
                my $previousLine = $parentLine;
              TYPE_INDENT: {

                    # Jogging problems are detected by the individual jogs --
                    # we do not run diagnostics on the sequence.
                    next TYPE_INDENT if $lhsName eq 'rick5d';
                    next TYPE_INDENT if $lhsName eq 'ruck5d';

                    if ( $lhsName eq 'tall5dSeq' ) {
                        my $argAncestors = $argContext->{ancestors};

                        # say Data::Dumper::Dumper($argAncestors);
                        my $ancestorCount   = scalar @{$argAncestors};
                        my $grandParentName = "";
                        my $grandParentLC;
                        my ( $grandParentLine, $grandParentColumn );
                        if ( scalar @{$argAncestors} >= 1 ) {
                            my $grandParent       = $argAncestors->[-1];
                            my $grandParentRuleID = $grandParent->{ruleID};
                            my $grandParentStart  = $grandParent->{start};
                            ( $grandParentLine, $grandParentColumn ) =
                              $recce->line_column($grandParentStart);
                            $grandParentLC = join ':', $grandParentLine,
                              $grandParentColumn;
                            $grandParentColumn--;    # 0-based
                            my ($lhs) =
                              $grammar->rule_expand($grandParentRuleID);
                            $grandParentName =
                              $grammar->symbol_display_form($lhs);
                        }
                        if ( $grandParentName eq 'tallSemsig' ) {

                            $previousLine = $grandParentLine;
                          CHILD: for my $childIX ( 0 .. $#$children ) {
                                my $isProblem  = 0;
                                my $child      = $children->[$childIX];
                                my $childStart = $child->{start};
                                my $symbol     = $child->{symbol};
                                next CHILD
                                  if defined $symbol
                                  and $symbolReverseDB{$symbol}->{gap};
                                my ( $childLine, $childColumn ) =
                                  $recce->line_column($childStart);
                                my $childLC = join ':', $childLine,
                                  $childColumn;
                                $childColumn--;    # 0-based

                                my $indentDesc = 'RUN';
                              SET_INDENT_DESC: {
                                    my $suppression =
                                      $suppressions->{'sequence'}{$childLC};
                                    if ( defined $suppression ) {
                                        $indentDesc =
                                          "SUPPRESSION $suppression";
                                        $unusedSuppressions->{'sequence'}
                                          {$childLC} = undef;
                                        last SET_INDENT_DESC;
                                    }

                                    if (    $childLine != $previousLine
                                        and $childColumn !=
                                        $grandParentColumn + 2 )
                                    {
                                        $isProblem = 1;
                                        $indentDesc = join " ", $grandParentLC,
                                          $childLC;
                                    }
                                }
                                if (   not $inclusions
                                    or $inclusions->{sequence}{$grandParentLC} )
                                {
                                    print reportItem(
"$fileName $grandParentLC sequence $lhsName $indentDesc",
                                        $parentLine, $childLine, $contextLines )
                                      if $censusWhitespace or $isProblem;
                                }
                                $previousLine = $childLine;
                            }

                            last TYPE_INDENT;
                        }
                    }

                  CHILD: for my $childIX ( 0 .. $#$children ) {
                        my $isProblem  = 0;
                        my $child      = $children->[$childIX];
                        my $childStart = $child->{start};
                        my $symbol     = $child->{symbol};
                        next CHILD
                          if defined $symbol
                          and $symbolReverseDB{$symbol}->{gap};
                        my ( $childLine, $childColumn ) =
                          $recce->line_column($childStart);
                        my $childLC = join ':', $childLine, $childColumn;
                        $childColumn--;    # 0-based

                        my $indentDesc = 'REGULAR';
                      SET_INDENT_DESC: {
                            my $suppression =
                              $suppressions->{'sequence'}{$childLC};
                            if ( defined $suppression ) {
                                $indentDesc = "SUPPRESSION $suppression";
                                $unusedSuppressions->{'sequence'}{$childLC} =
                                  undef;
                                last SET_INDENT_DESC;
                            }

                            if (    $childLine != $previousLine
                                and $childColumn != $parentColumn )
                            {
                                $isProblem = 1;
                                $indentDesc = join " ", $parentLC, $childLC;
                            }
                        }
                        if (   not $inclusions
                            or $inclusions->{sequence}{$parentLC} )
                        {
                            print reportItem(
                                (
                                    sprintf
"$fileName $parentLC sequence %s $indentDesc",
                                    diagName( $node, $parentContext )
                                ),
                                $parentLine,
                                $childLine,
                                $contextLines
                            ) if $censusWhitespace or $isProblem;
                        }
                        $previousLine = $childLine;
                    }
                }
                    last WHITESPACE_POLICY;
                }

                sub isLuslusStyle {
                    my ($indents) = @_;
                    my @mistakes = ();
                    my ( $baseLine, $baseColumn ) = @{ $indents->[0] };

                    my $indentCount = scalar @{$indents};
                    my $indentIX    = 1;
                  INDENT: while ( $indentIX < $indentCount ) {
                        my ( $thisLine, $thisColumn ) = @{ $indents->[$indentIX] };
                        last INDENT if $thisLine != $baseLine;
                        $indentIX++;
                    }
                  INDENT: while ( $indentIX < $indentCount ) {
                        my ( $thisLine, $thisColumn ) = @{ $indents->[$indentIX] };
                        if ( $thisColumn != $baseColumn + 2 ) {
                            my $msg = sprintf
                              "Child #%d @ line %d; backdent is %d; should be %d",
                              $indentIX, $thisLine, $thisColumn, $baseColumn + 2;
                            push @mistakes,
                              {
                                desc           => $msg,
                                line           => $thisLine,
                                column         => $thisColumn,
                                child          => $indentIX,
                                expectedColumn => $baseColumn + 2
                              };
                        }
                        $indentIX++;
                    }
                    return \@mistakes;
                }

                # Format line and 0-based column as string
                sub describeLC {
                  my ($line, $column) = @_;
                  return '@' . $line . ':' . ($column+1);
                }

                sub describeMisindent {
                  my ($got, $sought) = @_;
                  if ($got > $sought) {
                     return "overindented by " . ($got - $sought);
                  }
                  if ($got < $sought) {
                     return "underindented by " . ($sought - $got);
                  }
                 return "correctly indented";
                }

                my $joggingSide = sub {
                    my ( $node, $runeColumn ) = @_;
                    my $children  = $node->{children};
                    my %sideCount = ();
                    my $firstSide;
                    my %bodyColumnCount = ();
                    my $kingsideCount   = 0;
                    my $queensideCount  = 0;
                  CHILD: for my $childIX ( 0 .. $#$children ) {
                        my $jog  = $children->[$childIX];
                        my $symbol = $jog->{symbol};
                        next CHILD if defined $symbol and $symbolReverseDB{$symbol}->{gap};
                        my $head = $jog->{children}->[0];
                        my ( undef, $column1 ) = line_column( $head->{start} );
                        # say " $column1 - $runeColumn >= 4 ";
                        if ( $column1 - $runeColumn >= 4 ) {
                            $queensideCount++;
                            next CHILD;
                        }
                        $kingsideCount++;
                    }
                    return $kingsideCount > $queensideCount
                      ? 'kingside'
                      : 'queenside';
                };

                my $joggingBodyAlignment = sub {
                    my ( $node, $runeColumn ) = @_;
                    my $children = $node->{children};
                    my $firstBodyColumn;
                    my %firstLine       = ();
                    my %bodyColumnCount = ();

                    # Traverse first to last to make it easy to record
                    # first line of occurrence of each body column
                  CHILD:
                    for ( my $childIX = $#$children ; $childIX >= 0; $childIX-- ) {
                        my $jog         = $children->[$childIX];
                        my $jogChildren = $jog->{children};
                        my $gap         = $jogChildren->[1];
                        my $gapLength   = $gap->{length};
                        my $body = $jogChildren->[2];
                        my ( $bodyLine, $bodyColumn ) =
                          line_column( $body->{start} );
                        $firstBodyColumn = $bodyColumn
                          if not defined $firstBodyColumn;
                        next CHILD unless $gap > 2;
                        $bodyColumnCount{$bodyColumn} =
                          $bodyColumnCount{$bodyColumn}++;
                        $firstLine{$bodyColumn} = $bodyLine;
                    }
                    my @bodyColumns = keys %bodyColumnCount;

                    # If no aligned columns, simply return first
                    return $firstBodyColumn if not @bodyColumns;

                    my @sortedBodyColumns =
                      sort {
                             $bodyColumnCount{$a} <=> $bodyColumnCount{$b}
                          or $firstLine{$b} <=> $firstLine{$a}
                      }
                      keys %bodyColumnCount;
                    my $topBodyColumn = $sortedBodyColumns[$#sortedBodyColumns];
                    return $topBodyColumn;
                };

                my $censusJoggingHoon = sub {
                    my ($node) = @_;
                    my ( undef, $runeColumn ) = line_column( $node->{start} );
                  CHILD: for my $childIX ( 0 .. $#$children ) {
                        my $child  = $children->[$childIX];
                        my $symbol = symbol($child);
                        next CHILD if $symbol ne 'rick5d' and $symbol ne 'ruck5d';
                        my $side = $joggingSide->($child, $runeColumn);
                        my $bodyAlignment = $joggingBodyAlignment->($child, $runeColumn);
                        return $side, $bodyAlignment;
                    }
                  die "No jogging found for ", symbol($node);
                };

                sub is_0Jogging {
                    my ( $runeLine, $runeColumn, $gapIndents ) = @_;
                    my @mistakes = ();
                    die "Jogging-0-style rule with only $gapIndents gap indents"
                      if $#$gapIndents < 2;

                    # Second child must be on rune line, or
                    # at ruleColumn+2
                    my ( $firstChildLine, $firstChildColumn ) =
                      @{ $gapIndents->[1] };

                    if (    $firstChildLine != $runeLine
                        and $firstChildColumn != $runeColumn + 2 )
                    {
                        my $msg = sprintf
    "Jogging-0-style child #%d @%d:%d; %s",
                          2, $firstChildLine,
                          $firstChildColumn+1,
                          describeMisindent($firstChildColumn, $runeColumn + 2);
                        push @mistakes,
                          {
                            desc           => $msg,
                            line           => $firstChildLine,
                            column         => $firstChildColumn,
                            child          => 2,
                            expectedColumn => $runeColumn + 2,
                          };
                    }

                    my ( $tistisLine, $tistisColumn ) = @{ $gapIndents->[2] };
                    if ( $tistisLine == $runeLine ) {
                        my $msg = sprintf
    "Jogging-0-style line %d; TISTIS is on rune line %d; should not be",
                          $runeLine, $tistisLine;
                        push @mistakes,
                          {
                            desc         => $msg,
                            line         => $tistisLine,
                            column       => $tistisColumn,
                            child        => 3,
                            expectedLine => $runeLine,
                          };
                    }

                    my $tistisIsMisaligned = $tistisColumn != $runeColumn;
                    # say join " ", __FILE__, __LINE__, $tistisColumn , $runeColumn;
                    if ($tistisIsMisaligned) {
                       my $tistisPos = $lineToPos[$tistisLine]+$tistisColumn;
                       my $tistis = literal($tistisPos, 2);
                        # say join " ", __FILE__, __LINE__, $tistis;
                       $tistisIsMisaligned = $tistis ne '==';
                    }
                    if ( $tistisIsMisaligned ) {
                        my $msg = sprintf "Jogging-0-style; TISTIS @%d:%d; %s",
                          $tistisLine, $tistisColumn+1,
                          describeMisindent( $tistisColumn, $runeColumn);
                        push @mistakes,
                          {
                            desc           => $msg,
                            line           => $tistisLine,
                            column         => $tistisColumn,
                            child          => 3,
                            expectedColumn => $runeColumn,
                          };
                    }
                    return \@mistakes;
                }

                my $isJogging1 = sub {
                    my ( $context, $node, $gapIndents ) = @_;
                    my $start = $node->{start};
                    my ( $runeLine, $runeColumn ) = line_column($start);
                    my ( $chessSide, $jogBodyColumn ) =
                      $censusJoggingHoon->($node);
                    $context->{chessSide} = $chessSide;

              # say join " ", __FILE__, __LINE__, "set chess side:", $chessSide;
                    $context->{jogRuneColumn} = $runeColumn;

# say join " ", __FILE__, __LINE__, "set rune column:", $context->{jogRuneColumn} ;

                    $context->{jogBodyColumn} = $jogBodyColumn
                      if defined $jogBodyColumn;
                    internalError("Chess side undefined") unless $chessSide;

             # say join " ", "=== jog census:", $side, ($flatJogColumn // 'na');
                    my @mistakes = ();
                    die "1-jogging rule with only $gapIndents gap indents"
                      if $#$gapIndents < 3;
                    my ( $firstChildLine, $firstChildColumn ) =
                      @{ $gapIndents->[1] };
                    if ( $firstChildLine != $runeLine ) {
                        my $msg = sprintf
                          "1-jogging %s head %s; should be on rune line %d",
                          $chessSide,
                          describeLC( $firstChildLine, $firstChildColumn ),
                          $runeLine;
                        push @mistakes,
                          {
                            desc         => $msg,
                            line         => $firstChildLine,
                            column       => $firstChildColumn,
                            child        => 1,
                            expectedLine => $runeLine,
                          };
                    }

                    my $expectedColumn =
                      $runeColumn + ( $chessSide eq 'kingside' ? 4 : 6 );
                    if ( $firstChildColumn != $expectedColumn ) {
                        my $msg = sprintf
                          "1-jogging %s head %s; %s",
                          $chessSide,
                          describeLC( $firstChildLine, $firstChildColumn ),
                          describeMisindent( $firstChildColumn,
                            $expectedColumn );
                        push @mistakes,
                          {
                            desc           => $msg,
                            line           => $firstChildLine,
                            column         => $firstChildColumn,
                            child          => 1,
                            expectedColumn => $expectedColumn,
                          };
                    }

                    my ( $tistisLine, $tistisColumn ) = @{ $gapIndents->[3] };
                    if ( $tistisLine == $runeLine ) {
                        my $msg = sprintf
                          "1-jogging TISTIS %s; should not be on rune line",
                          $chessSide,
                          describeLC( $tistisLine, $tistisColumn );
                        push @mistakes,
                          {
                            desc         => $msg,
                            line         => $tistisLine,
                            column       => $tistisColumn,
                            child        => 3,
                            expectedLine => $runeLine,
                          };
                    }

                    my $tistisIsMisaligned = $tistisColumn != $runeColumn;

                # say join " ", __FILE__, __LINE__, $tistisColumn , $runeColumn;
                    if ($tistisIsMisaligned) {
                        my $tistisPos = $lineToPos[$tistisLine] + $tistisColumn;
                        my $tistis = literal( $tistisPos, 2 );

                        # say join " ", __FILE__, __LINE__, $tistis;
                        $tistisIsMisaligned = $tistis ne '==';
                    }
                    if ($tistisIsMisaligned) {
                        my $msg = sprintf "1-jogging TISTIS %s; %s",
                          describeLC( $tistisLine, $tistisColumn ),
                          describeMisindent( $tistisColumn, $runeColumn );
                        push @mistakes,
                          {
                            desc           => $msg,
                            line           => $tistisLine,
                            column         => $tistisColumn,
                            child          => 3,
                            expectedColumn => $runeColumn,
                          };
                    }
                    return \@mistakes;
                };

                my $isJogging2 = sub  {
                    my ( $context, $node, $gapIndents ) = @_;
                    my $start  = $node->{start};
                    my ( $runeLine, $runeColumn ) = line_column($start);
                    my ( $chessSide, $jogBodyColumn ) = $censusJoggingHoon->($node);
                    $context->{chessSide} = $chessSide;
                    # say join " ", __FILE__, __LINE__, "set chess side:", $chessSide;
                    $context->{jogRuneColumn} = $runeColumn;
                    $context->{jogBodyColumn} = $jogBodyColumn if $jogBodyColumn;
                    internalError("Chess side undefined") unless $chessSide;
                    # say join " ", "=== jog census:", $side, ($flatJogColumn // 'na');
                    my @mistakes = ();
                    my ( $firstChildLine, $firstChildColumn ) =
                      @{ $gapIndents->[1] };
                    if ( $firstChildLine != $runeLine ) {
                        my $msg = sprintf
    "Jogging-2-style child #%d @ line %d; first child is on line %d; should be on rune line",
                          1, $runeLine, $firstChildLine;
                        push @mistakes,
                          {
                            desc         => $msg,
                            line         => $firstChildLine,
                            column       => $firstChildColumn,
                            child        => 1,
                            expectedLine => $runeLine,
                          };
                    }

                    my $expectedColumn = $runeColumn + ($chessSide eq 'kingside' ? 6 : 8);
                    if ( $firstChildColumn != $expectedColumn) {
                        my $msg = sprintf
    "Jogging-2-style %s child #%d @%d:%d; %s",
                          $chessSide, 1, $runeLine,
                          $firstChildColumn+1,
                          describeMisindent( $firstChildColumn, $expectedColumn);
                        push @mistakes,
                          {
                            desc           => $msg,
                            line           => $firstChildLine,
                            column         => $firstChildColumn,
                            child          => 1,
                            expectedColumn => $expectedColumn,
                          };
                    }

                    # Second child must be on rune line, or
                    # at chess-side-dependent column
                    $expectedColumn = $runeColumn + ($chessSide eq 'kingside' ? 4 : 6);
                    my ( $secondChildLine, $secondChildColumn ) =
                      @{ $gapIndents->[2] };

                    if (    $secondChildLine != $runeLine
                        and $secondChildColumn != $expectedColumn )
                    {
                        my $msg = sprintf
    "Jogging-2-style %s child #%d @%d:%d; %s",
                          $chessSide,
                          2, $secondChildLine,
                          $secondChildColumn+1,
                          describeMisindent($secondChildColumn, $expectedColumn);
                        push @mistakes,
                          {
                            desc           => $msg,
                            line           => $secondChildLine,
                            column         => $secondChildColumn,
                            child          => 2,
                            expectedColumn => $expectedColumn,
                          };
                    }

                    my ( $tistisLine, $tistisColumn ) = @{ $gapIndents->[4] };
                    if ( $tistisLine == $runeLine ) {
                        my $msg = sprintf
    "Jogging-2-style line %d; TISTIS is on rune line %d; should not be",
                          $runeLine, $tistisLine;
                        push @mistakes,
                          {
                            desc         => $msg,
                            line         => $tistisLine,
                            column       => $tistisColumn,
                            child        => 3,
                            expectedLine => $runeLine,
                          };
                    }

                    my $tistisIsMisaligned = $tistisColumn != $runeColumn;
                    # say join " ", __FILE__, __LINE__, $tistisColumn , $runeColumn;
                    if ($tistisIsMisaligned) {
                       my $tistisPos = $lineToPos[$tistisLine]+$tistisColumn;
                       my $tistis = literal($tistisPos, 2);
                        # say join " ", __FILE__, __LINE__, $tistis;
                       $tistisIsMisaligned = $tistis ne '==';
                    }
                    if ( $tistisIsMisaligned ) {
                        my $msg = sprintf "Jogging-2-style; TISTIS @%d:%d; %s",
                          $tistisLine, $tistisColumn+1,
                          describeMisindent( $tistisColumn, $runeColumn);
                        push @mistakes,
                          {
                            desc           => $msg,
                            line           => $tistisLine,
                            column         => $tistisColumn,
                            child          => 3,
                            expectedColumn => $runeColumn,
                          };
                    }
                    return \@mistakes;
                };

                my $isJogging_1 = sub  {
                    my ( $context, $node, $gapIndents ) = @_;
                    my $start  = $node->{start};
                    my ( $runeLine, $runeColumn ) = line_column($start);
                    my ( $chessSide, $jogBodyColumn ) = $censusJoggingHoon->($node);
                    $context->{chessSide} = $chessSide;
                    # say join " ", __FILE__, __LINE__, "set chess side:", $chessSide;
                    $context->{jogRuneColumn} = $runeColumn;
                    $context->{jogBodyColumn} = $jogBodyColumn if defined $jogBodyColumn;
                    internalError("Chess side undefined") unless $chessSide;
                    # say join " ", "=== jog census:", $side, ($flatJogColumn // 'na');
                    my @mistakes = ();
                    die "Jogging-prefix rule with only $gapIndents gap indents"
                      if $#$gapIndents < 3;

                    my ( $tistisLine, $tistisColumn ) = @{ $gapIndents->[2] };
                    if ( $tistisLine == $runeLine ) {
                        my $msg = sprintf
    "Jogging-prefix line %d; TISTIS is on rune line %d; should not be",
                          $runeLine, $tistisLine;
                        push @mistakes,
                          {
                            desc         => $msg,
                            line         => $tistisLine,
                            column       => $tistisColumn,
                            child        => 3,
                            expectedLine => $runeLine,
                          };
                    }

                    my $expectedColumn =  $runeColumn + 2;
                    my $tistisIsMisaligned = $tistisColumn != $expectedColumn;
                    # say join " ", __FILE__, __LINE__, $tistisColumn , $runeColumn;
                    if ($tistisIsMisaligned) {
                       my $tistisPos = $lineToPos[$tistisLine]+$tistisColumn;
                       my $tistis = literal($tistisPos, 2);
                        # say join " ", __FILE__, __LINE__, $tistis;
                       $tistisIsMisaligned = $tistis ne '==';
                    }
                    if ( $tistisIsMisaligned ) {
                        my $msg = sprintf "Jogging-prefix; TISTIS @%d:%d; %s",
                          $tistisLine, $tistisColumn+1,
                          describeMisindent( $tistisColumn, $runeColumn);
                        push @mistakes,
                          {
                            desc           => $msg,
                            line           => $tistisLine,
                            column         => $tistisColumn,
                            child          => 3,
                            expectedColumn => $expectedColumn,
                          };
                    }

                    my ( $thirdChildLine, $thirdChildColumn ) =
                      @{ $gapIndents->[3] };

		    # TODO: No examples of "jogging prefix" queenside in arvo/ corpus
                    $expectedColumn = $runeColumn;
                    if ( $thirdChildColumn != $expectedColumn) {
                        my $msg = sprintf
    "Jogging-prefix %s child #%d @%d:%d; %s",
                          $chessSide, 1, $runeLine,
                          $thirdChildColumn+1,
                          describeMisindent( $thirdChildColumn, $expectedColumn);
                        push @mistakes,
                          {
                            desc           => $msg,
                            line           => $thirdChildLine,
                            column         => $thirdChildColumn,
                            child          => 1,
                            expectedColumn => $expectedColumn,
                          };
                    }

                    return \@mistakes;
                };

                my $checkKingsideJog = sub {
                    my ( $node, $context ) = @_;
                    # say join " ", __FILE__, __LINE__, "rune column:", $context->{jogRuneColumn} ;
                    my $chessSide = $context->{chessSide};
                    say STDERR Data::Dumper::Dumper(
                        [
                            $context->{hoonName},
                            $fileName,
                            ( line_column( $node->{start} ) ),
                            map { $grammar->symbol_display_form($_) }
                              $grammar->rule_expand($ruleID)
                        ]
                    ) unless $chessSide;    # TODO: Delete after development
                    internalError("Chess side undefined") unless $chessSide;

                    my @mistakes = ();

                    my $runeColumn    = $context->{jogRuneColumn};
                    say STDERR Data::Dumper::Dumper(
                        [
                            $context->{hoonName},
                            $fileName,
                            ( line_column( $node->{start} ) ),
                            map { $grammar->symbol_display_form($_) }
                              $grammar->rule_expand($ruleID)
                        ]
                    ) unless defined $runeColumn;    # TODO: Delete after development
                    internalError("Rune column undefined") unless defined $runeColumn;
                    my $jogBodyColumn = $context->{jogBodyColumn};

                    # say join " ", __FILE__, __LINE__, "rune column:", $context->{jogRuneColumn} ;

                    # do not pass these attributes on to child nodes
                    delete $context->{jogRuneColumn};
                    delete $context->{jogBodyColumn};
                    delete $context->{chessSide};

                    my $children = $node->{children};
                    my $head     = $children->[0];
                    my $gap      = $children->[1];
                    my $body     = $children->[2];
                    my ( $headLine, $headColumn ) =
                      line_column( $head->{start} );
                    my ( $bodyLine, $bodyColumn ) =
                      line_column( $body->{start} );
                    my $sideDesc = 'kingside';

                    my $expectedHeadColumn = $runeColumn + 2;
                    if ( $headColumn != $expectedHeadColumn ) {
                        my $msg = sprintf 'Jog %s head %s; %s',
                          $sideDesc,
                          describeLC( $headLine, $headColumn ),
                          describeMisindent( $headColumn, $expectedHeadColumn );
                        push @mistakes,
                          {
                            desc           => $msg,
                            line           => $headLine,
                            column         => $headColumn,
                            child          => 1,
                            expectedColumn => $expectedHeadColumn,
                          };
                    }

                    if ( $headLine != $bodyLine ) {

                        # Check for "seaside"
                        my $expectedBodyColumn = $runeColumn + 4;
                        if ( $bodyColumn != $expectedBodyColumn ) {
                            my $msg = sprintf 'Jog %s body %s; %s',
                              $sideDesc, describeLC( $bodyLine, $bodyColumn ),
                              describeMisindent( $bodyColumn,
                                $expectedBodyColumn );
                            push @mistakes,
                              {
                                desc           => $msg,
                                line           => $bodyLine,
                                column         => $bodyColumn,
                                child          => 2,
                                expectedColumn => $expectedBodyColumn,
                              };
                        }
                        return \@mistakes;
                    }

                    # Check for flat kingside misalignments
                    my $gapLength = $gap->{length};
                    if ( $gapLength != 2 and $bodyColumn != $jogBodyColumn ) {
                        my $msg = sprintf 'Jog %s body %s; %s',
                          $sideDesc,
                          describeLC( $bodyLine, $bodyColumn ),
                          describeMisindent( $bodyColumn, $jogBodyColumn );
                        push @mistakes,
                          {
                            desc           => $msg,
                            line           => $bodyLine,
                            column         => $bodyColumn,
                            child          => 2,
                            expectedColumn => $jogBodyColumn,
                          };
                    }
                    return \@mistakes;
                };

                my $checkQueensideJog = sub {
                    my ( $node, $context ) = @_;

# say join " ", __FILE__, __LINE__, "set rune column:", $context->{jogRuneColumn} ;
                    my $chessSide = $context->{chessSide};
                    die Data::Dumper::Dumper(
                        [
                            $fileName,
                            ( line_column( $node->{start} ) ),
                            map { $grammar->symbol_display_form($_) }
                              $grammar->rule_expand($ruleID)
                        ]
                    ) unless $chessSide;    # TODO: Delete after development
                    internalError("Chess side undefined") unless $chessSide;

                    my @mistakes = ();

                    my $runeColumn    = $context->{jogRuneColumn};
                    my $jogBodyColumn = $context->{jogBodyColumn};

                    # do not pass these attributes on to child nodes
                    delete $context->{jogRuneColumn};
                    delete $context->{jogBodyColumn};
                    delete $context->{chessSide};

                    my $children = $node->{children};
                    my $head     = $children->[0];
                    my $gap      = $children->[1];
                    my $body     = $children->[2];
                    my ( $headLine, $headColumn ) =
                      line_column( $head->{start} );
                    my ( $bodyLine, $bodyColumn ) =
                      line_column( $body->{start} );
                    my $sideDesc = 'queenside';

                    my $expectedHeadColumn = $runeColumn + 4;
                    if ( $headColumn != $expectedHeadColumn ) {
                        my $msg = sprintf 'Jog %s head %s; %s',
                          $sideDesc,
                          describeLC( $headLine, $headColumn ),
                          describeMisindent( $headColumn, $expectedHeadColumn );
                        push @mistakes,
                          {
                            desc           => $msg,
                            line           => $headLine,
                            column         => $headColumn,
                            child          => 1,
                            expectedColumn => $expectedHeadColumn,
                          };
                    }

                    my $expectedBodyColumn = $runeColumn + 2;
                    if (    $headLine != $bodyLine
                        and $bodyColumn != $expectedBodyColumn )
                    {

                        my $msg = sprintf 'Jog %s body %s; %s',
                          $sideDesc,
                          describeLC( $bodyLine, $bodyColumn ),
                          describeMisindent( $bodyColumn, $expectedBodyColumn );
                        push @mistakes,
                          {
                            desc           => $msg,
                            line           => $bodyLine,
                            column         => $bodyColumn,
                            child          => 2,
                            expectedColumn => $expectedBodyColumn,
                          };
                    }

                    # Check for flat queenside misalignments
                    if ( $headLine == $bodyLine ) {
                        $expectedBodyColumn = $jogBodyColumn;
                        my $gapLength = $gap->{length};
                        if ( $gapLength != 2 and $bodyColumn != $jogBodyColumn )
                        {
                            my $msg = sprintf 'Jog %s body %s; %s',
                              $sideDesc,
                              describeLC( $bodyLine, $bodyColumn ),
                              describeMisindent( $bodyColumn, $jogBodyColumn );
                            push @mistakes,
                              {
                                desc           => $msg,
                                line           => $bodyLine,
                                column         => $bodyColumn,
                                child          => 2,
                                expectedColumn => $jogBodyColumn,
                              };
                        }
                    }
                    return \@mistakes;
                };

                # TODO: Add a check (optional?) for queenside joggings with no
                # split jogs.
                my $isJog = sub {
                    my ( $node, $context ) = @_;
                    # say join " ", __FILE__, __LINE__, "set rune column:", $context->{jogRuneColumn} ;
                    my $chessSide = $context->{chessSide};
                    return $checkQueensideJog->( $node, $context )
                      if $chessSide eq 'queenside';
                    return $checkKingsideJog->( $node, $context );
                };

                sub isBackdented {
                    my ( $indents, $baseIndent ) = @_;
                    my @mistakes = ();

                    # say Data::Dumper::Dumper($indents);
                    my ( $baseLine, $baseColumn ) = @{ $indents->[0] };
                    $baseIndent //= $baseColumn;
                    my $currentIndent = $baseIndent + $#$indents * 2;
                    my $lastLine      = $baseLine;
                  INDENT: for my $ix ( 1 .. $#$indents ) {
                        my $indent = $indents->[$ix];
                        my ( $thisLine, $thisColumn ) = @{$indent};
                        $currentIndent -= 2;

                        # say "$currentIndent vs. $thisColumn";
                        next INDENT if $thisLine == $lastLine;
                        if ( $currentIndent != $thisColumn ) {
                            my $msg = sprintf
                              "Child #%d @ line %d; backdent is %d; should be %d",
                              $ix, $thisLine, $thisColumn, $currentIndent;
                            push @mistakes,
                              {
                                desc           => $msg,
                                line           => $thisLine,
                                column         => $thisColumn,
                                child          => $ix,
                                backdentColumn => $currentIndent,
                              };
                        }
                        $lastLine = $thisLine;
                    }
                    return \@mistakes;
                }

             # By default, report anomalies in terms of differences from backdenting
             # to the rule start.
                sub defaultMistakes {
                    my ( $indents, $type ) = @_;
                    my $mistakes = isBackdented($indents);
                    return [ { desc => "Undetected mistakes" } ]
                      if not @{$mistakes};
                    for my $mistake ( @{$mistakes} ) {
                        my $mistakeChild  = $mistake->{child};
                        my $mistakeColumn = $mistake->{column};
                        my $defaultColumn = $mistake->{backdentColumn};
                        my $mistakeLine   = $mistake->{line};
                        my $msg           = sprintf
                          "$type child #%d; line %d; indent=%d vs. default of %d",
                          $mistakeChild, $mistakeLine, $mistakeColumn,
                          $defaultColumn;
                        $mistake->{desc} = $msg;
                    }
                    return $mistakes;
                }

                sub isFlat {
                    my ($indents)   = @_;
                    my ($firstLine) = @{ $indents->[0] };
                    my ($lastLine)  = @{ $indents->[$#$indents] };
                    return $firstLine == $lastLine;
                }

                my $displayMistakes = sub {

                    # say join " ", __FILE__, __LINE__, "displayMistakes()";
                    my ( $mistakes, $hoonDesc ) = @_;
                    my $parentLC = join ':', $parentLine, $parentColumn + 1;
                    my @pieces = ();
                  MISTAKE: for my $mistake ( @{$mistakes} ) {

                        # say join " ", __FILE__, __LINE__, "displayMistakes()";
                        my $desc        = $mistake->{desc};
                        my $type        = $mistake->{type};
                        my $mistakeLine = $mistake->{line};

                    next MISTAKE
                      if $inclusions and not $inclusions->{$type}{$parentLC};

                        push @pieces,
                          reportItem(
                            (
                                    "$fileName $parentLC $type $hoonDesc $desc"
                            ),
                            $parentLine,
                            $mistakeLine,
                            $contextLines
                          );
                    }
                    return join "", @pieces;
                };

          # say STDERR __LINE__, " parentIndents: ", (join " ", @parentIndents);
          # if here, gapiness > 0
            {
                my $mistakes = [];
                my $start    = $node->{start};

                my $indentDesc = '???';

                my @gapIndents = @{$calcGapIndents->($node)};

              TYPE_INDENT: {

                    my $suppression = $suppressions->{'indent'}{$parentLC};
                    if ( defined $suppression ) {
                        $indentDesc = "SUPPRESSION $suppression";
                        $unusedSuppressions->{'indent'}{$parentLC} = undef;
                        last TYPE_INDENT;
                    }

                    if ( $tallJogRule{$lhsName} ) {
                        $mistakes = $isJog->( $node, $parentContext );
                        last TYPE_INDENT if @{$mistakes};
                        $indentDesc = 'JOG-STYLE';
                        last TYPE_INDENT;
                    }

                    # if ( isFlat( \@gapIndents ) ) {
                        # $indentDesc = 'FLAT';
                        # last TYPE_INDENT;
                    # }

                    if ( $tall_0JoggingRule{$lhsName} ) {
                        $mistakes =
                          is_0Jogging( $parentLine, $parentColumn, \@gapIndents );
                        last TYPE_INDENT if @{$mistakes};
                        $indentDesc = 'JOGGING-0-STYLE';
                        last TYPE_INDENT;
                    }

                    if ( $tall_1JoggingRule{$lhsName} ) {
                        $mistakes =
                          $isJogging1->( $parentContext, $node, \@gapIndents );
                        last TYPE_INDENT if @{$mistakes};
                        $indentDesc = 'JOGGING-1-STYLE';
                        last TYPE_INDENT;
                    }

                    if ( $tall_2JoggingRule{$lhsName} ) {
                        $mistakes =
                          $isJogging2->( $parentContext, $node, \@gapIndents );
                        last TYPE_INDENT if @{$mistakes};
                        $indentDesc = 'JOGGING-2-STYLE';
                        last TYPE_INDENT;
                    }

                    if ( $tallJogging1_Rule{$lhsName} ) {
                        $mistakes =
                          $isJogging_1->( $parentContext, $node, \@gapIndents );
                        last TYPE_INDENT if @{$mistakes};
                        $indentDesc = 'JOGGING-PREFIX-STYLE';
                        last TYPE_INDENT;
                    }

                    if ( $tallNoteRule{$lhsName} ) {
                        $mistakes = isBackdented( \@gapIndents, $noteIndent );
                        last TYPE_INDENT if @{$mistakes};
                        $indentDesc = 'CAST-STYLE';
                        last TYPE_INDENT;
                    }

                    if ( $tallLuslusRule{$lhsName} ) {
                        $mistakes = isLuslusStyle( \@gapIndents );
                        last TYPE_INDENT if @{$mistakes};
                        $indentDesc = 'LUSLUS-STYLE';
                        last TYPE_INDENT;
                    }

                    # By default, treat as backdented
                    $mistakes = isBackdented( \@gapIndents );
                    if ( not @{$mistakes} ) {
                        $indentDesc = 'BACKDENTED';
                        last TYPE_INDENT;
                    }

                }

              PRINT: {
          # say join " ", __FILE__, __LINE__, "$lhsName", (scalar @{$mistakes});
                    if ( @{$mistakes} ) {
                        $_->{type} = 'indent' for @{$mistakes};
                        print $displayMistakes->($mistakes, diagName($node, $parentContext));
                        last PRINT;
                    }

                    if ($censusWhitespace) {
                        print reportItem(
                        (sprintf "$fileName %s indent %s %s",
                              ( join ':', $recce->line_column($start) ),
                              diagName($node, $parentContext), $indentDesc),
                            $parentLine, $parentLine, $contextLines );
                    }
                }
            }
        }    # End of whitespace "policy"
    }

  CHILD: for my $childIX ( 0 .. $#$children ) {
        my $child = $children->[$childIX];
        doLint( $child, $parentContext );
    }
}

# TODO: ancestors, indents in favor of tree traversal
doLint( $astValue, { hoonName => '[TOP]', line => -1, indents => [], ancestors => [] } );

for my $type ( keys %{$unusedSuppressions} ) {
    for my $tag (
        grep { $unusedSuppressions->{$type}{$_} }
        keys %{ $unusedSuppressions->{$type} }
      )
    {
        say "Unused suppression: $type $tag";
    }
}

# vim: expandtab shiftwidth=4:
