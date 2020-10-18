#!/usr/bin/perl

use strict;
use warnings;

print "; Generated from docker container env settings.\n\n";

my $prefix = shift;
my %sections;

for (keys %ENV) {
    if (m/^${prefix}_(.+?)_/) {
        $sections{$1} = 1;
    }
}

for my $section (keys %sections) {
    my $section_name = lc($section);
    print "[$section_name]\n";
    for (keys %ENV) {
        if (m/^${prefix}_${section}_(.*)$/) {
            my $key = lc($1);
            print "$key = $ENV{$_}\n";
        }
    }
    print "\n";
}