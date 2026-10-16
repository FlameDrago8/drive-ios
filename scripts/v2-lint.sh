#!/usr/bin/env bash
#
# v2-lint.sh — the v2 "Road Furniture" design-rule gate (spec §3.5 and §8).
#
# Scans Drive/V2, DriveWidget and Drive/Views/DriveView.swift and exits 1 on:
#   - repeatForever, `loop: true` (and Lottie `loopMode: .loop`)
#   - `onAppear { withAnimation` (also split across lines)
#   - CMMotionManager
#   - `.system(size:` outside the two token files (V2Theme.swift, V2WidgetKit.swift)
#   - emoji inside string literals
#   - a user-facing string literal in Drive/V2 that ends with "!" (best effort)
# Comments are ignored. Exit 0 = clean, 1 = violations, 2 = could not run.
#
# Usage: scripts/v2-lint.sh   (from anywhere in the repo; also run by .githooks/pre-commit)
#

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2
cd "$ROOT" || exit 2

if ! command -v perl >/dev/null 2>&1; then
    echo "v2-lint: perl is required" >&2
    exit 2
fi

FILES="$( { find Drive/V2 DriveWidget -type f -name '*.swift' 2>/dev/null; \
            [ -f Drive/Views/DriveView.swift ] && echo Drive/Views/DriveView.swift; } | sort -u )"
if [ -z "$FILES" ]; then
    echo "v2-lint: no Swift files found under Drive/V2, DriveWidget" >&2
    exit 2
fi

# One file per line on stdin; perl does the scanning (comments and string
# literals need a small tokenizer, which grep can't do).
printf '%s\n' "$FILES" | perl -CSD -e '
use strict;
use warnings;

# Files allowed to set fonts by size: the token files.
my %TOKEN_FILES = map { $_ => 1 } ("Drive/V2/Foundation/V2Theme.swift", "DriveWidget/V2WidgetKit.swift");

# Literals that are not user-facing as written ("file|literal"). V2Tips keeps
# v1 tip titles verbatim and strips the "!" in cleanTitle before display.
my %ALLOW = map { $_ => 1 } ("Drive/V2/Data/V2Tips.swift|Great Drive!");

my $EMOJI = qr/[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}\x{2B00}-\x{2BFF}\x{1F1E6}-\x{1F1FF}\x{FE0F}\x{200D}]/;

my @files = map { chomp; $_ } grep { /\S/ } <STDIN>;
my $problems = 0;

sub report {
    my ($file, $line, $rule, $text) = @_;
    $text =~ s/\s*\n\s*/ /g;
    $text =~ s/^\s+|\s+$//g;
    print "$file:$line: $rule: $text\n";
    $problems++;
}

for my $file (@files) {
    open(my $fh, "<:encoding(UTF-8)", $file) or do { print STDERR "v2-lint: cannot read $file\n"; exit 2 };
    my @lines = <$fh>;
    close $fh;

    my $in_block = 0;     # inside /* */
    my $in_multi = 0;     # inside a """ literal
    my $multi_buf = "";
    my $multi_line = 0;
    my @code;             # per line: code with comments removed, literals emptied
    my @lits;             # [line, literal]

    for my $n (0 .. $#lines) {
        my $src = $lines[$n];
        $src =~ s/\r?\n\z//;
        my $code = "";
        my @mode = ("code");      # code | str | interp
        my @depth;                # paren depth per interp
        my @buf;                  # literal buffers per str
        my $len = length $src;
        my $i = 0;
        while ($i < $len) {
            my $c  = substr($src, $i, 1);
            my $c2 = substr($src, $i, 2);
            my $c3 = substr($src, $i, 3);
            if ($in_block) {
                if ($c2 eq "*/") { $in_block = 0; $i += 2; } else { $i++; }
                next;
            }
            if ($in_multi) {
                if ($c3 eq "\"\"\"") {
                    $in_multi = 0;
                    push @lits, [$multi_line, $multi_buf];
                    $code .= "\"\"";
                    $i += 3;
                } else {
                    $multi_buf .= $c;
                    $i++;
                }
                next;
            }
            my $m = $mode[-1];
            if ($m eq "str") {
                if ($c eq "\\") {
                    my $nx = substr($src, $i + 1, 1);
                    if ($nx eq "(") {
                        $buf[-1] .= " ";
                        push @mode, "interp";
                        push @depth, 1;
                        $code .= "(";
                    } else {
                        $buf[-1] .= $nx;
                    }
                    $i += 2;
                    next;
                }
                if ($c eq "\"") {
                    pop @mode;
                    push @lits, [$n + 1, pop @buf];
                    $code .= "\"";
                    $i++;
                    next;
                }
                $buf[-1] .= $c;
                $i++;
                next;
            }
            # code or interpolation
            if ($c2 eq "//") { last; }
            if ($c2 eq "/*") { $in_block = 1; $i += 2; next; }
            if ($m eq "code" && $c3 eq "\"\"\"") {
                $in_multi = 1;
                $multi_buf = "";
                $multi_line = $n + 1;
                $code .= "\"\"";
                $i += 3;
                next;
            }
            if ($c eq "\"") {
                push @mode, "str";
                push @buf, "";
                $code .= "\"";
                $i++;
                next;
            }
            if ($m eq "interp") {
                if ($c eq "(") { $depth[-1]++; }
                if ($c eq ")") {
                    $depth[-1]--;
                    if ($depth[-1] == 0) { pop @depth; pop @mode; $code .= ")"; $i++; next; }
                }
            }
            $code .= $c;
            $i++;
        }
        # Single-line literals cannot span lines: flush whatever is open.
        while (@buf) { push @lits, [$n + 1, pop @buf]; }
        $multi_buf .= "\n" if $in_multi;
        push @code, $code;
    }

    for my $n (0 .. $#code) {
        my $c = $code[$n];
        my $ln = $n + 1;
        report($file, $ln, "repeatForever is banned (quiet at rest)", $lines[$n]) if $c =~ /repeatForever/;
        report($file, $ln, "looping animation is banned", $lines[$n]) if $c =~ /loop:\s*true|loopMode:\s*\.loop\b/;
        report($file, $ln, "CMMotionManager is banned in UI code", $lines[$n]) if $c =~ /CMMotionManager/;
        if (!$TOKEN_FILES{$file} && $c =~ /\.system\(\s*size:/) {
            report($file, $ln, ".system(size:) outside the token files; use V2Type / V2WType", $lines[$n]);
        }
    }

    # onAppear { withAnimation, including the brace or the call on the next line.
    my $joined = join("\n", @code);
    while ($joined =~ /onAppear\s*(?:\(\s*perform:\s*)?\{\s*(?:\[[^\]]*\]\s*in\s*)?withAnimation/g) {
        my $at = $-[0];
        my $ln = (substr($joined, 0, $at) =~ tr/\n//) + 1;
        report($file, $ln, "onAppear { withAnimation is banned; start one-shot motion from .task or a state change",
               $lines[$ln - 1]);
    }

    for my $lit (@lits) {
        my ($ln, $text) = @$lit;
        if ($text =~ $EMOJI) {
            report($file, $ln, "emoji in a string literal", "\"$text\"");
        }
        if ($file =~ m{^Drive/V2/} && $text =~ /\p{L}/ && $text =~ /!\s*\z/ && !$ALLOW{"$file|$text"}) {
            report($file, $ln, "exclamation mark ending a string literal (v2 voice has none)", "\"$text\"");
        }
    }
}

if ($problems) {
    print "v2-lint: $problems problem" . ($problems == 1 ? "" : "s") . " found\n";
    exit 1;
}
print "v2-lint: clean (" . scalar(@files) . " files)\n";
exit 0;
'
