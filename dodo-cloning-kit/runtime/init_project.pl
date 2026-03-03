#!/usr/bin/env perl

use strict;
use warnings;
use Cwd;
use File::Copy;

my $MAKEFILE = <<ENDL;
include weigelt-lab/Makefile
ENDL

unless (-e "Makefile") {
    open OUT, ">Makefile";
    print OUT $MAKEFILE;
}
close OUT;

unless (-e "project_config.yaml") {
    copy("weigelt-lab/default_yaml/project_config.yaml", "project_config.yaml") or die "Unable to create project_config.yaml: $!";
}

unless (-e "summary_config.yaml") {
    copy("weigelt-lab/default_yaml/summary_config.yaml", "summary_config.yaml") or die "Unable to create summary_config.yaml: $!";
}

mkdir "html_dashboard" or die "Unable to create html dashboard: $!";
copy("weigelt-lab/html_dashboard/Project_Dashboard.html", "html_dashboard/Project_Dashboard.html") or die "Unable to create Project_Dashboard.html: $!";
copy("weigelt-lab/html_dashboard/Facets_Dashboard.html", "html_dashboard/Facets_Dashboard.html") or die "Unable to create Facets_Dashboard.html: $!";
