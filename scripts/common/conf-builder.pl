#!/usr/bin/perl

use strict;
use warnings;

# Make a copy of the environment variables, so we can delete stuff.
my %ENV_COPY = ( %ENV );

# Hash to store template definitions, based on their names.
# The values are hashes themselves, containing the following keys:
#     prefix:       The prefix used in the template definition. (TMPLT[0-9]+)
#     replaceables: An array of keywords that can be replaced when the template is applied.
#     keys:         A hash containing environment variable names/values, that will be filled by the template.
my %templates;

# Loads all template definitions from environment variables.
# It looks for TMPLT[0-9]+_DEF variables, whose value should be:
#     name_of_the_template(keywords;that;can;be;replaced)
# Any other variables starting with TMPLT[0-9]+ will be recorded, and made part of the template.
sub load_templates {
    for (keys %ENV_COPY) {
        if (m/^(TMPLT[0-9]+)_DEF$/) {
            my $prefix = $1;

            die "Bad template syntax" unless $ENV_COPY{$_} =~ m/^(\w+)\((.*)\)$/;
            my $name = $1;
            my @replaceables = split(/;/, $2);

            $templates{$name} = {
                prefix       => $prefix,
                replaceables => \@replaceables
            };

            delete $ENV_COPY{$_};
        }
    }

    for my $name (keys %templates) {
        my %keys = ();

        for (keys %ENV_COPY) {
            my $prefix = $templates{$name}{prefix};
            if (m/^${prefix}_(.*)$/) {
                $keys{$1} = $ENV_COPY{$_};
                delete $ENV_COPY{$_};
            }
        }

        $templates{$name}{keys} = \%keys;
    }
}

# Applies a template, by creating new environment variables.
# $_[0]: The prefix to apply the template to.
sub fill_template {
    my $prefix = $_[0];
    my $tmplt_envname = $prefix . "_TMPLT";
    if (exists $ENV_COPY{$tmplt_envname}) {
        die "Bad template syntax" unless $ENV_COPY{$tmplt_envname} =~ m/^(\w+)\((.*)\)$/;
        my $tmplt_name = $1;
        my @tmplt_args = split(/;/, $2);

        die "Template $1 not found" unless exists $templates{$tmplt_name};

        my %tmplt = %{$templates{$tmplt_name}};

        die "Too many arguments for template" unless scalar(@tmplt_args) <= scalar(@{$tmplt{replaceables}});

        my %keys_copy = ( %{$tmplt{keys}} );

        for (my $i = 0; $i < scalar @tmplt_args; $i++) {
            for (keys %keys_copy) {
                $keys_copy{$_} =~ s/$tmplt{replaceables}[$i]/$tmplt_args[$i]/;
            }
        }

        delete $ENV_COPY{$tmplt_envname};

        for (keys %keys_copy) {
            my $target_key = $prefix . "_" . $_;
            if (not exists $ENV_COPY{$target_key}) {
                $ENV_COPY{$target_key} = $keys_copy{$_};
            }
        }
    }
}

# Treats the input as an array containing lines.
# Return a new array with the lines all indented.
sub indent {
    return map { "    " . $_ } @_;
}

# Creates the body of a config object by reading environment variables. 
# $_[0]: The prefix to look for in environment variables.
# $_[1]: An array of sub-object description hashes.
# Return an array of lines for the config file.
sub keys_from_env {
    my $prefix = $_[0];
    my @confs = @{ $_[1] };
    
    my @lines;

    # Look for sub-objects based on the given descriptions.
    for (@confs) {
        my $fake_conf = { %{$_} };
        my $old_prefix = $fake_conf->{prefix};
        $fake_conf->{prefix} = "${prefix}_${old_prefix}";
        push @lines, multi_config_from_env($fake_conf);
    }

    fill_template($prefix);

    # Look for environment variables starting with the prefix.
    for (keys %ENV_COPY) {
        if (m/^${prefix}_(.*)$/) {
            my $key = lc($1);
            $key =~ s/[0-9]+$//;
            $key =~ tr/_/ /;
            push @lines, "$key = $ENV_COPY{$_}";
            delete $ENV_COPY{$_};
        }
    }
    return @lines;
}

# Create a single config object.
# $_[0]: Object description hash.
# Return an array of lines for the config file.
sub config_from_env {
    my %conf = %{ $_[0] };

    my @body = keys_from_env($conf{prefix}, $conf{promoted});
    return ($conf{name}, "{", indent(@body), "}", "") if scalar @body;
    return @body;
}

# Create multiple config object using a numbered prefix.
# $_[0]: Object description hash.
# Return an array of lines for the config file.
sub multi_config_from_env {
    my %conf = %{ $_[0] };
        
    my %prefixes;

    # Make a list of all the numbered prefixes.
    for (keys %ENV_COPY) {
        my $prefix = $conf{prefix};
        if (m/^($prefix[0-9]+)_/) {
            $prefixes{$1}++;
        }
    }

    my @lines;

    # Treat each numbered prefix as a new prefix,
    # and create single objects from them.
    for (sort keys %prefixes) {
        my %fake_conf = ( %conf );
        $fake_conf{prefix} = $_;
        my @body = config_from_env(\%fake_conf);
        push @lines, @body;
    }

    return @lines;
}

# Parse an object description.
# $_[0]: The object description encoded in text.
#            They should look like this: (NameOfObject:PREFIX)+{}
#
#            The "+" indicates that it's possible to have multiple instances
#            of this object, so numbered prefixes will be used. (PREFIX1, PREFIX2, etc.)
#
#            Between the "{}" a comma separated list of sub-objects can appear.
#            (FirstSub:FSUB),(SecondSub:FSUB->SSUB)
#            The "->" in the prefix indicates that this sub-object is nested in another
#            sub-object. Sub-objects always use numbered prefixes.  
# Return an object description hash.
#     The hash contains the following values:
#     name:     The name of the object, that will appear in the config file.
#     prefix:   The prefix to use when searching for environment variables.
#     multi:    Whether this object uses numbered prefixes.
#     promoted: An array containing object description hashes for sub-objects.
sub load_config {
    die "Object description error" unless $_[0] =~ m/^\((\w+):(\w+)\)(\+?)\{(.*)\}$/;

    my %new_config = ( 
        name     => $1,
        prefix   => $2,
        multi    => ($3 eq "+"),
        promoted => []
    );

    # Decode sub-objects.    
    for (split /,/, $4) {
        die "Sub-object description error" unless m/^\((\w+):(.+)\)$/;

        my $name = $1;
        my @prefixes = split /->/, $2;

        # Traverse the list of nested prefixes forward to find immediate parent.
        my $container = \%new_config;
        for my $pref (@prefixes[0..$#prefixes - 1]) {
            $container = (grep { $_->{prefix} eq $pref } @{$container->{promoted}})[0];
        }

        my %nested_config = (
            name     => $name,
            prefix   => $prefixes[$#prefixes],
            multi    => 1,
            promoted => []
        );

        push @{$container->{promoted}}, \%nested_config; 
    }

    return \%new_config;
}

print "# Generated from docker container environment settings.\n\n";

# The arguments should each contain an encoded object description.
for (@ARGV) {
    load_templates();
    my $config = load_config($_);
    my @lines;
    if ($config->{multi}) {
        @lines = multi_config_from_env($config);
    } else {
        @lines = config_from_env($config);
    }
    if (scalar @lines) {
        print join "\n", @lines;
        print "\n";
    }
}