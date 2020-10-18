#!/usr/bin/perl

use strict;
use warnings;

my %ENV_COPY = ( %ENV );

sub indent {
    return map { "    " . $_ } @_;
}

sub keys_from_env {
    my @lines; 

    for (@{$_[1]}) {
        my $fake_conf = { %{$_} };
        $fake_conf->{"prefix"} = "$_[0]_$fake_conf->{\"prefix\"}";
        push(@lines, multi_config_from_env($fake_conf));
    }

    for (keys %ENV_COPY) {
        if (m/^$_[0]_(.*)$/) {
            my $key = lc($1);
            $key =~ s/[0-9]+$//;
            $key =~ tr/_/ /;
            push(@lines, "$key = $ENV_COPY{$_}");
            delete $ENV_COPY{$_};
        }
    }
    return @lines;
}

sub config_from_env {
    my @body = keys_from_env($_[0]->{"prefix"}, $_[0]->{"promoted"});
    return ($_[0]->{"name"}, "{", indent(@body), "}", "") if scalar(@body);
    return @body;
}

sub multi_config_from_env {
    my @lines;
    my %prefixes;

    for (keys %ENV_COPY) {
        my $prefix = $_[0]->{"prefix"};
        if (m/^($prefix[0-9]+)_/) {
            $prefixes{$1} = 1;
        }
    }

    for (sort keys %prefixes) {
        my $fake_conf = { %{$_[0]} };
        $fake_conf->{"prefix"} = $_;
        my @body = config_from_env($fake_conf);
        push(@lines, @body);
    }

    return @lines;
}

sub load_config {
    die "input error" unless $_[0] =~ m/\((\w+):(\w+)\)(\+?)\{(.*)\}/;

    my %new_config = ( 
        name     => $1,
        prefix   => $2,
        multi    => ($3 eq "+")
    );
    
    for (split(/,/, $4)) {
        die "input error" unless m/\((\w+):(.+)\)/;
        my @prefixes = split(/->/, $2);
        my $container = \%new_config;
        for my $pref (@prefixes[0..$#prefixes - 1]) {
            $container = (grep { $_->{"prefix"} eq $pref } @{$container->{"promoted"}})[0];
        }

        my %nested_config = (
            name     => $1,
            prefix   => $prefixes[$#prefixes],
            multi    => 1
        );

        push @{$container->{"promoted"}}, \%nested_config; 
    }

    return \%new_config;
}

print "# Generated from docker container env settings.\n\n";

for (@ARGV) {
    my $config = load_config($_);
    my @lines;
    if ($config->{"multi"}) {
        @lines = multi_config_from_env($config);
    } else {
        @lines = config_from_env($config);
    }
    if (scalar(@lines)) {
        print join "\n", @lines;
        print "\n";
    }
}