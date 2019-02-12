# Hoon "tidy" utility

use 5.010;
use strict;
use warnings;
no warnings 'recursion';

package MarpaX::YAHC::Lint;

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
my $contextSize = 0;

GetOptions(
    "verbose"             => \$verbose,
    "context|C=i"         => \$contextSize,
    "census-whitespace"   => \$censusWhitespace,
    "inclusions-file|I=s" => \$inclusionsFileName,
    "suppressions_file|S=s" => \@suppressionsFileNames,
) or die("Error in command line arguments\n");

sub usage {
    die "usage: $PROGRAM_NAME [options ...] fileName\n";
}

usage() if scalar @ARGV != 1;
my $fileName = $ARGV[0];

# Eventually this will be packaged as a Perl module,
# and the rare user who needs multiple lint instances
# will be able to create them.  Right now there is only
# one
my $lintInstance = {};
bless $lintInstance, "MarpaX::YAHC::Lint";

no warnings 'once';
$lintInstance->{fileName} = $fileName;
no warnings 'recursion';

$lintInstance->{censusWhitespace} = [];
$lintInstance->{topicLines} = [];
$lintInstance->{mistakeLines} = {};

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
$lintInstance->{suppressions} = $suppressions;
$lintInstance->{unusedSuppressions} = $unusedSuppressions;

my $pInclusions;
my ( $inclusions, $unusedInclusions );
if ( defined $inclusionsFileName ) {
    $pInclusions = slurp($inclusionsFileName);
    ( $inclusions, $unusedInclusions ) = parseReportItems($pInclusions);
    die $unusedInclusions if not $inclusions;
}
$lintInstance->{inclusions} = $inclusions;
$lintInstance->{unusedInclusions} = $unusedInclusions;

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

$lintInstance->{pHoonSource} = $pHoonSource;
$lintInstance->{contextSize} = $contextSize;

my @data = ();
my $recce;

my $semantics = <<'EOS';
:default ::= action=>MarpaX::YAHC::Lint::doNode
lexeme default = latm => 1 action=>[start,length,name]
EOS

my $parser = MarpaX::YAHC::new( { semantics => $semantics, all_symbols => 1 } );
my $dsl = $parser->dsl();
my $lintGrammar = $parser->rawGrammar();
$lintInstance->{grammar} = $lintGrammar;

my %tallRuneRule = map { +( $_, 1 ) } grep {
         /^tall[B-Z][aeoiu][b-z][b-z][aeiou][b-z]$/
      or /^tall[B-Z][aeoiu][b-z][b-z][aeiou][b-z]Mold$/
} map { $lintGrammar->symbol_name($_); } $lintGrammar->symbol_ids();

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
$lintInstance->{mortarLHS} = \%mortarLHS;

my %tallBodyRule =
  map { +( $_, 1 ) } grep { not $tallNoteRule{$_} } keys %tallRuneRule;
$lintInstance->{tallBodyRule} = \%tallBodyRule;

# TODO: These are *not* jogging rules.  Change the name and look
# at the logic.
my %tall_0JoggingRule = map { +( $_, 1 ) } qw(tallWutbar tallWutpam);
$lintInstance->{tall_0JoggingRule} = \%tall_0JoggingRule;

my %tall_1JoggingRule =
  map { +( $_, 1 ) } qw(tallCentis tallCencab tallWuthep);
$lintInstance->{tall_1JoggingRule} = \%tall_1JoggingRule;

my %tall_2JoggingRule = map { +( $_, 1 ) } qw(tallCentar tallWutlus);
$lintInstance->{tall_2JoggingRule} = \%tall_2JoggingRule;

my %tallJogging1_Rule = map { +( $_, 1 ) } qw(tallTiscol);
$lintInstance->{tallJogging1_Rule} = \%tallJogging1_Rule;

my %tallLuslusRule = map { +( $_, 1 ) } qw(LuslusCell LushepCell LustisCell
  optFordFashep optFordFaslus fordFaswut fordFastis);
$lintInstance->{tallLuslusRule} = \%tallLuslusRule;

my %tallJogRule      = map { +( $_, 1 ) } qw(rick5dJog ruck5dJog);
$lintInstance->{tallJogRule} = \%tallJogRule;

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
      map { $lintGrammar->symbol_display_form($_) } $lintGrammar->rule_expand($ruleID);
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

        $node = {
            type     => 'node',
            ruleID   => $ruleID,
            start    => $lhsStart,
            length   => $lhsLength,
            children => \@results,
        };
    }

        # Add weak links
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
$lintInstance->{recce} = $recce;

$parser = undef;                 # free up memory
my $astRef = $recce->value();

sub literal {
    my ( $start, $length ) = @_;
    return substr ${$pHoonSource}, $start, $length;
}

my @lineToPos = (-1, 0);
while (${$pHoonSource} =~ m/\n/g) { push @lineToPos, pos ${$pHoonSource} };
$lintInstance->{lineToPos} = \@lineToPos;

sub column {
    my ($instance, $pos) = @_;
    my $pSource = $instance->{pHoonSource};
    return $pos - ( rindex ${$pSource}, "\n", $pos - 1 );
}

sub contextDisplay {
     say STDERR join " ", __FILE__, __LINE__, "context2()";
    my ( $instance ) = @_;
    my $pTopicLines = $instance->{topicLines};
    my $pMistakeLines = $instance->{mistakeLines};
    my $contextSize = $instance->{contextSize};
    my @pieces      = ();
    my %tag         = map { $_ => q{>} } @{$pTopicLines};
    $tag{$_} = q{!} for keys %{$pMistakeLines};
    my @sortedLines = sort { $a <=> $b } map { $_+0; } keys %tag;

     say STDERR join " ", __FILE__, __LINE__, "# of sorted lines:", (scalar @sortedLines);
    if ($contextSize <= 0) {
        for my $lineNum (@sortedLines) {
            my $mistakeDescs = $pMistakeLines->{$lineNum};
            for my $mistakeDesc (@{$mistakeDescs}) {
                push @pieces, $mistakeDesc, "\n";
            }
        }
        return join q{}, @pieces;
    }

    my $maxNumWidth = length q{} . $#lineToPos;
    my $lineNumFormat = q{%} . $maxNumWidth . 'd';

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
            my $mistakeDescs = $pMistakeLines->{$lineNum};
            for my $mistakeDesc (@{$mistakeDescs}) {
                push @pieces, '[ ', $mistakeDesc, " ]\n";
            }
            push @pieces, (sprintf $lineNumFormat, $lineNum), $tag, q{ }, $line;
        }
    };

    my $lastIX = -1;
  CONSEC_RANGE: while ( $lastIX < $#sortedLines ) {
        my $firstIX = $lastIX + 1;

        # Divider line if after first consecutive range
        push @pieces, ('-' x ($maxNumWidth+2)), "\n" if $firstIX > 0;
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
            $sortedLines[$firstIX] - ( $contextSize - 1 ),
            $sortedLines[$lastIX] + ( $contextSize - 1 )
        );
    }

    return join q{}, @pieces;
}

sub reportItem {
    my ( $instance, $mistakeDesc, $topicLineArg, $mistakeLineArg ) = @_;

    my $topicLines = $instance->{topicLines};
    my $mistakeLines = $instance->{mistakeLines};
    say join " ", __FILE__, __LINE__, "# topic lines:", (scalar @{ $instance->{topicLines}});
    say join " ", __FILE__, __LINE__, "# mistake lines:", (scalar %{ $instance->{mistakeLines}});
    push @{$topicLines},
      ref $topicLineArg ? @{$topicLineArg} : $topicLineArg;
    my $thisMistakeDescs = $mistakeLines->{$mistakeLineArg};
    $thisMistakeDescs = [] if not defined $thisMistakeDescs;
    push @{$thisMistakeDescs}, $mistakeDesc;
    $mistakeLines->{$mistakeLineArg} = $thisMistakeDescs;

}

sub displayMistakes {
    my ( $instance, $mistakes, $hoonDesc ) = @_;
    my $fileName = $instance->{fileName};

    say join " ", __FILE__, __LINE__, "displayMistakes()";
    my @pieces = ();
  MISTAKE: for my $mistake ( @{$mistakes} ) {

        # say join " ", __FILE__, __LINE__, "displayMistakes()";
        my $type = $mistake->{type};
        my $parentLine = $mistake->{parentLine};
        my $parentColumn = $mistake->{parentColumn};
    my $parentLC = join ':', $parentLine, $parentColumn + 1;
        next MISTAKE
          if $inclusions and not $inclusions->{$type}{$parentLC};

        my $desc              = $mistake->{desc};
        my $mistakeLine       = $mistake->{line};
        my $mistakeTopicLines = $mistake->{topicLines};
        my @topicLines        = ($parentLine);
        push @topicLines, @{$mistakeTopicLines} if $mistakeTopicLines;

        $instance->reportItem( ("$fileName $parentLC $type $hoonDesc $desc"),
            \@topicLines, $mistakeLine, );
    }
}

# The "symbol" of a node.  Not necessarily unique.
sub symbol {
    my ($instance, $node) = @_;
    my $grammar = $instance->{grammar};
    my $name = $node->{symbol};
    return $name if defined $name;
    my $type = $node->{type};
    die Data::Dumper::Dumper($node) if not $type;
    if ( $type eq 'node' ) {
        my $ruleID = $node->{ruleID};
        my ( $lhs, @rhs ) = $grammar->rule_expand($ruleID);
        return $grammar->symbol_name($lhs);
    }
    return "[$type]";
}

# Can be used as test of "brick-ness"
sub brickName {
    my ($instance, $node) = @_;
    my $grammar = $instance->{grammar};
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
    my ($instance, $node, $hoonName) = @_;
    my $grammar = $instance->{grammar};
    my $type = $node->{type};
    return symbol($node) if $type ne 'node';
    my $ruleID = $node->{ruleID};
    my ( $lhs, @rhs ) = $grammar->rule_expand($ruleID);
    my $lhsName = $grammar->symbol_name($lhs);
    return $lhsName if not $mortarLHS{$lhsName};
    internalError("No hoon name for $lhsName") if not $hoonName;
    return $hoonName;
}

# The "name" of a node.  Not necessarily unique
sub name {
    my ($instance, $node) = @_;
    my $grammar = $instance->{grammar};
    my $type = $node->{type};
    my $symbol = $instance->symbol($node);
    return $symbol if $type ne 'node';
    my $ruleID = $node->{ruleID};
    my ( $lhs, @rhs ) = $grammar->rule_expand($ruleID);
    return $symbol . '#' . ( scalar @rhs );
}

die "Parse failed" if not $astRef;

# local $Data::Dumper::Deepcopy = 1;
# local $Data::Dumper::Terse    = 1;
# local $Data::Dumper::Maxdepth    = 3;

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

$lintInstance->{ruleDB} = [];
$lintInstance->{symbolDB} = [];
$lintInstance->{symbolReverseDB} = {};

sub testStyleCensus {
  my ($instance) = @_;
  my $ruleDB = $instance->{ruleDB};
  my $symbolDB = $instance->{symbolDB};
  my $symbolReverseDB = $instance->{symbolReverseDB};
  my $grammar = $instance->{grammar};

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
        $symbolDB->[$symbolID] = $data;
        $symbolReverseDB->{$name} = $data;
    }
    my $gapID = $symbolReverseDB->{'GAP'}->{id};
  RULE:
    for my $ruleID ( $grammar->rule_ids() ) {
        my $data = { id => $ruleID };
        my ( $lhs, @rhs ) = $grammar->rule_expand($ruleID);
        $data->{symbols} = [ $lhs, @rhs ];
        my $lhsName       = $grammar->symbol_name($lhs);
        my $separatorName = $separator{$lhsName};
        if ($separatorName) {
            my $separatorID = $symbolReverseDB->{$separatorName}->{id};
            $data->{separator} = $separatorID;
            if ( $separatorID == $gapID ) {
                $data->{gapiness} = -1;
            }
        }
        if ( not defined $data->{gapiness} ) {
            for my $rhsID (@rhs) {
                $data->{gapiness}++ if $symbolDB->[$rhsID]->{gap};
            }
        }
        $ruleDB->[$ruleID] = $data;

say STDERR join " ", __FILE__, __LINE__, "setting rule $ruleID gapiness to", $data->{gapiness} // 'undef';
        $symbolReverseDB->{$lhs}->{lexeme} = 0;
    }

}

$lintInstance->testStyleCensus();

sub line_column {
   my ($instance, $pos) = @_;
   $Data::Dumper::Maxdepth = 3; die Data::Dumper::Dumper($instance) if not defined $instance->{recce};
   my ( $line, $column ) = $instance->{recce}->line_column($pos);
   $column--;
   return $line, $column;
}

sub brickLC {
    my ($instance, $node)     = @_;
    my $thisNode = $node;
    while ( $thisNode ) {
        return $instance->line_column($thisNode->{start}) if $instance->brickName($thisNode);
        $thisNode = $thisNode->{PARENT};
    }
    internalError("No brick parent");
};

LINT_NODE: {

    # "Policies" will go here
    # As of this writing, these is only one policy -- the "whitespace"
    # policy.

  WHITESPACE_POLICY: {
        require Test::Whitespace;
        my $policy = MarpaX::YAHC::Lint::Test::Whitespace->new($lintInstance);
        $policy->validate( $astValue,
            { hoonName => '[TOP]', line => -1, indents => [], ancestors => [] }
        );
    }
}


print $lintInstance->contextDisplay();

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
