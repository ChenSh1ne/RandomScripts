#!/usr/bin/env perl
use warnings;
use strict;
use Pod::Usage;
use Getopt::Long qw(GetOptions);
Getopt::Long::Configure qw(gnu_getopt);

#This script takes an AGP and a GFF on scaffolds, and outputs a GFF in
#chromosomal coordinate space.

my $SCRIPTNAME = "ScaffoldGFFtoChromosomeGFF.pl";
my $VERSION = "1.0";

=pod

=head1 NAME

ScaffoldGFFtoChromosomeGFF.pl - Convert scaffold-based GFF to chromosome-based GFF using AGP

=head1 SYNOPSIS

ScaffoldGFFtoChromosomeGFF.pl -a [AGP file] -g [Scaffold GFF3 file] > [Chromosome GFF3 file]

 Options:
  --help,-h,-?		Display this help documentation
  --version,-v          Output version string
 Mandatory:
  --agp,-a		AGP file mapping scaffolds to chromosomes
  --gff,-g		GFF3 file of features in scaffold-space

=head1 DESCRIPTION

ScaffoldGFFtoChromosomeGFF.pl converts a GFF3 from scaffold-space into
chromosome-space using an AGP file that maps scaffolds to chromosomes.

=cut

#Initialize the input parameters
my $help = 0;
my $man = 0;
my $debug = 0;
my $input_agp = "";
my $input_gff = "";
my $dispversion = 0;

#Fetch the command line parameters
GetOptions('version|v' => \$dispversion, 'help|h|?+' => \$help, 'agp|a=s' => \$input_agp, 'gff|g=s' => \$input_gff, 'debug|d' => \$debug, man => \$man) or pod2usage(2);
pod2usage(-exitval => 1, -verbose => $help, -output => \*STDERR) if $help;
pod2usage(-exitval => 0, -verbose => 2, -output => \*STDERR) if $man;

print STDERR "${SCRIPTNAME} version ${VERSION}\n" if $dispversion;
exit 0 if $dispversion;

pod2usage(-exitval => 2, -output => \*STDERR) if $input_agp eq "" or $input_gff eq "";

#Make sure the required parameters are filled out correctly
unless (-e $input_agp) {
   print STDERR "The AGP input file does not exist.\n";
   exit 3;
}
unless (-e $input_gff) {
   print STDERR "The GFF3 input file does not exist.\n";
   exit 4;
}

#Set up the hashes for translating scaffolds to chromosomes:
my %chromosomes = ();
my %offsets = ();
my %orientations = ();
my %chrom_headers = ();

#Read through the AGP and fill the aforementioned hashes:
print STDERR "Reading AGP\n";
open(AGP, "<", $input_agp);
while (!eof(AGP)) {
   my $line = <AGP>;
   my @agp_parts = split /\t/, $line;
   next if $agp_parts[4] eq "N" or $agp_parts[4] eq "U"; #Skip gap lines
   
   #Collect the important information for superscaffolds:
   my $chrom = $agp_parts[0];
   my $chrom_start = $agp_parts[1];
   my $chrom_end = $agp_parts[2];
   my $scaffold = $agp_parts[5];
   my $scaf_start = $agp_parts[6];
   my $scaf_end = $agp_parts[7];
   my $scaf_orientation = $agp_parts[8];
   
   #Fill the hashes:
   $chromosomes{$scaffold} = $chrom;
   #Offset for negative orientation is the larger position, for positive is smaller:
   $offsets{$scaffold} = $scaf_orientation eq "-" ? $chrom_end : $chrom_start;
   $orientations{$scaffold} = $scaf_orientation;
   $chrom_headers{$chrom} = join(" ", $chrom_start, $chrom_end);
}
close(AGP);
print STDERR "Done reading AGP, found ", scalar(keys %chromosomes), " scaffolds\n";

#Read through the GFF3, and modify the chromosome/scaffold, start, end, and
# orientation fields according to the hashes derived from the AGP:
my @gff_headers = ();
print STDERR "Reading scaffold-based GFF3 and outputting chromosome-based GFF3\n";
open(GFF, "<", $input_gff);
while (!eof(GFF)) {
   my $line = <GFF>;
   #Accumulate headers
   if ($line =~ /^##/) {
      chomp $line;
      push @gff_headers, $line unless $line =~ /sequence-region/;
      if ($line =~ /sequence-region/) { #Keep if scaffold missing from AGP
         my ($headertype, $scaffold, $scaf_start, $scaf_end) = split /\s+/, $line, 4;
         push @gff_headers, $line unless exists($chromosomes{$scaffold});
      }
      next;
   }
   #Add the revised sequence-region headers once we're onto the records:
   if ($line !~ /^##/ and scalar@gff_headers > 0) {
      #Output the accumulated headers:
      print STDOUT join("\n", @gff_headers), "\n";
      #Output the sorted chromosome headers:
      for my $chrom (sort keys %chrom_headers) {
         print STDOUT join(" ", "##sequence-region", $chrom, $chrom_headers{$chrom}), "\n";
      }
      @gff_headers = ();
   }
   #Parse important elements out of the GFF3 records:
   my @gff_parts = split /\t/, $line;
   my $scaffold = $gff_parts[0];
   unless (exists($chromosomes{$scaffold})) { #Skip unanchored scaffolds
      print STDOUT $line;
      print STDOUT "#${scaffold} not mapped to a chromosome\n" if $debug;
      next;
   }
   my $feature_start = $gff_parts[3];
   my $feature_end = $gff_parts[4];
   my $feature_orientation = $gff_parts[6];
   
   #Perform the conversions:
   $gff_parts[0] = $chromosomes{$scaffold};
   if ($orientations{$scaffold} eq "-") {
      #Flipping orientation, start becomes end, end becomes start:
      $gff_parts[3] = $offsets{$scaffold} - $feature_end - 1;
      $gff_parts[4] = $offsets{$scaffold} - $feature_start - 1;
      $gff_parts[6] = $feature_orientation eq "-" ? "+" : "-";
   } else {
      $gff_parts[3] = $offsets{$scaffold} + $feature_start - 1;
      $gff_parts[4] = $offsets{$scaffold} + $feature_end - 1;
      $gff_parts[6] = $feature_orientation;
   }

   #Print the modified GFF line:
   print STDOUT join("\t", @gff_parts);
}
close(GFF);
print STDERR "Done reading scaffold-based GFF3 and outputting chromosome-based GFF3\n";

exit 0;
