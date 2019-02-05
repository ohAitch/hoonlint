# Hoon jogging indentation

## Terminology

### Jogging hoons

A hoon is a *jogging hoon* if it contains an element that
uses the jogging syntax.
A jogging element is more often called simply a *jogging*.
(Currently all hoons contains at most one jogging.)

In addition to the jogging, a jogging hoon may contain
other elements, either before or after the jogging.
An element after the jogging is called a *tail*.
If there is one element before the jogging, it
is called the *head* of the jogging hoon.
If there are two elements before the jogging, they
are called, in order, the *head* and *subhead* of
the jogging.

There are current four kinds of jogging.
A 0-jogging has no head and no tail.
A 1-jogging has one head and no tail.
A 2-jogging has a head and a subhead and no tail.
A jogging-1 has a tail and no head.

The current 0-jogging rules are WUTBAR (?|) and WUTPAM (?&).
The current 1-jogging rules are CENTIS (%=), CENCAB (%_) and WUTHEP (?-).
The current 2-jogging rules are CENTAR (%*) and WUTLUS (?+).
The current jogging-1 rule is TISCOL (=:).

### Jogs

A jogging is a gap-separated sequence of one or more jogs.
Every *jog* contains a *jog head*, followed by a gap and a *jog body*.
Note that it is important to distinguish between the head of a jogging
hood, defined above, and the head of a jog.

A jog is *flat* if its head and its body are both on the same line.
Otherwise, the jog is said to be *split*.

### Chess-sidedness

A jogs and jogging hoons have *chess-sidedness*.
Chess-sidedness is always either kingside and queenside.
No properly indented jogging or jogging hoon has "mixed"
sidedness.
What is called a "seasided" jog is a split kingside jog.

Informally, kingside means the indentation has a left-side bias;
and queenside means that the indentation has a right-side bias.
Indentation will be desribed more precisely in what follows.

### Lines, columns and indentation

In this document, a *stop* is two spaces.
We say the text `X` is indented `N` stops after text `Y`
if there are exactly `N` stops between the end of text `X`
and the beginning of text `Y`.

Let `Column(Y)` be column at which text `Y` begins.
We say the indentation of text `X` is `N` stops greater than
text `Y` if text `X` begins at column `Column(Y)+N*2`.
We say the indentation of text `X` is `N` stops less than
text `Y` if text `X` begins at column `Column(Y)-N*2`.

## Limitations of this current document

The rest of this document describes the indentation of the 1-jogging
rules only.
I expect to revise it to describe the other rules along similar lines.

## Proper spacing of 1-jogging hoons

Every jogging hoon is either kingside or queenside --
none of them are considered "mixed".
The *rune line* is the line on which the rune occurs,
and the *rune column* is the column at which the rune begins.


"Sidedness" must be consistent:

* The head of a kingside jogging hoon must be kingside.
It should be on the rune line,
indented 1 stop after the rune.

* The jogging of a kingside jogging hoon must be kingside.
It should be on a line after the rune line,
and should consist entirely of kingside jogs.

* The head of a queenside jogging hoon must be queenside
It should be on the rune line,
indented 2 stops after the rune.

* The jogging of a queenside jogging hoon must be queenside.
It should be on a line after the rune line,
and should consist entirely of queenside jogs.

The indentation of a jog is that of its head.
A kingside jog must have an indentation 1 stop greater than
the rune column.
A queenside jog must have an indentation 2 stops greater than
the rune column.

A flat jog may be either *aligned* or *ragged*.
A flat jog is ragged is its body is indented 1 stop after
its head.
Otherwise, a flat jog is considered aligned.

All aligned jogs in a jogging must be indented to the
same column.
This column is called the *jog body column* of the jogging.

The indentation of the body of a split kingside jog
should be 1 stop greater than the indentation of the jog's head.
A split kingside is sometimes called "seaside",
because of the resemblance of its indentation to the indentation
common in C language code.

The indentation of the body of a split queenside jog
should be 1 stop less than the indentation of the jog's head.

## Sidedness in misindented hoons

For linting purposes, it is necessary to decide the intended
chess-sidedness.
A jog is consider queenside if its indentation is 2 stops or more
than than indentation of the rune 